#!/usr/bin/env python3
"""Run: python3 run.test.py   Exit 0 when every case passes. No network: `gh` is faked on PATH."""

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("run", os.path.join(_here, "run.py"))
run = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = run
_spec.loader.exec_module(run)

SECRET = "s3cret"


class GauntletRepo:
    def __init__(self, config: dict | None = None):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        subprocess.run(["git", "init", "-q", self.root], check=True)
        os.makedirs(os.path.join(self.root, ".gauntlet"))
        with open(os.path.join(self.root, ".gauntlet", "config.json"), "w") as f:
            json.dump(config if config is not None else {"build": "true"}, f)
        with open(os.path.join(self.root, ".gauntlet", "run-secret"), "w") as f:
            f.write(SECRET)
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.bin)
        self.previous_cwd = os.getcwd()
        self.previous_path = os.environ["PATH"]

    def fake(self, name: str, script: str) -> None:
        path = os.path.join(self.bin, name)
        with open(path, "w") as f:
            f.write("#!/usr/bin/env bash\n" + script)
        os.chmod(path, 0o755)

    def fake_gh_issue(self, title: str, body: str) -> None:
        payload = os.path.join(self.root, "issue.json")
        with open(payload, "w") as f:
            json.dump({"title": title, "body": body}, f)
        self.fake("gh", f'cat "{payload}"')

    def __enter__(self):
        os.chdir(self.root)
        os.environ["PATH"] = self.bin + os.pathsep + self.previous_path
        return self

    def __exit__(self, *exc):
        os.chdir(self.previous_cwd)
        os.environ["PATH"] = self.previous_path
        self.tmp.cleanup()


def invoke(*argv: str) -> dict:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        run.main(list(argv))
    return json.loads(out.getvalue().strip().splitlines()[-1])


def receipt_for(nonce: str, exit_code: int) -> str:
    return run.fnv1a32(f"{SECRET}:{nonce}:{exit_code}")


class TicketGuardTests(unittest.TestCase):
    def test_reachable_issue_emits_only_the_receipt_verified_fields(self):
        with GauntletRepo() as repo:
            repo.fake_gh_issue("Fix login", "## Acceptance criteria\n- [ ] Given a — when b, then c")
            result = invoke("ticket", "n1", "63")
        self.assertEqual(result, {"nonce": "n1", "guard": "ticket", "exitCode": 0, "receipt": receipt_for("n1", 0)})

    def test_verified_ticket_is_persisted_for_later_guards(self):
        with GauntletRepo() as repo:
            repo.fake_gh_issue("Fix login", "- [ ] Given a, when b, then c")
            invoke("ticket", "n1", "63")
            with open(os.path.join(repo.root, ".gauntlet", "ticket.json")) as f:
                persisted = json.load(f)
        self.assertEqual(persisted, {"issue": "63", "title": "Fix login", "body": "- [ ] Given a, when b, then c"})

    def test_gh_failure_is_operational(self):
        with GauntletRepo() as repo:
            repo.fake("gh", 'echo "GraphQL: Could not resolve" >&2; exit 1')
            result = invoke("ticket", "n2", "63")
        self.assertEqual(result["exitCode"], 2)
        self.assertNotIn("body", result)
        self.assertIn("Could not resolve", result["tail"])
        self.assertEqual(result["receipt"], receipt_for("n2", 2))

    def test_empty_body_is_operational(self):
        with GauntletRepo() as repo:
            repo.fake_gh_issue("Fix login", "  \n")
            result = invoke("ticket", "n3", "63")
        self.assertEqual(result["exitCode"], 2)
        self.assertNotIn("body", result)

    def test_missing_issue_argument_is_operational(self):
        with GauntletRepo() as repo:
            repo.fake("gh", 'exit 1')
            result = invoke("ticket", "n4")
        self.assertEqual(result["exitCode"], 2)


