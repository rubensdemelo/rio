"""Send synthetic command text to the hook; never execute the supplied command."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / '.agents/skills/git-guardrails-claude-code/scripts/block-dangerous-git.sh'


@unittest.skipUnless(shutil.which('jq'), 'Guardrail JSON parsing requires jq')
class GitGuardrailTests(unittest.TestCase):
    def run_hook(self, command):
        return subprocess.run(
            ['/bin/bash', str(HOOK)],
            input=json.dumps({'tool_input': {'command': command}}),
            capture_output=True, text=True,
        )

    def test_blocked_push_reports_rule_without_command_credentials(self):
        url = 'https://synthetic-user:SYNTHETIC_SECRET@example.invalid/repo'
        result = self.run_hook('git push ' + url)
        self.assertEqual(result.returncode, 2)
        self.assertIn('BLOCKED', result.stderr)
        self.assertIn('git push', result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertNotIn('SYNTHETIC_SECRET', result.stderr)
        self.assertNotIn(url, result.stderr)

    def test_read_only_status_is_allowed(self):
        result = self.run_hook('git status')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr, '')
