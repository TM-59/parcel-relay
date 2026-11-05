"""Run native reports and a real CLI smoke; preserve every attempt outside Git."""
import datetime as dt
import json
import os
from pathlib import Path
import platform
import subprocess as sp
import sys
import time
import xml.etree.ElementTree as ET

cfg = json.loads(Path("scripts/commands.json").read_text())
if sys.argv[1] in ("play", "demo"):
    raise SystemExit(sp.run(cfg["play"], input=cfg["demo"] if sys.argv[1] == "demo" else None,
                           text=True).returncode)
started = dt.datetime.now(dt.UTC)
run_id = started.strftime("%Y%m%dT%H%M%S%fZ")
folder = Path("test-results") / run_id
folder.mkdir(parents=True)
suites = []
for kind, command in [("unit", cfg["unit"])] + (
        [("e2e", cfg["play"])] if sys.argv[1] == "check" else []):
    tick = time.monotonic()
    code = 1
    try:
        result = sp.run(command, env=dict(os.environ, RESULT_DIR=str(folder.resolve())),
                        input=cfg["demo"] if kind == "e2e" else None, text=True,
                        capture_output=True, timeout=180)
        code = result.returncode
        (folder / (kind + ".log")).write_text(result.stdout + result.stderr)
        print(result.stdout, result.stderr)
        if kind == "e2e":
            code = int(code != 0 or "WON" not in result.stdout)
    except (OSError, sp.TimeoutExpired) as error:
        (folder / (kind + ".log")).write_text(str(error))
    report = folder / (kind + ".xml")
    if kind == "e2e":
        root = ET.Element("testsuite", tests="1", failures=str(code), errors="0")
        case = ET.SubElement(root, "testcase", name="REQ-finish real CLI victory")
        if code:
            ET.SubElement(case, "failure", message="CLI did not reach WON")
        ET.ElementTree(root).write(report, encoding="unicode")
    counts = dict(tests=0, failures=0, errors=0, skipped=0)
    if report.exists():
        cases = list(ET.parse(report).getroot().iter("testcase"))
        counts = dict(tests=len(cases), **{k: sum(c.find(tag) is not None for c in cases)
                      for k, tag in [("failures", "failure"), ("errors", "error"), ("skipped", "skipped")]})
    passed = code == 0 and counts["tests"] > 0 and not counts["failures"] and not counts["errors"]
    suites.append(dict(kind=kind, framework=cfg["language"] if kind == "unit" else "CLI harness",
        command=command, status="pass" if passed else "error", duration_seconds=time.monotonic()-tick,
        counts=counts, junit=str(report) if report.exists() else None,
        requirements=["REQ-finish"], reason=None if passed else "See local log"))
finished = dt.datetime.now(dt.UTC)
counts = {k: sum(s["counts"][k] for s in suites) for k in suites[0]["counts"]}
passed = all(s["status"] == "pass" for s in suites)
summary = dict(schema_version=1, run_id=run_id, repository=cfg["repository"],
    commit=sp.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    dirty=bool(sp.check_output(["git", "status", "--porcelain"])),
    started_at=started.isoformat(), finished_at=finished.isoformat(),
    duration_seconds=(finished-started).total_seconds(), status="pass" if passed else "error",
    exit_code=0 if passed else 1, environment=dict(os=platform.system(), architecture=platform.machine(),
        tools={"python":platform.python_version(), "language":cfg["language"]}, jobs=1, seed=59),
    counts=counts, coverage=dict(status="not_measured", line_percent=None, branch_percent=None,
        reason="M1 verifies rules and CLI; coverage deferred"), metrics=[], suites=suites)
text = json.dumps(summary, indent=2) + "\n"
(folder / "summary.json").write_text(text)
Path("test-results/summary.json").write_text(text)
raise SystemExit(summary["exit_code"])
