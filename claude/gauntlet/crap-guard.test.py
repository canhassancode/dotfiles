#!/usr/bin/env python3
"""Run: python3 crap-guard.test.py   Exit 0 when every case passes.

The end-to-end cases need `lizard` on PATH; the unit cases do not.
"""

import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("crap_guard", os.path.join(_here, "crap-guard.py"))
guard = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = guard
_spec.loader.exec_module(guard)


GNARLY = """function simple(a) { return a + 1; }
function gnarly(x) {
  if (x > 0) { if (x > 10) { return 1; } else { return 2; } }
  else if (x < -10) { return 3; }
  for (let i = 0; i < x; i++) { if (i % 2) { continue; } }
  return x ? 4 : 5;
}
"""


def istanbul_json(source_path: str, hit: int) -> dict:
    return {
        source_path: {
            "path": source_path,
            "statementMap": {
                "0": {"start": {"line": 2}, "end": {"line": 2}},
                "1": {"start": {"line": 3}, "end": {"line": 3}},
                "2": {"start": {"line": 6}, "end": {"line": 6}},
            },
            "s": {"0": hit, "1": hit, "2": hit},
        }
    }


class FormulaTests(unittest.TestCase):
    def test_boundary(self):
        self.assertEqual(guard.crap(5, 0.0), 30)

    def test_full_coverage_reduces_to_complexity(self):
        self.assertEqual(guard.crap(7, 1.0), 7)

    def test_uncovered_complexity_squares(self):
        self.assertEqual(guard.crap(7, 0.0), 56)


class CoverageIndexTests(unittest.TestCase):
    def test_absent_file_is_uncovered(self):
        index = guard.CoverageIndex({})
        self.assertEqual(index.fraction("/nowhere.js", 1, 9), 0.0)

    def test_no_lines_in_range_has_nothing_to_cover(self):
        index = guard.CoverageIndex({os.path.realpath("/a.js"): {5: True}})
        self.assertEqual(index.fraction("/a.js", 1, 3), 1.0)

    def test_partial_range_fraction(self):
        index = guard.CoverageIndex({os.path.realpath("/a.js"): {2: True, 3: False, 6: True}})
        self.assertAlmostEqual(index.fraction("/a.js", 2, 7), 2 / 3)

    def test_basename_fallback_when_realpath_misses(self):
        index = guard.CoverageIndex({os.path.realpath("/elsewhere/a.js"): {2: True}})
        self.assertEqual(index.fraction("./a.js", 2, 2), 1.0)


class FormatTests(unittest.TestCase):
    def test_auto_detects_coverage_py(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cov.json")
            with open(path, "w") as handle:
                json.dump({"files": {"m.py": {"executed_lines": [1], "missing_lines": [2]}}}, handle)
            index = guard.load_coverage(path, "auto")
            self.assertAlmostEqual(index.fraction(os.path.realpath("m.py"), 1, 2), 0.5)

    def test_auto_detects_istanbul(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "a.js")
            path = os.path.join(tmp, "cov.json")
            with open(path, "w") as handle:
                json.dump(istanbul_json(src, 1), handle)
            index = guard.load_coverage(path, "auto")
            self.assertEqual(index.fraction(src, 2, 7), 1.0)

    def test_bad_path_is_operational_error(self):
        with self.assertRaises(guard.OperationalError):
            guard.load_coverage("/no/such/file.json", "auto")


class EndToEndTests(unittest.TestCase):
    def _run(self, hit: int):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "sample.js")
            cov = os.path.join(tmp, "cov.json")
            with open(src, "w") as handle:
                handle.write(GNARLY)
            with open(cov, "w") as handle:
                json.dump(istanbul_json(src, hit), handle)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = guard.main(["--coverage", cov, src])
            return code, json.loads(out.getvalue())

    def test_uncovered_gnarly_function_fails(self):
        code, verdict = self._run(hit=0)
        self.assertEqual(code, 1)
        self.assertFalse(verdict["pass"])
        names = [offender["function"] for offender in verdict["offenders"]]
        self.assertIn("gnarly", names)
        self.assertNotIn("simple", names)

    def test_fully_covered_gnarly_function_passes(self):
        code, verdict = self._run(hit=3)
        self.assertEqual(code, 0)
        self.assertTrue(verdict["pass"])
        self.assertEqual(verdict["offenders"], [])

    def test_operational_error_exit_code(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = guard.main(["--coverage", "/no/such.json", "."])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