CRITERIA = [
    "Given an expired access token, when the client calls any route, then the response is 200",
    "Given ten parallel 401s, when they resolve, then exactly one refresh call was made",
    "Given an expired refresh token, when a request 401s, then the user is redirected to /login",
]


def jest_results(statuses: dict[str, str]) -> dict:
    return {"testResults": [{"assertionResults": [{"fullName": f"Session refresh {name}", "status": status} for name, status in statuses.items()]}]}


class SpecRepo(GauntletRepo):
    def __init__(self, criteria: list[str], results: dict, spec_source: str = "describe('Session refresh', () => {});\n", ticket: bool = True):
        super().__init__({"sourcePaths": ["src"], "acceptance": {"run": "cp results.json acceptance.json", "output": "acceptance.json", "pattern": "tests/*.acceptance.spec.ts"}})
        os.makedirs(os.path.join(self.root, "tests"))
        with open(os.path.join(self.root, "tests", "session.acceptance.spec.ts"), "w") as f:
            f.write(spec_source)
        with open(os.path.join(self.root, "results.json"), "w") as f:
            json.dump(results, f)
        if ticket:
            body = "## Acceptance criteria\n\n" + "\n".join(f"- [ ] {c}" for c in criteria) + "\n\n## Blocked by\n- None"
            with open(os.path.join(self.root, ".gauntlet", "ticket.json"), "w") as f:
                json.dump({"issue": "63", "title": "t", "body": body}, f)


class SpecGuardTests(unittest.TestCase):
    def test_red_mode_passes_when_every_criterion_test_fails(self):
        with SpecRepo(CRITERIA, jest_results({c: "failed" for c in CRITERIA})):
            result = invoke("spec", "n1", "red")
        self.assertEqual(result["exitCode"], 0, result)
        self.assertEqual(result["criteria"], CRITERIA)

    def test_criterion_without_test_names_the_mismatch(self):
        with SpecRepo(CRITERIA, jest_results({c: "failed" for c in CRITERIA[:2]})):
            result = invoke("spec", "n1", "red")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["problems"], [f"0 tests named after criterion: {CRITERIA[2]}"])

    def test_stray_test_in_acceptance_file_names_the_mismatch(self):
        statuses = {c: "failed" for c in CRITERIA}
        statuses["Given something nobody asked for, when run, then it passes"] = "failed"
        with SpecRepo(CRITERIA, jest_results(statuses)):
            result = invoke("spec", "n1", "red")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["problems"], ["test matches no criterion: Session refresh Given something nobody asked for, when run, then it passes"])

    def test_red_mode_fails_when_baseline_already_satisfies_a_criterion(self):
        statuses = {c: "failed" for c in CRITERIA}
        statuses[CRITERIA[1]] = "passed"
        with SpecRepo(CRITERIA, jest_results(statuses)):
            result = invoke("spec", "n1", "red")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["problems"], [f"expected failed in red mode but was passed: {CRITERIA[1]}"])

    def test_green_mode_passes_when_all_pass_and_names_the_failure_otherwise(self):
        with SpecRepo(CRITERIA, jest_results({c: "passed" for c in CRITERIA})):
            self.assertEqual(invoke("spec", "n1", "green")["exitCode"], 0)
        statuses = {c: "passed" for c in CRITERIA}
        statuses[CRITERIA[0]] = "failed"
        with SpecRepo(CRITERIA, jest_results(statuses)):
            result = invoke("spec", "n2", "green")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["problems"], [f"expected passed in green mode but was failed: {CRITERIA[0]}"])

    def test_mocking_the_system_under_test_fails_before_running(self):
        source = "jest.mock('../src/auth/refreshCoordinator');\njest.mock('node-fetch');\n"
        with SpecRepo(CRITERIA, jest_results({c: "failed" for c in CRITERIA}), spec_source=source):
            result = invoke("spec", "n1", "red")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["problems"], ["tests/session.acceptance.spec.ts mocks ../src/auth/refreshCoordinator"])

    def test_suite_that_cannot_start_is_operational(self):
        with SpecRepo(CRITERIA, {}) as repo:
            with open(os.path.join(repo.root, ".gauntlet", "config.json"), "w") as f:
                json.dump({"acceptance": {"run": "exit 1", "output": "acceptance.json", "pattern": "tests/*.spec.ts"}}, f)
            result = invoke("spec", "n1", "red")
        self.assertEqual(result["exitCode"], 2)

    def test_missing_ticket_is_operational(self):
        with SpecRepo(CRITERIA, {}, ticket=False):
            self.assertEqual(invoke("spec", "n1", "red")["exitCode"], 2)

    def test_ticket_without_scenarios_is_a_code_failure(self):
        with SpecRepo([], {}) as repo:
            body = "## Acceptance criteria\n- [ ] Coordinator covered by integration tests\n"
            with open(os.path.join(repo.root, ".gauntlet", "ticket.json"), "w") as f:
                json.dump({"issue": "63", "title": "t", "body": body}, f)
            result = invoke("spec", "n1", "red")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["criteria"], [])

    def test_playwright_report_is_understood(self):
        report = {"suites": [{"title": "session.acceptance.spec.ts", "file": "tests/session.acceptance.spec.ts", "suites": [{"title": "Session refresh", "specs": [
            {"title": c, "tests": [{"results": [{"status": "failed"}]}]} for c in CRITERIA]}]}]}
        with SpecRepo(CRITERIA, report):
            result = invoke("spec", "n1", "red")
        self.assertEqual(result["exitCode"], 0, result)
        self.assertEqual(result["tests"][CRITERIA[0]], f"session.acceptance.spec.ts Session refresh {CRITERIA[0]}")


