#!/usr/bin/env python3
"""Test command flow only; stubs do not demonstrate CocoaPods builds."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().with_name("validate-cocoapods.sh")
REPO = f" @{SCRIPT.parent.parent}"
QUICK = "pod" + REPO + " spec lint ABSmartlySwiftSDK.podspec --quick --allow-warnings"
FULL = (
    "pod" + REPO + " lib lint ABSmartlySwiftSDK.podspec "
    "--platforms=ios,osx,tvos,watchos --allow-warnings --verbose"
)


class ValidationCommandsTest(unittest.TestCase):
    def run_validation(self, platform="Darwin", quick_status=0, full_status=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            trace = root / "trace"
            stub = '''#!/usr/bin/env bash
set -eu
name=${0##*/}
if [[ $name == uname ]]; then
  echo "$TEST_PLATFORM"
  exit 0
fi
printf '%s' "$name" >> "$TEST_TRACE"
if [[ $name == pod ]]; then printf ' @%s' "$PWD" >> "$TEST_TRACE"; fi
printf ' %s' "$@" >> "$TEST_TRACE"
printf '\\n' >> "$TEST_TRACE"
if [[ $name == pod && ${1:-} == spec ]]; then
  exit "$TEST_QUICK_STATUS"
elif [[ $name == pod && ${1:-} == lib ]]; then
  exit "$TEST_FULL_STATUS"
fi
'''
            for name in ("uname", "xcodebuild", "swift", "pod"):
                tool = root / name
                tool.write_text(stub)
                tool.chmod(0o755)
            environment = dict(
                os.environ,
                PATH=str(root) + os.pathsep + os.environ["PATH"],
                TEST_PLATFORM=platform,
                TEST_TRACE=str(trace),
                TEST_QUICK_STATUS=str(quick_status),
                TEST_FULL_STATUS=str(full_status),
            )
            result = subprocess.run(
                ["bash", str(SCRIPT)], env=environment, capture_output=True, text=True, cwd=directory
            )
            commands = trace.read_text().splitlines() if trace.exists() else []
            return result, commands

    def test_darwin_runs_full_local_lint_for_all_platforms(self):
        result, commands = self.run_validation()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands, [
            "xcodebuild -version", "swift --version", "pod" + REPO + " --version", QUICK, FULL
        ])

    def test_linux_fails_before_invoking_apple_tools(self):
        result, commands = self.run_validation(platform="Linux")
        self.assertEqual(result.returncode, 1)
        self.assertIn("requires macOS and Xcode", result.stderr)
        self.assertEqual(commands, [])

    def test_other_non_darwin_hosts_fail_before_invoking_apple_tools(self):
        result, commands = self.run_validation(platform="FreeBSD")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(commands, [])

    def test_quick_failure_stops_before_full_lint(self):
        result, commands = self.run_validation(quick_status=13)
        self.assertEqual(result.returncode, 13)
        self.assertEqual(commands[-1], QUICK)
        self.assertNotIn(FULL, commands)

    def test_full_failure_is_not_suppressed(self):
        result, commands = self.run_validation(full_status=17)
        self.assertEqual(result.returncode, 17)
        self.assertEqual(commands[-1], FULL)


if __name__ == "__main__":
    unittest.main()
