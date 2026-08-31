#!/usr/bin/env python3
"""Gauntlet guard runner — the deterministic half of every transition gate.

    run.py <guard> <nonce> [<argument>]

Looks the guard up by name in <repo>/.gauntlet/config.json, runs it with all output
captured to <repo>/.gauntlet/runs/<nonce>.log, and prints exactly one JSON line:

    {"nonce", "guard", "exitCode", "receipt", "tail", "offenders"?}

`preflight <ref> [--from <stage>]` is the skill's entry point, run in the operator's session
with no model in the loop: leaves main, mints .gauntlet/run-secret, resolves the ticket by
origin (a GitHub issue number or a markdown path) into .gauntlet/ticket.json, refuses a body
without Given/When/Then criteria, then runs clean-tree, install, setup, build and coverage —
plus `spec green` when re-entering past the coder. Prints one JSON line the skill hands to
the workflow as args: {"ok", "repoRoot", "headSha", "branch", "secret", "ticket", "from",
"failed"?, "tail"?}. Every stage and later guard reads the ticket from disk; it never
crosses a conduit.

`gate <nonce> specify|code` runs one transition's whole guard chain in this process and
prints one line — `specify` = clean-tree, spec red; `code` = clean-tree, spec green, build,
coverage (retried once on exit 1), reachability, crap, depth. Each guard logs under
<nonce>-<guard>. The chain stops only where the next guard would have no input: a dirty
tree, a red build, coverage still red after its retry, or any exit 2. Every other red keeps
going, so one retry prompt carries every finding at once. Adds {"failed": the most upstream
red guard or null, "head", "findings": {guard: {exitCode, tail, offenders?, problems?}}};
`exitCode` is that guard's. `failed` and `head` are branch fields — the receipt signs
secret:nonce:exitCode:failed-or-dash:head — so a conduit that renames the red guard is
caught the same way as one that drops HEAD. A dirty tree is exit 1 here (the stage's
fault — commit), not clean-tree's standalone 2.

`reachability <nonce>` requires every production file the branch adds to be an edge
(config.edges globs — routes, pages, handlers the runtime reaches by itself) or to be
imported, transitively, from an edge or a pre-existing file. Red names the orphans.

`depth <nonce>` requires every production file the branch adds to carry at least
config.depth.ceiling (default 15) implementation lines per exported symbol — Ousterhout's
depth, operationalised: it fails pass-throughs and barrels. Adds {"offenders"}.

`spec <nonce> red|green` reads the ticket's `- [ ] Given … when … then …` criteria, runs
config.acceptance.run, and requires exactly one test named after each criterion (and no
stray test in the same files): `red` = every criterion test fails on the untouched tree,
`green` = every one passes. Mocking a module under sourcePaths in an acceptance file is
exit 1. Adds {"criteria", "tests", "problems"}.

`qa <nonce>` runs four phases: start config.serve.run; wait inside the serve.startup window
until every serve.ready probe answers its expected status serve.successes times in a row
(a bare string probe expects anything below 500; default probe is serve.url); send each
serve.warmup request once, in order, straight to serve.url (statuses logged, never judged);
then put a counting relay in front of serve.url, run the QA stage's .gauntlet/qa/<nonce>.sh
with GAUNTLET_URL set to the relay, and read its `PASS <criterion>` / `FAIL <criterion>`
lines. Only the last phase can be exit 1: any FAIL (or none of either), or zero requests
through the relay (the script proved nothing against the served system). The first three
are environment: a probe that never becomes ready or a warm-up that never answers is exit 2,
a port that already has a listener is exit 2 without starting serve.run (an orphaned server
would otherwise be judged as the product). The relay never retries; its own failures are
status 599 with an X-Gauntlet-Relay-Error header so they cannot read as the product's. No
serve in config is exit 0 with "skipped". The server is always stopped. Adds {"passed",
"failed", "requests"} or {"skipped"}.

`qa-dry <nonce>` is the QA stage's own calibration run of the same script: identical to
`qa` but adds {"output"} — the script's full stdout and stderr — prints no receipt, and is
capped at 3 per nonce (the 4th is exit 2). A harness that has never been seen to run is as
untrustworthy as a test that has never been seen to fail; the guard still serves fresh and
runs the script itself, so the dry-run can calibrate the instrument but never supply the
verdict.

`verdict <nonce>` writes .gauntlet/verdict-<HEAD>.json = {"sha", "clean": true, "source":
"gauntlet"} — the artefact the pre-PR hook requires. The workflow mints it only after
every gate is green; it is the machine's signature on HEAD, replacing the review stage's.

The workflow verifies `receipt` (FNV-1a over the per-run secret, nonce and exit code —
and HEAD, when the guard reports it, so `clean-tree`'s `head` is a branch field too)
so a relayed result that never came from this script is rejected as a conduit error.
Exit codes: 0 pass, 1 guard failed (code), 2 operational (infra / harness / protected
file edited), 127 unknown guard. The process itself always exits 0 — the verdict is the
JSON, never the runner's own status.
"""
import http.server
import json
import os
import re
import secrets
import signal
import subprocess
import sys
import threading
import time
import socket
import urllib.error
import urllib.parse
import urllib.request
from fnmatch import fnmatch
from pathlib import Path