def free_port() -> int:
    import socket
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def port_is_open(port: int) -> bool:
    import socket
    with socket.socket() as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(("127.0.0.1", port)) == 0


class QaRepo(GauntletRepo):
    def __init__(self, script: str | None, serve: dict | None):
        config = {"build": "true"}
        if serve is not None:
            config["serve"] = serve
        super().__init__(config)
        if script is not None:
            os.makedirs(os.path.join(self.root, ".gauntlet", "qa"))
            with open(os.path.join(self.root, ".gauntlet", "qa", "n1.sh"), "w") as f:
                f.write(script)


def http_serve(port: int) -> dict:
    return {"run": f"python3 -m http.server {port} --bind 127.0.0.1", "url": f"http://127.0.0.1:{port}/", "timeout": 10}


class QaGuardTests(unittest.TestCase):
    def test_script_runs_against_the_served_system_and_serve_is_stopped(self):
        port = free_port()
        script = 'curl -sf "$GAUNTLET_URL" >/dev/null && echo "PASS Given the server, when fetched, then it answers" || echo "FAIL Given the server, when fetched, then it answers"\n'
        with QaRepo(script, http_serve(port)):
            result = invoke("qa", "n1")
            still_open = port_is_open(port)
        self.assertEqual(result["exitCode"], 0, result)
        self.assertEqual(result["passed"], ["Given the server, when fetched, then it answers"])
        self.assertFalse(still_open)

    def test_failing_criterion_is_a_code_failure_listing_it(self):
        port = free_port()
        script = 'echo "PASS Given a, when b, then c"\necho "FAIL Given d, when e, then f"\nexit 1\n'
        with QaRepo(script, http_serve(port)):
            result = invoke("qa", "n1")
            still_open = port_is_open(port)
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["failed"], ["Given d, when e, then f"])
        self.assertFalse(still_open)

    def test_script_reporting_nothing_is_a_code_failure(self):
        port = free_port()
        with QaRepo('echo hello\n', http_serve(port)):
            result = invoke("qa", "n1")
        self.assertEqual(result["exitCode"], 1)
        self.assertIn("no PASS/FAIL lines", result["tail"])

    def test_server_that_never_answers_is_operational(self):
        port = free_port()
        with QaRepo('echo "PASS never reached"\n', {"run": "sleep 30", "url": f"http://127.0.0.1:{port}/", "timeout": 1}):
            result = invoke("qa", "n1")
        self.assertEqual(result["exitCode"], 2)
        self.assertNotIn("passed", result)

    def test_ready_url_answering_5xx_is_not_ready(self):
        port = free_port()
        serve = {"run": f"python3 -c \"import http.server,sys\nclass H(http.server.BaseHTTPRequestHandler):\n  def do_GET(self): self.send_response(503); self.end_headers()\nhttp.server.HTTPServer(('127.0.0.1', {port}), H).serve_forever()\"", "url": f"http://127.0.0.1:{port}/", "timeout": 2}
        with QaRepo('echo "PASS never reached"\n', serve):
            result = invoke("qa", "n1")
        self.assertEqual(result["exitCode"], 2)

    def test_ready_url_is_polled_instead_of_url(self):
        port = free_port()
        serve = {**http_serve(port), "url": "http://127.0.0.1:1/", "ready": f"http://127.0.0.1:{port}/"}
        script = 'curl -s "$GAUNTLET_URL" >/dev/null; echo "PASS Given the server, when fetched, then it answers"\n'
        with QaRepo(script, serve):
            result = invoke("qa", "n1")
        self.assertEqual(result["exitCode"], 0)
        self.assertEqual(result["requests"], 1)

    def test_script_that_never_touches_the_served_system_is_red_with_zero_requests(self):
        port = free_port()
        script = 'echo "PASS Given a, when b, then c"\necho "PASS Given d, when e, then f"\n'
        with QaRepo(script, http_serve(port)):
            result = invoke("qa", "n1")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["requests"], 0)
        self.assertIn("0 requests to the served system", result["tail"])

    def test_relay_forwards_status_headers_body_and_does_not_follow_redirects(self):
        port = free_port()
        serve = {"run": f"python3 -c \"import http.server\nclass H(http.server.BaseHTTPRequestHandler):\n  def do_GET(self):\n    if self.path == '/go': self.send_response(302); self.send_header('Location', '/login'); self.end_headers(); return\n    body = ('echo ' + self.path + ' ' + self.headers.get('Cookie', '-')).encode(); self.send_response(200); self.send_header('X-Served', 'yes'); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)\n  def do_POST(self):\n    n = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(n); self.send_response(201); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)\n  def log_message(self, *a): pass\nhttp.server.HTTPServer(('127.0.0.1', {port}), H).serve_forever()\"", "url": f"http://127.0.0.1:{port}/", "timeout": 10}
        script = """
out=$(curl -s -H 'Cookie: a=1' "$GAUNTLET_URL/api/x"); [ "$out" = "echo /api/x a=1" ] && echo "PASS Given g, when a get is relayed, then path and cookie reach upstream" || echo "FAIL Given g, when a get is relayed, then path and cookie reach upstream ($out)"
hdr=$(curl -s -D - -o /dev/null "$GAUNTLET_URL/api/x" | grep -i x-served | tr -d '\\r'); [ "$hdr" = "X-Served: yes" ] && echo "PASS Given h, when headers come back, then they are relayed" || echo "FAIL Given h, when headers come back, then they are relayed ($hdr)"
code=$(curl -s -o /dev/null -w '%{http_code}' "$GAUNTLET_URL/go"); [ "$code" = "302" ] && echo "PASS Given r, when upstream redirects, then the script sees the 302" || echo "FAIL Given r, when upstream redirects, then the script sees the 302 ($code)"
body=$(curl -s -X POST -d 'hello' -w ' %{http_code}' "$GAUNTLET_URL/post"); [ "$body" = "hello 201" ] && echo "PASS Given p, when a post is relayed, then body and status come back" || echo "FAIL Given p, when a post is relayed, then body and status come back ($body)"
"""
        with QaRepo(script, serve):
            result = invoke("qa", "n1")
        self.assertEqual(result["failed"], [], result)
        self.assertEqual(result["exitCode"], 0)
        self.assertEqual(result["requests"], 4)

    def test_missing_script_is_operational(self):
        port = free_port()
        with QaRepo(None, http_serve(port)):
            result = invoke("qa", "n1")
            still_open = port_is_open(port)
        self.assertEqual(result["exitCode"], 2)
        self.assertFalse(still_open)

    def test_no_serve_in_config_skips(self):
        with QaRepo('echo "PASS x"\n', None):
            result = invoke("qa", "n1")
        self.assertEqual(result["exitCode"], 0)
        self.assertTrue(result["skipped"])


