"""Drive the real terminal program and check round boundaries and process exit."""
import json
import os
from pathlib import Path
import signal
import subprocess as sp
import time
import xml.etree.ElementTree as ET

cfg = json.loads(Path("scripts/commands.json").read_text())
folder = Path(os.environ["RESULT_DIR"])
lose = "t\nt\n1s\n2s\nt\nt\nt\nt\n1s\n2s\nt\nt\nt\nt\n"


def group_alive(group):
    for path in Path("/proc").glob("[0-9]*/stat"):
        try:
            fields = path.read_text().rsplit(") ", 1)[1].split()
            if int(fields[2]) == group and fields[0] != "Z":
                return True
        except (OSError, IndexError, ValueError):
            continue
    return False


def check_rounds(stdout):
    screens = stdout.split("\x1b[2J\x1b[H")[1:]
    starts = [s for s in screens if "tick 0/10" in s]
    results = [s for s in screens if "PARCEL RELAY | LOST" in s]
    assert len(starts) == 3 and starts[0] == starts[1]
    assert len(results) == 2 and results[0] == results[1]
    assert "seed 60" in starts[2] and "bridge CLOSED 5 and 9" in starts[2]
    assert "delivered 0/4 | lost 0" in starts[2]
    for screen in results:
        assert "RESULT: delivered 0 | late 0 | lost 4" in screen
        assert "#1 C1: LOST tick 4" in screen and "#4 C2: LOST tick 8" in screen
        lines = screen.removesuffix("> ").strip().splitlines()
        assert len(lines) <= 24 and max(map(len, lines)) <= 80
    (folder / "result-screen.txt").write_text(results[0].removesuffix("> ").rstrip() + "\n")


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
    process = None
    try:
        process = sp.Popen(cfg["play"], stdin=sp.PIPE, stdout=sp.PIPE, stderr=sp.PIPE,
                           text=True, start_new_session=True)
        stdout, stderr = process.communicate(commands, timeout=20)
        (folder / (name + ".log")).write_text(stdout + stderr)
        assert process.returncode == 0, f"CLI exit {process.returncode}: {stderr}"
        assert not stderr.strip(), stderr
        if expected:
            assert expected in stdout, f"Missing output: {expected}"
        else:
            check_rounds(stdout)
        deadline = time.monotonic() + 1
        while group_alive(process.pid) and time.monotonic() < deadline:
            time.sleep(0.01)
        assert not group_alive(process.pid), "CLI left a live process in its session group"
        print(name + ": pass; process group stopped")
    except (AssertionError, OSError, sp.TimeoutExpired) as error:
        failures += 1
        ET.SubElement(case, "failure", message=str(error)).text = str(error)
        print(name + ": FAIL: " + str(error))
    finally:
        if process is not None and (process.poll() is None or group_alive(process.pid)):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        case.set("time", str(time.monotonic() - started))
root.set("failures", str(failures))
ET.ElementTree(root).write(folder / "e2e.xml", encoding="unicode")
raise SystemExit(bool(failures))