LOCKFILE_INSTALL = [
    ("pnpm-lock.yaml", "pnpm install"),
    ("package-lock.json", "npm ci"),
    ("yarn.lock", "yarn install"),
    ("bun.lockb", "bun install"),
]
TAIL_CHARS = 3000


def git(root: Path, *argv: str) -> str:
    return subprocess.run(["git", *argv], cwd=root, capture_output=True, text=True).stdout.strip()


def fnv1a32(text: str) -> str:
    digest = 0x811C9DC5
    for byte in text.encode():
        digest = ((digest ^ byte) * 0x01000193) & 0xFFFFFFFF
    return f"{digest:08x}"


def changed_files(root: Path) -> list[str]:
    tracked = git(root, "diff", "--name-only", "HEAD").splitlines()
    untracked = git(root, "ls-files", "--others", "--exclude-standard").splitlines()
    return sorted(set(tracked + untracked))


def install_command(root: Path, config: dict) -> str | None:
    if config.get("install"):
        return config["install"]
    for lockfile, command in LOCKFILE_INSTALL:
        if (root / lockfile).exists():
            return command
    return None


def crap_command(config: dict) -> str:
    guard = Path(__file__).with_name("crap-guard.py")
    coverage = " ".join(f'--coverage "{s.get("output", "coverage/coverage-final.json")}"' for s in config["coverage"])
    sources = " ".join(config.get("sourcePaths") or ["src"])
    return f'python3 "{guard}" --changed-only {coverage} --format auto {sources}'


def coverage_command(config: dict) -> str:
    steps = [f'({s["run"]}) && ls "{s.get("output", "coverage/coverage-final.json")}" >/dev/null' for s in config["coverage"]]
    return " && ".join(steps)


def fetch_ticket(issue: str) -> dict:
    fetched = subprocess.run(["gh", "issue", "view", issue, "--json", "title,body"], capture_output=True, text=True)
    if fetched.returncode != 0:
        return {"exitCode": 2, "tail": fetched.stderr.strip() or f"gh issue view {issue} failed"}
    ticket = json.loads(fetched.stdout)
    body = ticket.get("body") or ""
    if not body.strip():
        return {"exitCode": 2, "tail": f"issue {issue} has an empty body"}
    return {"exitCode": 0, "title": ticket.get("title", ""), "body": body}


def read_ticket_file(path: Path) -> dict:
    text = path.read_text()
    heading = re.search(r"^#\s+(.+?)\s*$", text, re.MULTILINE)
    title = heading.group(1) if heading else path.stem
    return {"exitCode": 0, "title": title, "body": text}


def resolve_ticket(ref: str) -> dict:
    if re.fullmatch(r"\d+", ref):
        return fetch_ticket(ref)
    path = Path(ref).expanduser()
    if path.is_file():
        return read_ticket_file(path)
    return {"exitCode": 2, "tail": f"unknown ticket origin: {ref!r} is neither an issue number nor a readable file"}


CRITERION = re.compile(r"^\s*-\s*\[[ xX]\]\s*(given\b.+?)\s*$", re.IGNORECASE | re.MULTILINE)
SOURCE_MOCK = re.compile(r"\b(?:jest|vi)\.(?:do)?[mM]ock\(\s*['\"]([^'\"]+)['\"]")
ALIAS_PREFIXES = ("./", "../", "@/", "~/", "#", "src/")


def normalise(text: str) -> str:
    return " ".join(text.split()).lower()


def criteria_from(body: str) -> list[str]:
    return [" ".join(match.split()) for match in CRITERION.findall(body)]


def acceptance_tests(report: dict) -> list[dict]:
    if "testResults" in report:
        return [
            {"file": suite.get("name", ""), "name": test.get("fullName") or test.get("title", ""), "status": test.get("status", "")}
            for suite in report["testResults"]
            for test in suite.get("assertionResults", [])
        ]
    tests: list[dict] = []

    def walk(suite: dict, titles: list[str]) -> None:
        path = titles + ([suite["title"]] if suite.get("title") else [])
        for spec in suite.get("specs", []):
            statuses = [result.get("status") for test in spec.get("tests", []) for result in test.get("results", [])]
            status = "passed" if statuses and all(status in ("passed", "expected") for status in statuses) else "failed"
            tests.append({"file": suite.get("file", ""), "name": " ".join(path + [spec.get("title", "")]), "status": status})
        for child in suite.get("suites", []):
            walk(child, path)

    for suite in report.get("suites", []):
        walk(suite, [])
    return tests