def commit(root: str, message: str) -> str:
    subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false", "add", "-A"], cwd=root, check=True)
    subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", message], cwd=root, check=True)
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True).stdout.strip()


class BranchRepo(GauntletRepo):
    """A repo with `main` holding the baseline files and a feature branch holding the added ones."""

    def __init__(self, baseline: dict[str, str], added: dict[str, str], config: dict | None = None):
        super().__init__({"build": "true", "sourcePaths": ["src"], **(config or {})})
        with open(os.path.join(self.root, ".git", "info", "exclude"), "a") as f:
            f.write("bin/\nissue.json\n*.md\n.gauntlet/\nacceptance.json\n")
        subprocess.run(["git", "checkout", "-q", "-b", "main"], cwd=self.root)
        self.write(baseline)
        commit(self.root, "baseline")
        subprocess.run(["git", "checkout", "-q", "-b", "feature"], cwd=self.root)
        self.write(added)
        self.head = commit(self.root, "feature")

    def write(self, files: dict[str, str]) -> None:
        for path, text in files.items():
            full = os.path.join(self.root, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as f:
                f.write(text)


ROUTE = "export const GET = async () => new Response('ok');\n"
DEEP = "export async function refresh(token: string) {\n" + "\n".join(f"  const step{i} = {i};" for i in range(20)) + "\n  return token;\n}\n"


class ReachabilityGuardTests(unittest.TestCase):
    def test_new_file_imported_by_nothing_is_red_naming_it(self):
        with BranchRepo({"src/pages/api/posts.ts": ROUTE}, {"src/lib/sessionClient.ts": DEEP, "src/lib/sessionClient.acceptance.spec.ts": "import { refresh } from './sessionClient';\n"}):
            result = invoke("reachability", "n1")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["problems"], ["src/lib/sessionClient.ts is reached by nothing: not an edge and imported from no edge or pre-existing file"])

    def test_new_file_imported_from_a_pre_existing_file_is_green(self):
        with BranchRepo({"src/pages/api/posts.ts": ROUTE}, {"src/pages/api/posts.ts": "import { refresh } from '../../lib/sessionClient';\n" + ROUTE, "src/lib/sessionClient.ts": DEEP}):
            result = invoke("reachability", "n1")
        self.assertEqual(result["exitCode"], 0, result)

    def test_new_edge_is_green_and_its_helper_reached_through_it_is_green(self):
        config = {"edges": ["src/pages/**"]}
        with BranchRepo({"src/index.ts": "export {};\n"}, {"src/pages/api/foo/index.ts": "import { calc } from '@/lib/calc';\n" + ROUTE, "src/lib/calc.ts": DEEP}, config):
            result = invoke("reachability", "n1")
        self.assertEqual(result["exitCode"], 0, result)

    def test_directory_index_is_reached_by_a_directory_import(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {"src/app.ts": "import { refresh } from './auth';\nexport {};\n", "src/auth/index.ts": DEEP}):
            result = invoke("reachability", "n1")
        self.assertEqual(result["exitCode"], 0, result)

    def test_import_from_a_test_file_does_not_count(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {"src/lib/x.ts": DEEP, "tests/x.spec.ts": "import '../src/lib/x';\n", "src/lib/x.test.ts": "import './x';\n"}):
            result = invoke("reachability", "n1")
        self.assertEqual(result["exitCode"], 1)

    def test_no_added_production_files_is_green(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {"src/app.ts": "export const a = 1;\n", "README.md": "x"}):
            result = invoke("reachability", "n1")
        self.assertEqual(result["exitCode"], 0)
        self.assertEqual(result["added"], [])


