"""Run native reports and a real CLI smoke; preserve every attempt outside Git."""

import datetime as dt
import json
import os
import platform
import subprocess as sp
import sys
import time
from pathlib import Path

from defusedxml import ElementTree
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

TIMEOUT_SECONDS = 180
REQUIREMENTS = ["REQ-finish", "REQ-result", "REQ-session", "REQ-seed"]
UNIT_COMMAND = ["mix", "test", "--seed", "59"]
E2E_COMMAND = [sys.executable, "scripts/cli_smoke.py"]

cfg = json.loads(Path("scripts/commands.json").read_text())
mode = sys.argv[1]


def play(demo_input: str | None) -> int:
    """Run the game in the terminal, optionally feeding the demo input; return its exit code."""
    return sp.run(
        ["mix", "run", "-e", "ParcelRelay.main()"], input=demo_input, text=True, check=False
    ).returncode


def unit(env: dict[str, str]) -> sp.CompletedProcess[str]:
    """Run the ExUnit suite with the fixed seed."""
    return sp.run(
        ["mix", "test", "--seed", "59"],
        env=env,
        text=True,
        capture_output=True,
        timeout=TIMEOUT_SECONDS,
        check=False,
    )


def e2e(env: dict[str, str]) -> sp.CompletedProcess[str]:
    """Drive the real terminal program through the CLI smoke."""
    return sp.run(
        [sys.executable, "scripts/cli_smoke.py"],
        env=env,
        text=True,
        capture_output=True,
        timeout=TIMEOUT_SECONDS,
        check=False,
    )


def junit_counts(report: Path) -> dict[str, int]:
    """Return the test, failure, error and skip counts of one JUnit report (zeros if absent)."""
    if not report.exists():
        return {"tests": 0, "failures": 0, "errors": 0, "skipped": 0}
    cases = list(ElementTree.parse(report).iter("testcase"))
    return {
        "tests": len(cases),
        **{
            key: sum(case.find(tag) is not None for case in cases)
            for key, tag in [("failures", "failure"), ("errors", "error"), ("skipped", "skipped")]
        },
    }


def run_suite(
    kind: str, command: list[str], runner: Callable[[dict[str, str]], sp.CompletedProcess[str]]
) -> dict[str, object]:
    """Run one suite, keep its log and JUnit report, and return its summary entry."""
    tick = time.monotonic()
    code = 1
    try:
        result = runner(dict(os.environ, RESULT_DIR=str(folder.resolve())))
        code = result.returncode
        (folder / (kind + ".log")).write_text(result.stdout + result.stderr)
        sys.stdout.write(f"{result.stdout} {result.stderr}\n")
    except (OSError, sp.TimeoutExpired) as error:
        (folder / (kind + ".log")).write_text(str(error))
    report = folder / (kind + ".xml")
    counts = junit_counts(report)
    passed = code == 0 and counts["tests"] > 0 and not counts["failures"] and not counts["errors"]
    return {
        "kind": kind,
        "framework": cfg["language"] if kind == "unit" else "CLI harness",
        "command": command,
        "status": "pass" if passed else "error",
        "duration_seconds": time.monotonic() - tick,
        "counts": counts,
        "junit": str(report) if report.exists() else None,
        "requirements": REQUIREMENTS,
        "reason": None if passed else "See local log",
    }


if mode in {"play", "demo"}:
    raise SystemExit(play(cfg["demo"] if mode == "demo" else None))
started = dt.datetime.now(dt.UTC)
run_id = started.strftime("%Y%m%dT%H%M%S%fZ")
folder = Path("test-results") / run_id
folder.mkdir(parents=True)
suites = [run_suite("unit", UNIT_COMMAND, unit)]
if mode == "check":
    suites.append(run_suite("e2e", E2E_COMMAND, e2e))
finished = dt.datetime.now(dt.UTC)
suite_counts = [suite["counts"] for suite in suites if isinstance(suite["counts"], dict)]
counts = {key: sum(c[key] for c in suite_counts) for key in suite_counts[0]}
passed = all(suite["status"] == "pass" for suite in suites)
summary = {
    "schema_version": 1,
    "run_id": run_id,
    "repository": cfg["repository"],
    "commit": sp.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "dirty": bool(sp.check_output(["git", "status", "--porcelain"])),
    "started_at": started.isoformat(),
    "finished_at": finished.isoformat(),
    "duration_seconds": (finished - started).total_seconds(),
    "status": "pass" if passed else "error",
    "exit_code": 0 if passed else 1,
    "environment": {
        "os": platform.system(),
        "architecture": platform.machine(),
        "tools": {"python": platform.python_version(), "language": cfg["language"]},
        "jobs": 1,
        "seed": 59,
    },
    "counts": counts,
    "coverage": {
        "status": "not_measured",
        "line_percent": None,
        "branch_percent": None,
        "reason": "M1 verifies rules and CLI; coverage deferred",
    },
    "metrics": [],
    "suites": suites,
}
text = json.dumps(summary, indent=2) + "\n"
(folder / "summary.json").write_text(text)
Path("test-results/summary.json").write_text(text)
raise SystemExit(summary["exit_code"])
