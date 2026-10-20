"""Exercise dispatch with stubs; this does not validate native app code."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeTestDispatchTests(unittest.TestCase):
    def run_entrypoint(self, script='test', arguments=(), tooling=0, native=0, platform='Darwin'):
        with tempfile.TemporaryDirectory() as directory:
            trace = Path(directory) / 'trace'
            for name, body in {
                'python3': 'echo tooling >> "$TRACE"; exit "$TOOLING_STATUS"',
                'uname': 'echo "$TEST_PLATFORM"',
                'xcodebuild': 'printf "xcode %s\\n" "$*" >> "$TRACE"; exit "$NATIVE_STATUS"',
            }.items():
                command = Path(directory) / name
                command.write_text('#!/bin/bash\n' + body + '\n')
                command.chmod(0o755)
            environment = dict(os.environ, PATH=directory + ':' + os.environ['PATH'],
                               TRACE=str(trace), TOOLING_STATUS=str(tooling),
                               NATIVE_STATUS=str(native), TEST_PLATFORM=platform)
            result = subprocess.run(['/bin/bash', str(ROOT / f'scripts/factory/{script}.sh'), *arguments],
                                    env=environment, capture_output=True, text=True)
            return result, trace.read_text().splitlines() if trace.exists() else []

    def test_all_tests_dispatch_with_no_arguments_under_system_bash(self):
        result, calls = self.run_entrypoint()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0], 'tooling')
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[1].startswith('xcode test '))
        self.assertNotIn('-only-testing:', calls[1])
        self.assertIn('CODE_SIGNING_ALLOWED=NO', calls[1])

    def test_focused_selector_reaches_xcode(self):
        result, calls = self.run_entrypoint(arguments=('RioTests/SessionLifecycleTests',))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('-only-testing:RioTests/SessionLifecycleTests', calls[1])

    def test_excess_selectors_stop_before_tooling(self):
        result, calls = self.run_entrypoint(arguments=('RioTests/One', 'RioTests/Two'))
        self.assertEqual(result.returncode, 2)
        self.assertIn('Usage:', result.stderr)
        self.assertEqual(calls, [])

    def test_tooling_failure_stops_gate_before_xcode(self):
        result, calls = self.run_entrypoint('gate', tooling=17)
        self.assertEqual(result.returncode, 17)
        self.assertEqual(calls, ['tooling'])

    def test_native_failure_stops_gate_before_release(self):
        result, calls = self.run_entrypoint('gate', native=19)
        self.assertEqual(result.returncode, 19)
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[1].startswith('xcode test '))
        self.assertNotIn('-configuration Release', calls[1])

    def test_gate_runs_debug_tests_then_unsigned_release_build(self):
        result, calls = self.run_entrypoint('gate')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 3)
        self.assertEqual(calls[0], 'tooling')
        self.assertTrue(calls[1].startswith('xcode test '))
        self.assertIn('-configuration Debug', calls[1])
        self.assertTrue(calls[2].startswith('xcode build '))
        self.assertIn('-configuration Release', calls[2])
        for call in calls[1:]:
            self.assertIn('CODE_SIGNING_ALLOWED=NO', call)
            self.assertIn('CODE_SIGNING_REQUIRED=NO', call)
            self.assertIn('SWIFT_TREAT_WARNINGS_AS_ERRORS=YES', call)

    def test_non_darwin_refuses_native_work_after_tooling(self):
        result, calls = self.run_entrypoint('gate', platform='Linux')
        self.assertEqual(result.returncode, 2)
        self.assertIn('native tests were NOT run', result.stderr)
        self.assertEqual(calls, ['tooling'])