class DepthGuardTests(unittest.TestCase):
    def test_barrel_and_pass_through_are_red_naming_the_file(self):
        barrel = "export { a } from './a';\nexport { b } from './b';\nexport * from './c';\n"
        wrapper = "import { inner } from './inner';\nexport const one = () => inner(1);\nexport const two = () => inner(2);\nexport const three = () => inner(3);\n"
        with BranchRepo({"src/app.ts": "export {};\n"}, {"src/lib/index.ts": barrel, "src/lib/wrap.ts": wrapper}):
            result = invoke("depth", "n1")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual([o["file"] for o in result["offenders"]], ["src/lib/index.ts", "src/lib/wrap.ts"])
        self.assertEqual(result["offenders"][1], {"file": "src/lib/wrap.ts", "exports": 3, "lines": 3, "depth": 1.0})

    def test_deep_module_and_export_free_file_are_green(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {"src/lib/deep.ts": DEEP, "src/lib/side-effect.ts": "console.log('hi');\n"}):
            result = invoke("depth", "n1")
        self.assertEqual(result["exitCode"], 0, result)

    def test_ceiling_comes_from_config(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {"src/lib/deep.ts": DEEP}, {"depth": {"ceiling": 40}}):
            result = invoke("depth", "n1")
        self.assertEqual(result["exitCode"], 1)
        self.assertEqual(result["offenders"][0]["file"], "src/lib/deep.ts")

    def test_python_counts_public_defs(self):
        with BranchRepo({"src/app.py": "pass\n"}, {"src/lib/util.py": "def a():\n    pass\ndef b():\n    pass\ndef _p():\n    pass\n"}):
            result = invoke("depth", "n1")
        self.assertEqual(result["offenders"][0]["exports"], 2)


