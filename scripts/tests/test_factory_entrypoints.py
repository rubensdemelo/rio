"""Exercise command dispatch without running Xcode or requiring a signing identity."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeTestDispatchTests(unittest.TestCase):
    def run_tests(self, *arguments):
        with tempfile.TemporaryDirectory() as directory:
            for name, body in {
                'python3': 'exit 0',
                'uname': 'echo Darwin',
                'xcodebuild': 'printf "%s\\n" "$@"',
            }.items():
                command = Path(directory) / name
                command.write_text('#!/bin/bash\n' + body + '\n')
                command.chmod(0o755)
            environment = dict(os.environ, PATH=directory + ':' + os.environ['PATH'])
            return subprocess.run(['/bin/bash', str(ROOT / 'scripts/factory/test.sh'), *arguments],
                                  env=environment, capture_output=True, text=True)

    def test_all_tests_dispatch_with_no_arguments_under_system_bash(self):
        result = self.run_tests()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('test\n', result.stdout)
        self.assertNotIn('-only-testing:', result.stdout)
        self.assertIn('CODE_SIGNING_ALLOWED=NO', result.stdout)

    def test_focused_selector_reaches_xcode(self):
        result = self.run_tests('RioTests/SessionLifecycleTests')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('-only-testing:RioTests/SessionLifecycleTests\n', result.stdout)
