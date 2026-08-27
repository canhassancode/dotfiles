#!/usr/bin/env python3
"""Gauntlet guard runner — the deterministic half of every transition gate.

    run.py <guard> <nonce> [<argument>]

Looks the guard up by name in <repo>/.gauntlet/config.json, runs it with all output
captured to <repo>/.gauntlet/runs/<nonce>.log, and prints exactly one JSON line:

    {"nonce", "guard", "exitCode", "receipt", "tail", "offenders"?}

`ticket <nonce> <issue>` fetches the issue verbatim and persists it to .gauntlet/ticket.json
as {"issue", "title", "body"} — the gauntlet's one input contract, read from disk by every
stage and later guard. The ticket never crosses the conduit: the JSON line carries only the
receipt-verified fields, so nothing large has to survive a model relay byte-for-byte.

`spec <nonce> red|green` reads the ticket's `- [ ] Given … when … then …` criteria, runs
config.acceptance.run, and requires exactly one test named after each criterion (and no
stray test in the same files): `red` = every criterion test fails on the untouched tree,
`green` = every one passes. Mocking a module under sourcePaths in an acceptance file is
exit 1. Adds {"criteria", "tests", "problems"}.

`qa <nonce>` starts config.serve.run, waits for config.serve.ready (default serve.url) to answer below 500, runs the QA
stage's .gauntlet/qa/<nonce>.sh with GAUNTLET_URL set, and reads its `PASS <criterion>` /
`FAIL <criterion>` lines: any FAIL (or none of either) is exit 1, a server that never
answers is exit 2, no serve in config is exit 0 with "skipped". The server is always
stopped. Adds {"passed", "failed"} or {"skipped"}.

`verdict <nonce>` writes .gauntlet/verdict-<HEAD>.json = {"sha", "clean": true, "source":
"gauntlet"} — the artefact the pre-PR hook requires. The workflow mints it only after
every gate is green; it is the machine's signature on HEAD, replacing the review stage's.

The workflow verifies `receipt` (FNV-1a over the per-run secret, nonce and exit code)
so a relayed result that never came from this script is rejected as a conduit error.
Exit codes: 0 pass, 1 guard failed (code), 2 operational (infra / harness / protected
file edited), 127 unknown guard. The process itself always exits 0 — the verdict is the
JSON, never the runner's own status.
"""
import json
import os
import re
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
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


QA_LINE = re.compile(r"^(PASS|FAIL)\s+(.+?)\s*$", re.MULTILINE)
SERVE_TIMEOUT = 60


def wait_for(url: str, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            urllib.request.urlopen(url, timeout=1)
            return True
        except urllib.error.HTTPError as response:
            if response.code < 500:
                return True
            time.sleep(0.2)
        except (urllib.error.URLError, OSError):
            time.sleep(0.2)
    return False


def qa_guard(root: Path, config: dict, nonce: str, log: Path) -> dict:
    serve = config.get("serve")
    if not serve:
        return {"exitCode": 0, "skipped": True, "tail": "no serve in config — QA skipped"}
    script = root / ".gauntlet" / "qa" / f"{nonce}.sh"
    if not script.exists():
        return {"exitCode": 2, "tail": f"no QA script at {script.relative_to(root)}"}
    with log.open("w") as sink:
        sink.write(f"$ {serve['run']}\n")
        sink.flush()
        server = subprocess.Popen(["bash", "-c", serve["run"]], cwd=root, stdout=sink, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            ready_url = serve.get("ready", serve["url"])
            if not wait_for(ready_url, float(serve.get("timeout", SERVE_TIMEOUT))):
                return {"exitCode": 2, "tail": f"{ready_url} did not answer below 500 within {serve.get('timeout', SERVE_TIMEOUT)}s:\n" + log.read_text()[-TAIL_CHARS:]}
            sink.write(f"$ bash {script.relative_to(root)}\n")
            sink.flush()
            run = subprocess.run(["bash", str(script)], cwd=root, capture_output=True, text=True, env={**os.environ, "GAUNTLET_URL": serve["url"]})
            sink.write(run.stdout + run.stderr)
        finally:
            os.killpg(server.pid, signal.SIGTERM)
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(server.pid, signal.SIGKILL)
    verdicts = QA_LINE.findall(run.stdout)
    passed = [criterion for status, criterion in verdicts if status == "PASS"]
    failed = [criterion for status, criterion in verdicts if status == "FAIL"]
    if not verdicts:
        return {"exitCode": 1, "passed": [], "failed": [], "tail": "QA script printed no PASS/FAIL lines:\n" + (run.stdout + run.stderr)[-TAIL_CHARS:]}
    return {"exitCode": 1 if failed else 0, "passed": passed, "failed": failed, "tail": (run.stdout + run.stderr)[-TAIL_CHARS:]}


def resolve(guard: str, root: Path, config: dict) -> tuple[str | None, str | None]:
    if guard in ("setup", "teardown", "build"):
        return config.get(guard), None
    if guard == "install":
        return install_command(root, config), None
    if guard == "coverage":
        return coverage_command(config), None
    if guard == "crap":
        return crap_command(config), None
    if guard == "clean-tree":
        dirty = changed_files(root)
        return None, "\n".join(dirty) if dirty else ""
    return None, None


def main(argv: list[str]) -> int:
    guard, nonce = argv[0], argv[1]
    argument = argv[2] if len(argv) > 2 else None
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel") or Path.cwd())
    runs = root / ".gauntlet" / "runs"
    runs.mkdir(parents=True, exist_ok=True)
    secret_file = root / ".gauntlet" / "run-secret"
    secret = secret_file.read_text().strip() if secret_file.exists() else ""
    config_file = root / ".gauntlet" / "config.json"
    result: dict = {"nonce": nonce, "guard": guard}

    if not config_file.exists():
        result.update(exitCode=2, tail="no .gauntlet/config.json in this repo")
        return emit(result, secret)
    config = json.loads(config_file.read_text())

    if guard == "ticket":
        ticket = fetch_ticket(argument or "")
        if ticket["exitCode"] == 0:
            (root / ".gauntlet" / "ticket.json").write_text(json.dumps({"issue": argument, "title": ticket["title"], "body": ticket["body"]}))
        result.update(exitCode=ticket["exitCode"], **({"tail": ticket["tail"]} if "tail" in ticket else {}))
        return emit(result, secret)

    if guard == "spec":
        result.update(spec_guard(argument or "", root, config, runs / f"{nonce}.log"))
        return emit(result, secret)

    if guard == "verdict":
        sha = git(root, "rev-parse", "HEAD")
        (root / ".gauntlet" / f"verdict-{sha}.json").write_text(json.dumps({"sha": sha, "clean": True, "source": "gauntlet"}))
        result.update(exitCode=0, tail=f"verdict written for {sha}")
        return emit(result, secret)

    if guard == "qa":
        result.update(qa_guard(root, config, nonce, runs / f"{nonce}.log"))
        return emit(result, secret)

    command, inline = resolve(guard, root, config)
    if command is None and inline is None:
        result.update(exitCode=127 if guard not in ("install", "setup", "teardown") else 0, tail=f"no command for guard '{guard}'")
        return emit(result, secret)

    if inline is not None:
        result.update(exitCode=0 if inline == "" else 2, tail=inline and f"working tree dirty — stash or commit first:\n{inline}")
        return emit(result, secret)

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
    return emit(result, secret)


def emit(result: dict, secret: str) -> int:
    result["receipt"] = fnv1a32(f"{secret}:{result['nonce']}:{result['exitCode']}")
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
