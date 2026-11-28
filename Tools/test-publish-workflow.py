"""Exercise tag-release workflow branches with stubbed publish tools, never real credentials."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/publish.yml"


def step(name):
    text = WORKFLOW.read_text()
    start = text.index("      - name: " + name + "\n")
    following = text.find("\n      - name:", start + 1)
    block = text[start:following if following != -1 else None]
    script = block.split("        run: |\n", 1)[1]
    lines = []
    for line in script.splitlines():
        if line and not line.startswith("          "):
            break
        lines.append(line[10:] if line else "")
    return block, "\n".join(lines)


class PublishWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.log = self.directory / "calls"
        for tool in ("pod", "gh", "swift"):
            executable = self.directory / tool
            executable.write_text(
                '#!/bin/sh\nprintf "%s\\n" "' + tool + ' $*" >> "$CALL_LOG"\n'
                'if [ "' + tool + '" = pod ]; then exit "${POD_EXIT:-0}"; fi\n'
            )
            executable.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.directory) + os.pathsep + os.environ["PATH"],
                        CALL_LOG=str(self.log), GITHUB_OUTPUT=str(self.directory / "output"))
        # The test deliberately never reads an inherited publishing credential.
        self.env.pop("COCOAPODS_TRUNK_TOKEN", None)
        self.env.pop("GH_TOKEN", None)

    def run_script(self, script, **values):
        return subprocess.run(["bash", "-e", "-c", script], cwd=ROOT,
                              env=dict(self.env, **values), capture_output=True, text=True)

    def release(self, tag, token="", pod_exit="0"):
        block, script = step("Publish to CocoaPods trunk")
        guard = re.search(r"^        if: (.+)$", block, re.MULTILINE)
        self.assertIsNotNone(guard)
        self.assertEqual(guard.group(1), "github.ref_name != 'v2.1.0'")
        # Evaluate the exact single comparison supported above, like the Actions step condition.
        excluded = re.fullmatch(r"github.ref_name != '([^']+)'", guard.group(1)).group(1)
        if tag != excluded:
            result = self.run_script(script, COCOAPODS_TRUNK_TOKEN=token,
                                     PODSPEC="ABsmartly.podspec", POD_EXIT=pod_exit)
            if result.returncode:
                return result
        _, script = step("Create GitHub release")
        return self.run_script(script, TAG=tag, MAJOR=tag[1:].split(".")[0])

    def calls(self):
        return self.log.read_text() if self.log.exists() else ""

    def test_210_skips_trunk_without_token_but_creates_release(self):
        result = self.release("v2.1.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("pod ", self.calls())
        self.assertIn("gh release create v2.1.0", self.calls())
        self.assertIn("--latest=true", self.calls())

    def test_other_tags_keep_trunk_before_github_release(self):
        for tag in ("v2.0.0", "v2.1.1", "v2.2.0", "v2.1.0-rc.1", "v1.5.1"):
            with self.subTest(tag=tag):
                self.log.unlink(missing_ok=True)
                result = self.release(tag, token="test-placeholder")
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.calls().splitlines()
                self.assertEqual(calls[0], "pod trunk push ABsmartly.podspec --allow-warnings --skip-tests")
                self.assertTrue(calls[1].startswith("gh release create " + tag))
                self.assertIn("--latest=" + ("false" if tag.startswith("v1.") else "true"), calls[1])

    def test_other_tags_still_require_token(self):
        result = self.release("v2.1.1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("COCOAPODS_TRUNK_TOKEN secret is not set", result.stdout)
        self.assertEqual(self.calls(), "")

    def test_trunk_failure_still_prevents_github_release(self):
        result = self.release("v2.2.0", token="test-placeholder", pod_exit="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("gh ", self.calls())

    def test_version_checks_still_run_for_210(self):
        block, script = step("Check versions match the tag")
        self.assertNotRegex(block, r"(?m)^        if:")
        # Run against a copy pinned to 2.1.0, so the check does not depend on the working tree's
        # version as later releases bump it.
        tree = self.directory / "tree"
        (tree / "Sources").mkdir(parents=True)
        (tree / "ABsmartly.podspec").write_text("Pod::Spec.new do |spec|\n  spec.version = '2.1.0'\nend\n")
        (tree / "Sources" / "Version.swift").write_text('enum SDKVersion {\n\tstatic let version = "2.1.0"\n}\n')
        run = lambda tag: subprocess.run(["bash", "-e", "-c", script], cwd=tree,
                                         env=dict(self.env, TAG=tag), capture_output=True, text=True)
        result = run("v2.1.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tag=2.1.0 podspec=2.1.0 sdk=2.1.0", result.stdout)
        result = run("v2.1.1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stdout)

    def test_version_check_accepts_the_working_tree_version(self):
        _, script = step("Check versions match the tag")
        podspec = (ROOT / "ABsmartly.podspec").read_text()
        version = re.search(r"spec\.version\s*=\s*'([^']+)'", podspec).group(1)
        result = self.run_script(script, TAG="v" + version)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"tag={version} podspec={version} sdk={version}", result.stdout)

    def test_checks_and_release_have_no_skip_guard(self):
        for name in ("Build and test", "Create GitHub release"):
            with self.subTest(step=name):
                block, _ = step(name) if name != "Build and test" else (WORKFLOW.read_text().split(
                    "      - name: Build and test\n", 1)[1].split("      - name:", 1)[0], "")
                self.assertNotRegex(block, r"(?m)^        if:")
        self.assertIn("        run: swift test", WORKFLOW.read_text())
        self.assertIn("COCOAPODS_TRUNK_TOKEN: ${{ secrets.COCOAPODS_TRUNK_TOKEN }}", WORKFLOW.read_text())
        self.assertIn("      - v*", WORKFLOW.read_text())


if __name__ == "__main__":
    unittest.main()
