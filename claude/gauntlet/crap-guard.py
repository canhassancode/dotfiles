#!/usr/bin/env python3
"""Harness-owned CRAP ceiling guard.

CRAP(f) = comp(f)**2 * (1 - cov(f))**3 + comp(f), computed per function.
comp is the cyclomatic complexity from `lizard` (any language); cov is the
fraction of the function's lines exercised by the repo's own coverage run. A
function no coverage evidence touches counts as fully uncovered (0.0) — evidence
over trust: unmeasured is treated as unproven, not assumed safe.

The harness owns the formula, the ceiling, and the complexity tool. The repo
supplies only its coverage JSON (the one execution-bound fact), produced by c8 /
Istanbul (JS/TS) or coverage.py (Python). Pass --coverage once per test suite; a
line counts as covered if any suite exercised it (the guard unions them), so
unit + integration + e2e — even mixed istanbul/coverage-py formats — combine into
one honest coverage picture.

Usage:
    crap-guard.py --coverage <file> [--coverage <file> ...]
                  [--format auto|istanbul|coverage-py]
                  [--ceiling 30] [--changed-only] [PATH ...]

PATH defaults to the current directory and is what lizard analyses. Scope it to
the repo's own source dirs to avoid flagging vendored or generated code that the
coverage run never instrumented.

--changed-only narrows the verdict to the functions the working tree has actually
touched vs HEAD (new files count wholesale, modified files by their changed
hunks), keeping PATH only as a source-dir filter. This matches the gauntlet's
harden mandate — drive every *touched* function under the ceiling — so a repo's
pre-existing complexity debt never makes the guard unwinnable.

Stdout: a JSON verdict {pass, ceiling, offenders:[{file,function,line,ccn,
coverage,crap}]}. Exit 0 when every function is at or below the ceiling, 1 when
any exceeds it (offenders on stdout), 2 on an operational error (lizard missing,
unreadable coverage) reported on stderr.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import subprocess
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Function:
    file: str
    name: str
    ccn: int
    start: int
    end: int


class OperationalError(Exception):
    pass


def run_lizard(paths: list[str]) -> list[Function]:
    try:
        completed = subprocess.run(
            [
                "lizard",
                "-x", "*/node_modules/*",
                "-x", "*/.vite/*",
                "-x", "*.spec.*",
                "-x", "*.test.*",
                "-x", "*/__tests__/*",
                "--csv",
                *paths,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError as missing:
        raise OperationalError(
            "lizard not found on PATH — install it (pip install lizard / pipx install lizard)"
        ) from missing

    functions: list[Function] = []
    for row in csv.reader(io.StringIO(completed.stdout)):
        if len(row) < 11:
            continue
        functions.append(
            Function(
                file=row[6],
                name=row[7],
                ccn=int(row[1]),
                start=int(row[9]),
                end=int(row[10]),
            )
        )
    return functions


class CoverageIndex:
    def __init__(self, covered_by_file: dict[str, dict[int, bool]]):
        self._by_realpath = covered_by_file
        basenames: dict[str, list[str]] = {}
        for path in covered_by_file:
            basenames.setdefault(os.path.basename(path), []).append(path)
        self._unique_basenames = {
            name: paths[0] for name, paths in basenames.items() if len(paths) == 1
        }

    def _resolve(self, file: str) -> dict[int, bool] | None:
        realpath = os.path.realpath(file)
        if realpath in self._by_realpath:
            return self._by_realpath[realpath]
        fallback = self._unique_basenames.get(os.path.basename(file))
        if fallback is not None:
            return self._by_realpath[fallback]
        return None

    def fraction(self, file: str, start: int, end: int) -> float:
        lines = self._resolve(file)
        if lines is None:
            return 0.0
        in_range = [covered for line, covered in lines.items() if start <= line <= end]
        if not in_range:
            return 1.0
        return sum(1 for covered in in_range if covered) / len(in_range)


def _index_istanbul(data: dict) -> dict[str, dict[int, bool]]:
    covered_by_file: dict[str, dict[int, bool]] = {}
    for path, entry in data.items():
        statement_map = entry.get("statementMap", {})
        hits = entry.get("s", {})
        lines: dict[int, bool] = {}
        for statement_id, location in statement_map.items():
            line = location["start"]["line"]
            was_hit = hits.get(statement_id, 0) > 0
            lines[line] = lines.get(line, False) or was_hit
        covered_by_file[os.path.realpath(path)] = lines
    return covered_by_file


def _index_coverage_py(data: dict) -> dict[str, dict[int, bool]]:
    covered_by_file: dict[str, dict[int, bool]] = {}
    for path, entry in data.get("files", {}).items():
        lines: dict[int, bool] = {}
        for line in entry.get("executed_lines", []):
            lines[line] = True
        for line in entry.get("missing_lines", []):
            lines.setdefault(line, False)
        covered_by_file[os.path.realpath(path)] = lines
    return covered_by_file


def _index_file(path: str, fmt: str) -> dict[str, dict[int, bool]]:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as broken:
        raise OperationalError(f"could not read coverage JSON at {path}: {broken}") from broken

    resolved = fmt
    if resolved == "auto":
        resolved = "coverage-py" if isinstance(data.get("files"), dict) else "istanbul"
    if resolved == "istanbul":
        return _index_istanbul(data)
    if resolved == "coverage-py":
        return _index_coverage_py(data)
    raise OperationalError(f"unknown coverage format: {fmt}")


def load_coverage(paths: list[str], fmt: str) -> CoverageIndex:
    merged: dict[str, dict[int, bool]] = {}
    for path in paths:
        for realpath, lines in _index_file(path, fmt).items():
            target = merged.setdefault(realpath, {})
            for line, covered in lines.items():
                target[line] = target.get(line, False) or covered
    return CoverageIndex(merged)


def _diff_line_set(path: str) -> set[int]:
    diff = subprocess.run(
        ["git", "diff", "-U0", "HEAD", "--", path],
        capture_output=True,
        text=True,
        check=False,
    )
    changed: set[int] = set()
    for line in diff.stdout.splitlines():
        if not line.startswith("@@"):
            continue
        added = line.split("+", 1)[1].split(" ", 1)[0]
        start_text, _, count_text = added.partition(",")
        start = int(start_text)
        count = int(count_text) if count_text else 1
        for offset in range(count):
            changed.add(start + offset)
    return changed


def touched_ranges() -> dict[str, object]:
    status = subprocess.run(
        ["git", "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=False,
    )
    if status.returncode != 0:
        raise OperationalError("git status failed — --changed-only requires a git working tree")
    ranges: dict[str, object] = {}
    for line in status.stdout.splitlines():
        if not line.strip():
            continue
        code = line[:2]
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        real = os.path.realpath(path)
        if "?" in code:
            ranges[real] = "ALL"
        elif "D" not in code:
            ranges[real] = _diff_line_set(real)
    return ranges


def _is_scorable_source(realpath: str) -> bool:
    if "/node_modules/" in realpath or "/.vite/" in realpath:
        return False
    basename = os.path.basename(realpath)
    if ".spec." in basename or ".test." in basename:
        return False
    return "/__tests__/" not in realpath


def _under_source_paths(realpath: str, source_paths: list[str]) -> bool:
    if not _is_scorable_source(realpath):
        return False
    prefixes = [os.path.realpath(path) for path in source_paths] or [os.path.realpath(".")]
    return any(realpath == prefix or realpath.startswith(prefix + os.sep) for prefix in prefixes)


def _is_touched(function: Function, ranges: dict[str, object]) -> bool:
    changed = ranges.get(os.path.realpath(function.file))
    if changed is None:
        return False
    if changed == "ALL":
        return True
    return any(function.start <= line <= function.end for line in changed)


def crap(ccn: int, coverage: float) -> float:
    return ccn**2 * (1 - coverage) ** 3 + ccn


def evaluate(functions: list[Function], coverage: CoverageIndex, ceiling: float) -> list[dict]:
    offenders: list[dict] = []
    for function in functions:
        fraction = coverage.fraction(function.file, function.start, function.end)
        score = crap(function.ccn, fraction)
        if score > ceiling:
            offenders.append(
                {
                    "file": function.file,
                    "function": function.name,
                    "line": function.start,
                    "ccn": function.ccn,
                    "coverage": round(fraction, 4),
                    "crap": round(score, 2),
                }
            )
    offenders.sort(key=lambda offender: offender["crap"], reverse=True)
    return offenders


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="crap-guard.py", add_help=True)
    parser.add_argument("--coverage", required=True, action="append")
    parser.add_argument("--format", default="auto", choices=["auto", "istanbul", "coverage-py"])
    parser.add_argument("--ceiling", type=float, default=30.0)
    parser.add_argument("--changed-only", action="store_true")
    parser.add_argument("paths", nargs="*", default=["."])
    args = parser.parse_args(argv)

    try:
        coverage = load_coverage(args.coverage, args.format)
        if args.changed_only:
            ranges = touched_ranges()
            scoped = [path for path in ranges if _under_source_paths(path, args.paths)]
            if not scoped:
                print(json.dumps({"pass": True, "ceiling": args.ceiling, "offenders": []}))
                return 0
            functions = [function for function in run_lizard(scoped) if _is_touched(function, ranges)]
        else:
            functions = run_lizard(args.paths or ["."])
    except OperationalError as failure:
        print(f"crap-guard: {failure}", file=sys.stderr)
        return 2

    offenders = evaluate(functions, coverage, args.ceiling)
    verdict = {"pass": not offenders, "ceiling": args.ceiling, "offenders": offenders}
    print(json.dumps(verdict))
    return 0 if verdict["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