def match_criteria(criteria: list[str], tests: list[dict]) -> tuple[dict[str, dict], list[str]]:
    matched: dict[str, dict] = {}
    problems: list[str] = []
    for criterion in criteria:
        hits = [test for test in tests if normalise(criterion) in normalise(test["name"])]
        if len(hits) != 1:
            problems.append(f"{len(hits)} tests named after criterion: {criterion}")
            continue
        matched[criterion] = hits[0]
    files = {test["file"] for test in matched.values()}
    claimed = {id(test) for test in matched.values()}
    for test in tests:
        if test["file"] in files and id(test) not in claimed:
            problems.append(f"test matches no criterion: {test['name']}")
    return matched, problems


def surfaces_for(root: Path, matched: dict, serve: dict | None) -> list[str]:
    surfaces = (serve or {}).get("surfaces") or {}
    selected: set[str] = set()
    for test in matched.values():
        file = test["file"]
        path = os.path.relpath(file, root) if os.path.isabs(file) else file
        for name, surface in surfaces.items():
            if fnmatch(path, surface.get("paths", "")):
                selected.add(name)
    return sorted(selected)


def source_mocks(root: Path, pattern: str, source_paths: list[str]) -> list[str]:
    prefixes = ALIAS_PREFIXES + tuple(f"{path.rstrip('/')}/" for path in source_paths)
    found: list[str] = []
    for file in sorted(root.glob(pattern)):
        for target in SOURCE_MOCK.findall(file.read_text()):
            if target.startswith(prefixes):
                found.append(f"{file.relative_to(root)} mocks {target}")
    return found


def spec_guard(mode: str, root: Path, config: dict, log: Path) -> dict:
    ticket_file = root / ".gauntlet" / "ticket.json"
    acceptance = config.get("acceptance")
    if not ticket_file.exists():
        return {"exitCode": 2, "tail": "no .gauntlet/ticket.json — run the ticket guard first"}
    if not acceptance or mode not in ("red", "green"):
        return {"exitCode": 2, "tail": "config.acceptance {run, output, pattern} and a mode of red|green are required"}
    criteria = criteria_from(json.loads(ticket_file.read_text())["body"])
    if not criteria:
        return {"exitCode": 1, "criteria": [], "tail": "ticket has no 'Given …, when …, then …' acceptance criteria"}
    mocks = source_mocks(root, acceptance["pattern"], config.get("sourcePaths") or ["src"])
    if mocks:
        return {"exitCode": 1, "criteria": criteria, "problems": mocks, "tail": "acceptance tests mock the system under test:\n" + "\n".join(mocks)}
    output = root / acceptance.get("output", "acceptance.json")
    if output.exists():
        output.unlink()
    with log.open("w") as sink:
        sink.write(f"$ {acceptance['run']}\n")
        sink.flush()
        subprocess.run(["bash", "-c", acceptance["run"]], cwd=root, stdout=sink, stderr=subprocess.STDOUT)
    if not output.exists():
        return {"exitCode": 2, "criteria": criteria, "tail": log.read_text()[-TAIL_CHARS:]}
    tests = acceptance_tests(json.loads(output.read_text()))
    matched, problems = match_criteria(criteria, tests)
    serve = config.get("serve")
    if serve and serve.get("surfaces") is not None:
        (root / ".gauntlet" / "surfaces.json").write_text(json.dumps(surfaces_for(root, matched, serve)))
    wanted = "failed" if mode == "red" else "passed"
    for criterion, test in matched.items():
        if test["status"] != wanted:
            problems.append(f"expected {wanted} in {mode} mode but was {test['status']}: {criterion}")
    return {
        "exitCode": 1 if problems else 0,
        "criteria": criteria,
        "tests": {criterion: test["name"] for criterion, test in matched.items()},
        "problems": problems,
        "tail": "\n".join(problems) if problems else log.read_text()[-TAIL_CHARS:],
    }


CODE_SUFFIXES = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts", ".py", ".astro", ".svelte", ".vue"}
TEST_FILE = re.compile(r"\.(?:spec|test|stories)\.[cm]?[jt]sx?$|(?:^|/)(?:tests?|__tests__|__mocks__)/")
IMPORT_SPECIFIER = re.compile(r"""(?:\bfrom|\bimport|\brequire\()\s*['"]([^'"]+)['"]""")
MODULE_SUFFIX = re.compile(r"\.[cm]?[jt]sx?$")
EXPORT_DECLARATION = re.compile(r"^export\s+(?:default\s+)?(?:async\s+)?(?:const|let|var|function\*?|class|abstract\s+class|type|interface|enum|namespace)\b|^export\s+default\b", re.MULTILINE)
EXPORT_LIST = re.compile(r"^export\s*(?:type\s*)?\{([^}]*)\}", re.MULTILINE)
EXPORT_STAR = re.compile(r"^export\s+\*", re.MULTILINE)
PY_PUBLIC = re.compile(r"^(?:def|class)\s+[A-Za-z]", re.MULTILINE)
NOT_IMPLEMENTATION = re.compile(r"^\s*(?:import\b|export\s.*\bfrom\b|export\s*\{|//|/\*|\*|#|[{}()\[\];,]*$)")
DEFAULT_DEPTH_CEILING = 15