class CleanTreeGuardTests(unittest.TestCase):
    def test_clean_tree_reports_head_covered_by_the_receipt(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {}) as repo:
            result = invoke("clean-tree", "n1")
        self.assertEqual(result["exitCode"], 0)
        self.assertEqual(result["head"], repo.head)
        self.assertEqual(result["receipt"], run.fnv1a32(f"{SECRET}:n1:0:{repo.head}"))


class PreflightTests(unittest.TestCase):
    def preflight(self, *argv: str) -> dict:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            run.main(["preflight", *argv])
        return json.loads(out.getvalue().strip().splitlines()[-1])

    def test_issue_number_leaves_main_writes_the_ticket_and_runs_every_guard(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {}) as repo:
            subprocess.run(["git", "checkout", "-q", "main"], cwd=repo.root)
            repo.fake_gh_issue("Fix login", "- [ ] Given a, when b, then c")
            result = self.preflight("63")
            branch = subprocess.run(["git", "branch", "--show-current"], cwd=repo.root, capture_output=True, text=True).stdout.strip()
            with open(os.path.join(repo.root, ".gauntlet", "ticket.json")) as f:
                ticket = json.load(f)
            with open(os.path.join(repo.root, ".gauntlet", "run-secret")) as f:
                secret = f.read().strip()
            logs = sorted(os.listdir(os.path.join(repo.root, ".gauntlet", "runs")))
        self.assertTrue(result["ok"], result)
        self.assertEqual(branch, "gauntlet/63")
        self.assertEqual(result["branch"], "gauntlet/63")
        self.assertEqual(result["secret"], secret)
        self.assertEqual(result["ticket"], "63")
        self.assertEqual(result["from"], "specify")
        self.assertEqual(ticket["issue"], "63")
        self.assertIn("preflight-build.log", logs)
        self.assertNotIn("receipt", result)

    def test_markdown_path_is_a_ticket(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {}) as repo:
            path = os.path.join(repo.root, "Fix Login.md")
            with open(path, "w") as f:
                f.write("# Fix login flow\n\n- [ ] Given a, when b, then c\n")
            result = self.preflight(path)
            with open(os.path.join(repo.root, ".gauntlet", "ticket.json")) as f:
                ticket = json.load(f)
        self.assertTrue(result["ok"], result)
        self.assertEqual(ticket, {"issue": "Fix Login", "title": "Fix login flow", "body": "# Fix login flow\n\n- [ ] Given a, when b, then c\n"})

    def test_ticket_without_criteria_stops_before_any_guard(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {}) as repo:
            repo.fake_gh_issue("Rename", "Just rename the thing")
            result = self.preflight("63")
            logs = os.listdir(os.path.join(repo.root, ".gauntlet", "runs")) if os.path.isdir(os.path.join(repo.root, ".gauntlet", "runs")) else []
        self.assertFalse(result["ok"])
        self.assertEqual(result["failed"], "ticket")
        self.assertIn("no '- [ ] Given", result["tail"])
        self.assertEqual(logs, [])

    def test_unknown_origin_and_bad_from_are_named(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {}) as repo:
            repo.fake_gh_issue("t", "- [ ] Given a, when b, then c")
            unknown = self.preflight("BF-12")
            bad_from = self.preflight("63", "--from", "review")
        self.assertEqual(unknown["failed"], "ticket")
        self.assertIn("unknown ticket origin", unknown["tail"])
        self.assertEqual(bad_from["failed"], "from")

    def test_failing_guard_names_itself_and_stops(self):
        with BranchRepo({"src/app.ts": "export {};\n"}, {}, {"build": "exit 3"}) as repo:
            repo.fake_gh_issue("t", "- [ ] Given a, when b, then c")
            result = self.preflight("63")
        self.assertFalse(result["ok"])
        self.assertEqual(result["failed"], "build")
        self.assertEqual(result["exitCode"], 3)

    def test_re_entering_past_the_coder_requires_acceptance_green(self):
        results = jest_results({"Given a, when b, then c": "failed"})
        config = {"acceptance": {"run": "cp results.json acceptance.json", "output": "acceptance.json", "pattern": "tests/*.acceptance.spec.ts"}}
        with BranchRepo({"src/app.ts": "export {};\n"}, {"results.json": json.dumps(results), "tests/x.acceptance.spec.ts": ""}, config) as repo:
            repo.fake_gh_issue("t", "- [ ] Given a, when b, then c")
            red = self.preflight("63", "--from", "qa")
            from_specify = self.preflight("63", "--from", "specify")
        self.assertEqual(red["failed"], "spec")
        self.assertEqual(red["from"], "qa")
        self.assertTrue(from_specify["ok"], from_specify)

    def test_missing_config_is_named(self):
        with GauntletRepo() as repo:
            os.remove(os.path.join(repo.root, ".gauntlet", "config.json"))
            result = self.preflight("63")
        self.assertFalse(result["ok"])
        self.assertEqual(result["failed"], "config")


class VerdictGuardTests(unittest.TestCase):
    def test_verdict_is_written_for_head_as_a_clean_pass(self):
        with GauntletRepo() as repo:
            subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "init"], cwd=repo.root, check=True)
            sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo.root, capture_output=True, text=True).stdout.strip()
            result = invoke("verdict", "n1")
            with open(os.path.join(repo.root, ".gauntlet", f"verdict-{sha}.json")) as f:
                verdict = json.load(f)
        self.assertEqual(result["exitCode"], 0)
        self.assertEqual(verdict, {"sha": sha, "clean": True, "source": "gauntlet"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
