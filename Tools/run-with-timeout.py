#!/usr/bin/env python3
"""Bound a test command, including Swift test runners in separate process groups.

Works on Linux and macOS without GNU timeout. Polling tracks descendants before
Swift's driver can reparent them, so a timed-out mutant cannot leave runners alive.
"""
import os
import signal
import subprocess
import sys
import time


def descendants(known):
    rows = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
    parents = [tuple(map(int, row.split())) for row in rows.splitlines()]
    result = set(known)
    while True:
        added = {pid for pid, parent in parents if parent in result} - result
        if not added:
            return result
        result.update(added)


def stop(process, known):
    # Runners can call setsid(), so kill each descendant as well as the driver's group.
    known = descendants(known)
    for pid in known:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait()


def run(seconds, command):
    process = subprocess.Popen(command, start_new_session=True)
    known = {process.pid}
    deadline = time.monotonic() + seconds
    try:
        while process.poll() is None:
            known = descendants(known)
            if time.monotonic() >= deadline:
                print(f"Timed out after {seconds}s: {' '.join(command)}", file=sys.stderr, flush=True)
                stop(process, known)
                return 124
            time.sleep(0.05)
        return process.returncode
    except BaseException:
        stop(process, known)
        raise


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("Usage: run-with-timeout.py SECONDS COMMAND [ARG ...]")
    sys.exit(run(float(sys.argv[1]), sys.argv[2:]))