def merge_base(root: Path) -> str:
    for upstream in ("origin/HEAD", "main", "master"):
        base = git(root, "merge-base", "HEAD", upstream)
        if base:
            return base
    return ""


def is_production(path: str, source_paths: list[str]) -> bool:
    under_sources = path.startswith(tuple(f"{source.rstrip('/')}/" for source in source_paths))
    return under_sources and Path(path).suffix in CODE_SUFFIXES and not TEST_FILE.search(path)


def added_production_files(root: Path, config: dict) -> list[str]:
    base = merge_base(root)
    if not base:
        return []
    sources = config.get("sourcePaths") or ["src"]
    added = git(root, "diff", "--name-only", "--diff-filter=A", f"{base}..HEAD").splitlines()
    return sorted(path for path in added if is_production(path, sources))


def module_names(path: str) -> set[str]:
    without_suffix = MODULE_SUFFIX.sub("", path) if MODULE_SUFFIX.search(path) else str(Path(path).with_suffix(""))
    names = {without_suffix}
    if Path(without_suffix).name == "index":
        names.add(str(Path(without_suffix).parent))
    return names


def references(specifier: str, importer: str, candidate: str) -> bool:
    names = module_names(candidate)
    target = MODULE_SUFFIX.sub("", specifier)
    if target.startswith("."):
        resolved = os.path.normpath(os.path.join(os.path.dirname(importer), target))
        return resolved in names or f"{resolved}/index" in names
    tail = "/" + target.split("/", 1)[1] if "/" in target and target[0] in "@~#" else "/" + target
    return any(name == target or name.endswith(tail) for name in names)


def reachability_guard(root: Path, config: dict) -> dict:
    added = added_production_files(root, config)
    edges = config.get("edges") or []
    reached = {path for path in added if any(fnmatch(path, edge) for edge in edges)}
    orphans = [path for path in added if path not in reached]
    if not orphans:
        return {"exitCode": 0, "added": added, "problems": []}
    sources = config.get("sourcePaths") or ["src"]
    code = [path for path in git(root, "ls-files").splitlines() if is_production(path, sources)]
    imports = {path: IMPORT_SPECIFIER.findall((root / path).read_text(errors="ignore")) for path in code}
    frontier = (set(code) - set(added)) | reached
    grew = True
    while grew:
        grew = False
        for candidate in orphans:
            if candidate in reached:
                continue
            if any(references(specifier, importer, candidate) for importer in frontier for specifier in imports.get(importer, [])):
                reached.add(candidate)
                frontier.add(candidate)
                grew = True
    problems = [f"{path} is reached by nothing: not an edge and imported from no edge or pre-existing file" for path in orphans if path not in reached]
    return {"exitCode": 1 if problems else 0, "added": added, "problems": problems, "tail": "\n".join(problems)}


def export_count(text: str, suffix: str) -> int:
    if suffix == ".py":
        return len(PY_PUBLIC.findall(text))
    listed = sum(len([name for name in group.split(",") if name.strip()]) for group in EXPORT_LIST.findall(text))
    return len(EXPORT_DECLARATION.findall(text)) + listed + len(EXPORT_STAR.findall(text))


def implementation_lines(text: str) -> int:
    return sum(1 for line in text.splitlines() if line.strip() and not NOT_IMPLEMENTATION.match(line))


def depth_guard(root: Path, config: dict) -> dict:
    ceiling = float((config.get("depth") or {}).get("ceiling", DEFAULT_DEPTH_CEILING))
    offenders = []
    for path in added_production_files(root, config):
        text = (root / path).read_text(errors="ignore")
        exports = export_count(text, Path(path).suffix)
        if not exports:
            continue
        lines = implementation_lines(text)
        depth = round(lines / exports, 1)
        if depth < ceiling:
            offenders.append({"file": path, "exports": exports, "lines": lines, "depth": depth})
    tail = "\n".join(f"{o['file']}: {o['lines']} implementation lines over {o['exports']} exports = depth {o['depth']} (ceiling {ceiling:g})" for o in offenders)
    return {"exitCode": 1 if offenders else 0, "ceiling": ceiling, "offenders": offenders, "tail": tail}


QA_LINE = re.compile(r"^(PASS|FAIL)\s+(.+?)\s*$", re.MULTILINE)
SERVE_TIMEOUT = 60
DRY_RUN_CAP = 3


READY_PROBE_TIMEOUT = 15
READY_INTERVAL = 1
READY_SUCCESSES = 2
WARMUP_TIMEOUT = 90
RELAY_ERROR_STATUS = 599
RELAY_ERROR_HEADER = "X-Gauntlet-Relay-Error"
UPSTREAM_TIMEOUT = 60


