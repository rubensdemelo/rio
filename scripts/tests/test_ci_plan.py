import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('ci_plan', Path(__file__).parents[1] / 'ci-plan.py')
ci_plan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci_plan)


class PushPlanTests(unittest.TestCase):
    def test_factory_only_paths_skip_verification(self):
        self.assertFalse(ci_plan.needs_verification([
            '.factory-version', '.claude/settings.json', '.agents/skills/spec/SKILL.md',
            'AGENTS.md', 'CLAUDE.md', 'REVIEW.md', 'REVIEW.local.md', 'docs/PRODUCT.md']))

    def test_code_mixed_with_factory_paths_runs_verification(self):
        self.assertTrue(ci_plan.needs_verification(['.factory-version', 'Rio/App.swift']))

    def test_unknown_range_and_manual_dispatch_run_verification(self):
        self.assertTrue(ci_plan.plan('workflow_dispatch', '', 'HEAD'))
        self.assertTrue(ci_plan.plan('push', '0' * 40, 'HEAD'))
        def missing(args):
            raise subprocess.CalledProcessError(128, args)
        self.assertTrue(ci_plan.plan('push', 'missing', 'HEAD', missing))

    def test_earlier_code_commit_is_not_hidden_by_later_docs_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args], stderr=subprocess.DEVNULL)
            git('init', '-q')
            git('config', 'user.email', 'synthetic@example.invalid')
            git('config', 'user.name', 'Synthetic Test')
            root = Path(directory)
            (root / 'AGENTS.md').write_text('initial')
            git('add', '.'); git('commit', '-qm', 'initial')
            before = git('rev-parse', 'HEAD').decode().strip()
            (root / 'App.swift').write_text('// synthetic')
            git('add', '.'); git('commit', '-qm', 'code')
            (root / 'AGENTS.md').write_text('changed')
            git('add', '.'); git('commit', '-qm', 'docs')
            def run(args):
                return git(*args[1:])
            self.assertTrue(ci_plan.plan('push', before, 'HEAD', run))
            self.assertFalse(ci_plan.plan('push', 'HEAD~1', 'HEAD', run))
