# Copyright 2026 TM-59
"""Drive the real terminal program and check round boundaries and process exit."""

import json
import os
import shutil
import signal
import subprocess as sp
import sys
import time
import xml.etree.ElementTree as ET  # writes the report; nothing untrusted is parsed
from contextlib import suppress
from pathlib import Path

cfg = json.loads(Path("scripts/commands.json").read_text())
folder = Path(os.environ["RESULT_DIR"])
lose = "t\nt\n1s\n2s\nt\nt\nt\nt\n1s\n2s\nt\nt\nt\nt\n"
STARTS_SEEN = 3  # first round, retry, next round
RESULTS_SEEN = 2  # the two lost rounds
SCREEN_ROWS, SCREEN_COLUMNS = 24, 80
CLI_SECONDS = 20


def tool(name: str) -> str:
    """Return the absolute path of program `name` on PATH, or stop with a clear message."""
    path = shutil.which(name)
    if path is None:
        message = f"{name} was not found on PATH; install it (see README) and run again"
        raise SystemExit(message)
    return path


MIX = tool("mix")


class SmokeError(Exception):
    """A CLI session did not behave as the case expects."""


def expect(*, condition: bool, message: str) -> None:
    """Raise SmokeError with `message` unless `condition` holds."""
    if not condition:
        raise SmokeError(message)


def group_alive(group: int) -> bool:
    """Return whether any live (non-zombie) process belongs to session group `group`."""
    for path in Path("/proc").glob("[0-9]*/stat"):
        try:
            fields = path.read_text().rsplit(") ", 1)[1].split()
            if int(fields[2]) == group and fields[0] != "Z":
                return True
        except OSError, IndexError, ValueError:
            continue
    return False


def check_rounds(stdout: str) -> None:
    """Check that retry repeats the round exactly and next starts a different seed."""
    screens = stdout.split("\x1b[2J\x1b[H")[1:]
    starts = [s for s in screens if "tick 0/10" in s]
    results = [s for s in screens if "PARCEL RELAY | LOST" in s]
    expect(condition=len(starts) == STARTS_SEEN, message="expected three round starts")
    expect(condition=starts[0] == starts[1], message="retry did not repeat the round")
    expect(condition=len(results) == RESULTS_SEEN, message="expected two result screens")
    expect(condition=results[0] == results[1], message="the two results differ")
    expect(condition="seed 60" in starts[2], message="next did not move to seed 60")
    expect(condition="bridge CLOSED 5 and 9" in starts[2], message="seed 60 bridge closures")
    expect(condition="delivered 0/4 | lost 0" in starts[2], message="next round is not fresh")
    for screen in results:
        expect(
            condition="RESULT: delivered 0 | late 0 | lost 4" in screen,
            message="result line differs",
        )
        expect(condition="#1 C1: LOST tick 4" in screen, message="first loss line differs")
        expect(condition="#4 C2: LOST tick 8" in screen, message="last loss line differs")
        lines = screen.removesuffix("> ").strip().splitlines()
        expect(
            condition=len(lines) <= SCREEN_ROWS and max(map(len, lines)) <= SCREEN_COLUMNS,
            message="result screen is larger than 80 x 24",
        )
    (folder / "result-screen.txt").write_text(results[0].removesuffix("> ").rstrip() + "\n")


def run_case(commands: str, expected: str | None, name: str) -> sp.Popen[str]:
    """Play one session with `commands` as input and check its output and process group."""
    process = sp.Popen(
        [MIX, "run", "-e", "ParcelRelay.main()"],
        stdin=sp.PIPE,
        stdout=sp.PIPE,
        stderr=sp.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(commands, timeout=CLI_SECONDS)
        (folder / (name + ".log")).write_text(stdout + stderr)
        expect(
            condition=process.returncode == 0,
            message=f"CLI exit {process.returncode}: {stderr}",
        )
        expect(condition=not stderr.strip(), message=stderr)
        if expected:
            expect(condition=expected in stdout, message=f"Missing output: {expected}")
        else:
            check_rounds(stdout)
        deadline = time.monotonic() + 1
        while group_alive(process.pid) and time.monotonic() < deadline:
            time.sleep(0.01)
        expect(
            condition=not group_alive(process.pid),
            message="CLI left a live process in its session group",
        )
    finally:
        if process.poll() is None or group_alive(process.pid):
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    return process


cases = [
    ("victory", cfg["demo"] + "q\n", "RESULT: delivered 4 | late 0 | lost 0"),
    ("retry-next-quit", lose + "r\n" + lose + "n\nq\n", None),
    ("late", "t\n" * 8 + "1\n2s\nt\nt\nq\n", "#1 C1: LATE tick 10: safe needs 1 tick(s) (sent 8)."),
    ("quit-active", "1\n2\nq\n", "Courier 2: safe (3 ticks)"),
    ("eof-active", "", "PARCEL RELAY | PLAYING"),
    ("eof-result", "t\n" * 10, "Goal shortfall: 4"),
]
root = ET.Element("testsuite", name="CLI session", tests=str(len(cases)), failures="0", errors="0")
failures = 0
for name, commands, expected in cases:
    started = time.monotonic()
    case = ET.SubElement(root, "testcase", name="REQ-session " + name)
    try:
        run_case(commands, expected, name)
        sys.stdout.write(name + ": pass; process group stopped\n")
    except (SmokeError, OSError, sp.TimeoutExpired) as error:
        failures += 1
        ET.SubElement(case, "failure", message=str(error)).text = str(error)
        sys.stdout.write(name + ": FAIL: " + str(error) + "\n")
    finally:
        case.set("time", str(time.monotonic() - started))
root.set("failures", str(failures))
ET.ElementTree(root).write(folder / "e2e.xml", encoding="unicode")
raise SystemExit(bool(failures))