def ready_probes(serve: dict) -> list[dict]:
    declared = serve.get("ready", serve["url"])
    probes = declared if isinstance(declared, list) else [declared]
    return [normalise_probe(probe) for probe in probes]


def normalise_probe(probe: str | dict) -> dict:
    if isinstance(probe, str):
        return {"url": probe, "expect": None, "timeout": READY_PROBE_TIMEOUT}
    expect = probe.get("expect", 200)
    return {"url": probe["url"], "expect": [expect] if isinstance(expect, int) else list(expect), "timeout": float(probe.get("timeout", READY_PROBE_TIMEOUT))}


def probe_status(probe: dict) -> int | None:
    try:
        with urllib.request.urlopen(probe["url"], timeout=probe["timeout"]) as response:
            return response.status
    except urllib.error.HTTPError as response:
        response.close()
        return response.code
    except (urllib.error.URLError, OSError):
        return None


def probe_matches(probe: dict, status: int | None) -> bool:
    if status is None:
        return False
    if probe["expect"] is None:
        return status < 500
    return status in probe["expect"]


def describe_probe(probe: dict) -> str:
    expected = "below 500" if probe["expect"] is None else "/".join(str(code) for code in probe["expect"])
    return f"{probe['url']} expecting {expected}"


def wait_for_ready(serve: dict, probes: list[dict] | None = None) -> list[str]:
    probes = ready_probes(serve) if probes is None else probes
    startup = float(serve.get("startup", serve.get("timeout", SERVE_TIMEOUT)))
    interval = float(serve.get("interval", READY_INTERVAL))
    successes = int(serve.get("successes", READY_SUCCESSES))
    streaks = [0] * len(probes)
    deadline = time.monotonic() + startup
    while True:
        for index, probe in enumerate(probes):
            if streaks[index] >= successes:
                continue
            streaks[index] = streaks[index] + 1 if probe_matches(probe, probe_status(probe)) else 0
        if all(streak >= successes for streak in streaks):
            return []
        if time.monotonic() >= deadline:
            return [f"{describe_probe(probe)} ({streaks[index]}/{successes} consecutive)" for index, probe in enumerate(probes) if streaks[index] < successes]
        time.sleep(interval)


def warm_up(serve: dict, sink) -> str | None:
    items = serve.get("warmup", [])
    if not items:
        return None
    base = serve["url"].rstrip("/")
    for item in items:
        if isinstance(item, str):
            method, _, path = item.partition(" ")
            item = {"method": method, "path": path}
        method = item.get("method", "GET").upper()
        path = item["path"]
        body = item["body"].encode() if "body" in item else None
        headers = {"Content-Type": "application/json"} if body else {}
        request = urllib.request.Request(base + path, data=body, method=method, headers=headers)
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=float(item.get("timeout", WARMUP_TIMEOUT))) as response:
                status = response.status
        except urllib.error.HTTPError as response:
            status = response.code
            response.close()
        except (urllib.error.URLError, OSError) as error:
            return f"warm-up {method} {path} did not answer: {error}"
        sink.write(f"[warmup] {method} {path} -> {status}\n")
        sink.flush()
    return None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


HOP_BY_HOP = {"connection", "keep-alive", "transfer-encoding", "content-length", "host", "proxy-connection", "te", "trailer", "upgrade"}


class WireEvidence(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, upstream: str, upstream_timeout: float = UPSTREAM_TIMEOUT):
        super().__init__(("127.0.0.1", 0), RelayHandler)
        self.upstream = upstream.rstrip("/")
        self.upstream_timeout = upstream_timeout
        self.requests = 0
        self.lock = threading.Lock()

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.server_address[1]}/"


class RelayHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args) -> None:
        return

    def relay(self) -> None:
        server: WireEvidence = self.server  # type: ignore[assignment]
        with server.lock:
            server.requests += 1
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        headers = {name: value for name, value in self.headers.items() if name.lower() not in HOP_BY_HOP}
        request = urllib.request.Request(server.upstream + self.path, data=body, method=self.command, headers=headers)
        try:
            response = urllib.request.build_opener(NoRedirect).open(request, timeout=server.upstream_timeout)
        except urllib.error.HTTPError as error:
            response = error
        except (urllib.error.URLError, OSError) as error:
            self.relay_error("upstream did not answer", f"{server.upstream}: {error}")
            return
        try:
            payload = response.read()
        except (urllib.error.URLError, OSError) as error:
            self.relay_error("upstream broke off mid-response", f"{server.upstream}: {error}")
            return
        finally:
            response.close()
        self.send_response(response.status)
        for name, value in response.headers.items():
            if name.lower() not in HOP_BY_HOP:
                self.send_header(name, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def relay_error(self, kind: str, detail: str) -> None:
        payload = f"gauntlet relay: {kind} — {detail}".encode()
        self.send_response(RELAY_ERROR_STATUS)
        self.send_header(RELAY_ERROR_HEADER, kind)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = relay


def listener_on(port: int) -> bool:
    with socket.socket() as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def listeners(port: int) -> str:
    probe = subprocess.run(["ss", "-ltnp", f"sport = :{port}"], capture_output=True, text=True)
    return probe.stdout.strip()


def env_suffix(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", name).upper()


def selected_targets(root: Path, serve: dict) -> tuple[list[tuple[str, dict]], str | None]:
    surfaces = serve.get("surfaces")
    if not surfaces:
        return [("", serve)], None
    selection = root / ".gauntlet" / "surfaces.json"
    selected = json.loads(selection.read_text()) if selection.exists() else []
    if not selected:
        return [], "no acceptance criterion maps to a served surface — check config.serve.surfaces paths against the acceptance test locations"
    inherited = {key: value for key, value in serve.items() if key != "surfaces"}
    return [(name, {**inherited, **surfaces[name]}) for name in selected], None


def starvation_message(starved: list[str]) -> str:
    named = [name for name in starved if name]
    if named:
        return f"surfaces {named} received 0 requests to the served system through GAUNTLET_URL_<surface> — the script proved nothing against them from the outside:\n"
    return "QA made 0 requests to the served system through GAUNTLET_URL — the script proved nothing from the outside:\n"


def qa_guard(root: Path, config: dict, nonce: str, log: Path, full_output: bool = False) -> dict:
    serve = config.get("serve")
    if not serve:
        return {"exitCode": 0, "skipped": True, "tail": "no serve in config — QA skipped"}
    script = root / ".gauntlet" / "qa" / f"{nonce}.sh"
    if not script.exists():
        return {"exitCode": 2, "tail": f"no QA script at {script.relative_to(root)}"}
    targets, selection_error = selected_targets(root, serve)
    if selection_error:
        return {"exitCode": 1, "tail": selection_error}
    for _, target in targets:
        port = urllib.parse.urlparse(target["url"]).port
        if port and listener_on(port):
            message = f"environment: 127.0.0.1:{port} already has a listener, so serve.run was not started — stop it (an orphaned dev server from an earlier run?) and re-enter:\n{listeners(port)}"
            log.write_text(message)
            return {"exitCode": 2, "tail": message}
    with log.open("w") as sink:
        sink.write(f"$ {serve['run']}\n")
        sink.flush()
        server = subprocess.Popen(["bash", "-c", serve["run"]], cwd=root, stdout=sink, stderr=subprocess.STDOUT, start_new_session=True)
        relays: dict[str, WireEvidence] = {}
        env = {**os.environ}
        for name, target in targets:
            relay = WireEvidence(target["url"], float(target.get("upstreamTimeout", UPSTREAM_TIMEOUT)))
            threading.Thread(target=relay.serve_forever, daemon=True).start()
            relays[name] = relay
            if name:
                env[f"GAUNTLET_URL_{env_suffix(name)}"] = relay.url
        if len(relays) == 1:
            env["GAUNTLET_URL"] = next(iter(relays.values())).url
        try:
            probes = [probe for _, target in targets for probe in ready_probes(target)]
            unready = wait_for_ready(serve, probes)
            if unready:
                startup = serve.get("startup", serve.get("timeout", SERVE_TIMEOUT))
                return {"exitCode": 2, "tail": f"environment: not ready within the {startup}s startup window — " + "; ".join(unready) + ":\n" + log.read_text()[-TAIL_CHARS:]}
            warmup_failure = warm_up(serve, sink)
            if warmup_failure:
                return {"exitCode": 2, "tail": f"environment: {warmup_failure}:\n" + log.read_text()[-TAIL_CHARS:]}
            urls = " ".join(f"{key}={value}" for key, value in env.items() if key.startswith("GAUNTLET_URL"))
            sink.write(f"$ {urls} bash {script.relative_to(root)}\n")
            sink.flush()
            run = subprocess.run(["bash", str(script)], cwd=root, capture_output=True, text=True, env=env)
            sink.write(run.stdout + run.stderr)
        finally:
            for relay in relays.values():
                relay.shutdown()
                relay.server_close()
            os.killpg(server.pid, signal.SIGTERM)
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(server.pid, signal.SIGKILL)
    verdicts = QA_LINE.findall(run.stdout)
    passed = [criterion for status, criterion in verdicts if status == "PASS"]
    failed = [criterion for status, criterion in verdicts if status == "FAIL"]
    output = (run.stdout + run.stderr)[-TAIL_CHARS:]
    result = {"passed": passed, "failed": failed, "requests": sum(relay.requests for relay in relays.values())}
    if full_output:
        result["output"] = run.stdout + run.stderr
    if not verdicts:
        return {**result, "exitCode": 1, "tail": "QA script printed no PASS/FAIL lines:\n" + output}
    starved = [name for name, relay in relays.items() if relay.requests == 0]
    if starved:
        return {**result, "exitCode": 1, "tail": starvation_message(starved) + output}
    return {**result, "exitCode": 1 if failed else 0, "tail": output}


def qa_dry_guard(root: Path, config: dict, nonce: str, runs: Path) -> dict:
    taken = len(list(runs.glob(f"{nonce}-dry-*.log")))
    if taken >= DRY_RUN_CAP:
        return {"exitCode": 2, "dry": True, "tail": f"dry-run cap of {DRY_RUN_CAP} reached for {nonce} — return with the script as it stands"}
    return {**qa_guard(root, config, nonce, runs / f"{nonce}-dry-{taken + 1}.log", full_output=True), "dry": True}


def resolve(guard: str, root: Path, config: dict) -> tuple[str | None, str | None]:
    if guard in ("setup", "teardown", "build"):
        return config.get(guard), None
    if guard == "install":
        return install_command(root, config), None
    if guard in ("coverage", "crap") and not config.get("coverage"):
        return None, None
    if guard == "coverage":
        return coverage_command(config), None
    if guard == "crap":
        return crap_command(config), None
    if guard == "clean-tree":
        dirty = changed_files(root)
        return None, "\n".join(dirty) if dirty else ""
    return None, None


STAGES = ("specify", "coder", "cleaner", "qa", "ship")
PREFLIGHT_GUARDS = ("clean-tree", "install", "setup", "build", "coverage")


def write_ticket(root: Path, ref: str) -> dict:
    ticket = resolve_ticket(ref)
    if ticket["exitCode"] != 0:
        return ticket
    if not criteria_from(ticket["body"]):
        return {"exitCode": 1, "tail": f"ticket {ref} has no '- [ ] Given …, when …, then …' acceptance criteria — write them with /to-tickets first"}
    issue = ref if re.fullmatch(r"\d+", ref) else Path(ref).stem
    (root / ".gauntlet" / "ticket.json").write_text(json.dumps({"issue": issue, "title": ticket["title"], "body": ticket["body"]}))
    return {"exitCode": 0}


GATE_CHAINS = {
    "specify": (("clean-tree", None), ("spec", "red")),
    "code": (("clean-tree", None), ("spec", "green"), ("build", None), ("coverage", None), ("reachability", None), ("crap", None), ("depth", None)),
}
GATE_STOPS_AT = ("clean-tree", "build", "coverage")
GATE_FINDING_FIELDS = ("exitCode", "tail", "log", "offenders", "problems", "criteria")


def gate_guard(chain: str, nonce: str, root: Path, config: dict) -> dict:
    if chain not in GATE_CHAINS:
        return {"exitCode": 2, "failed": None, "head": git(root, "rev-parse", "HEAD"), "findings": {}, "tail": f"gate chain must be one of {', '.join(GATE_CHAINS)}"}
    findings: dict = {}
    failed = None
    exit_code = 0
    head = ""
    for guard, argument in GATE_CHAINS[chain]:
        result = guard_result(guard, f"{nonce}-{guard}", argument, root, config)
        if guard == "coverage" and result["exitCode"] == 1:
            result = guard_result(guard, f"{nonce}-{guard}-retry", argument, root, config)
        if guard == "clean-tree":
            head = result["head"]
            result["exitCode"] = min(result["exitCode"], 1)
        findings[guard] = {field: result[field] for field in GATE_FINDING_FIELDS if field in result}
        if result["exitCode"] == 0:
            continue
        if failed is None:
            failed = guard
            exit_code = result["exitCode"]
        if exit_code == 2 or guard in GATE_STOPS_AT:
            break
    red = [guard for guard, finding in findings.items() if finding["exitCode"] != 0]
    tail = "\n\n".join(f"[{guard}]\n{findings[guard].get('tail', '')}" for guard in red)
    return {"exitCode": exit_code, "failed": failed, "head": head, "findings": findings, "tail": tail}


def guard_result(guard: str, nonce: str, argument: str | None, root: Path, config: dict) -> dict:
    runs = root / ".gauntlet" / "runs"
    runs.mkdir(parents=True, exist_ok=True)
    result: dict = {"nonce": nonce, "guard": guard}

    if guard == "gate":
        result.update(gate_guard(argument or "", nonce, root, config))
        return result

    if guard == "ticket":
        result.update(write_ticket(root, argument or ""))
        return result

    if guard == "spec":
        result.update(spec_guard(argument or "", root, config, runs / f"{nonce}.log"))
        return result

    if guard == "reachability":
        result.update(reachability_guard(root, config))
        return result

    if guard == "depth":
        result.update(depth_guard(root, config))
        return result

    if guard == "verdict":
        sha = git(root, "rev-parse", "HEAD")
        (root / ".gauntlet" / f"verdict-{sha}.json").write_text(json.dumps({"sha": sha, "clean": True, "source": "gauntlet"}))
        result.update(exitCode=0, tail=f"verdict written for {sha}")
        return result

    if guard == "qa":
        result.update(qa_guard(root, config, nonce, runs / f"{nonce}.log"))
        return result

    if guard == "qa-dry":
        result.update(qa_dry_guard(root, config, nonce, runs))
        return result

    command, inline = resolve(guard, root, config)
    if command is None and inline is None:
        result.update(exitCode=127 if guard not in ("install", "setup", "teardown", "coverage", "crap") else 0, tail=f"no command for guard '{guard}' in config — skipped")
        return result

    if inline is not None:
        result.update(exitCode=0 if inline == "" else 2, tail=inline and f"working tree dirty — stash or commit first:\n{inline}", head=git(root, "rev-parse", "HEAD"))
        return result

    log = runs / f"{nonce}.log"
    with log.open("w") as sink:
        sink.write(f"$ {command}\n")
        sink.flush()
        process = subprocess.run(["bash", "-c", command], cwd=root, stdout=sink, stderr=subprocess.STDOUT)
    output = log.read_text()
    result.update(exitCode=process.returncode, tail=output[-TAIL_CHARS:], log=str(log.relative_to(root)))

    if guard == "crap":
        verdict_line = next((line for line in reversed(output.splitlines()) if line.startswith("{")), None)
        if verdict_line:
            result["offenders"] = json.loads(verdict_line).get("offenders", [])
    return result


def slug(ref: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", Path(ref).stem if not re.fullmatch(r"\d+", ref) else ref).strip("-")


def preflight(ref: str, from_stage: str, root: Path, config: dict) -> dict:
    if from_stage not in STAGES:
        return {"ok": False, "failed": "from", "tail": f"--from must be one of {', '.join(STAGES)}"}
    branch = git(root, "branch", "--show-current")
    if branch in ("main", "master"):
        subprocess.run(["git", "checkout", "-q", "-b", f"gauntlet/{slug(ref)}"], cwd=root)
        branch = git(root, "branch", "--show-current")
    (root / ".gauntlet").mkdir(exist_ok=True)
    secret = secrets.token_hex(8)
    (root / ".gauntlet" / "run-secret").write_text(secret + "\n")
    outcome = {"repoRoot": str(root), "branch": branch, "secret": secret, "ticket": ref, "from": from_stage}
    ticket = write_ticket(root, ref)
    if ticket["exitCode"] != 0:
        return {**outcome, "ok": False, "failed": "ticket", "tail": ticket["tail"]}
    guards = list(PREFLIGHT_GUARDS) + (["spec"] if STAGES.index(from_stage) >= STAGES.index("cleaner") else [])
    for guard in guards:
        result = guard_result(guard, f"preflight-{guard}", "green" if guard == "spec" else None, root, config)
        if result["exitCode"] != 0:
            return {**outcome, "ok": False, "failed": guard, "exitCode": result["exitCode"], "tail": result.get("tail", "")}
    return {**outcome, "ok": True, "headSha": git(root, "rev-parse", "HEAD")}


def main(argv: list[str]) -> int:
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel") or Path.cwd())
    config_file = root / ".gauntlet" / "config.json"
    secret_file = root / ".gauntlet" / "run-secret"
    secret = secret_file.read_text().strip() if secret_file.exists() else ""

    if argv and argv[0] == "preflight":
        ref = argv[1] if len(argv) > 1 else ""
        from_stage = argv[argv.index("--from") + 1] if "--from" in argv and argv.index("--from") + 1 < len(argv) else "specify"
        if not config_file.exists():
            print(json.dumps({"ok": False, "failed": "config", "tail": "no .gauntlet/config.json in this repo — see the gauntlet README"}))
            return 0
        if not ref:
            print(json.dumps({"ok": False, "failed": "ticket", "tail": "usage: run.py preflight <issue-number|path> [--from <stage>]"}))
            return 0
        print(json.dumps(preflight(ref, from_stage, root, json.loads(config_file.read_text()))))
        return 0

    guard, nonce = argv[0], argv[1]
    argument = argv[2] if len(argv) > 2 else None
    if not config_file.exists():
        return emit({"nonce": nonce, "guard": guard, "exitCode": 2, "tail": "no .gauntlet/config.json in this repo"}, secret)
    return emit(guard_result(guard, nonce, argument, root, json.loads(config_file.read_text())), secret)


def receipt(secret: str, nonce: str, exit_code: int, head: str | None = None, failed: str | None = None, gate: bool = False) -> str:
    signed = f"{secret}:{nonce}:{exit_code}"
    if gate:
        signed += f":{failed or '-'}"
    if head:
        signed += f":{head}"
    return fnv1a32(signed)


def emit(result: dict, secret: str) -> int:
    if not result.pop("dry", False):
        result["receipt"] = receipt(secret, result["nonce"], result["exitCode"], result.get("head"), result.get("failed"), result["guard"] == "gate")
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
