"""Exercise rollback.sh in a scratch repository with make stubbed; nothing is installed."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RollbackTests(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.repo)
        (self.repo / 'scripts/factory').mkdir(parents=True)
        (self.repo / 'Config').mkdir()
        shutil.copy(ROOT / 'scripts/factory/rollback.sh', self.repo / 'scripts/factory')
        (self.repo / 'Config/.keep').write_text('')
        (self.repo / '.gitignore').write_text('.build/\nConfig/Development.xcconfig\n')
        self.git('init', '-q', '-b', 'main')
        self.commits = [self.commit(name) for name in ('first', 'second', 'third')]
        (self.repo / 'Config/Development.xcconfig').write_text('DEVELOPMENT_TEAM = TEST\n')
        self.bin = self.repo.parent / f'{self.repo.name}-bin'
        self.bin.mkdir()
        self.addCleanup(shutil.rmtree, self.bin)
        self.trace = self.bin / 'trace'
        # Records the installed commit and whether the local signing settings reached the worktree.
        stub = ('[ "$1" = -C ] || exit 9\n'
                'echo "$(git -C "$2" log -1 --format=%s) $3 $(cat "$2/Config/Development.xcconfig" 2>/dev/null)" >> "$TRACE"\n'
                'exit "$MAKE_STATUS"\n')
        (self.bin / 'make').write_text('#!/bin/bash\n' + stub)
        (self.bin / 'make').chmod(0o755)
        (self.bin / 'uname').write_text('#!/bin/bash\necho Darwin\n')
        (self.bin / 'uname').chmod(0o755)

    def git(self, *arguments):
        return subprocess.run(['git', '-C', str(self.repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                               *arguments], check=True, capture_output=True, text=True).stdout.strip()

    def commit(self, message):
        # Plumbing builds the synthetic history quickly; porcelain commits would run the owner's commit hooks.
        (self.repo / 'version').write_text(message)
        self.git('add', '-A')
        parent = self.git('rev-parse', '--verify', '--quiet', 'HEAD') if (self.repo / '.git/refs/heads/main').exists() else ''
        sha = self.git('commit-tree', self.git('write-tree'), '-m', message, *(['-p', parent] if parent else []))
        self.git('update-ref', 'refs/heads/main', sha)
        return sha

    def rollback(self, *arguments, make_status=0, **environment):
        env = {k: v for k, v in os.environ.items() if k not in ('CI', 'CLAUDE_CODE_REMOTE')}
        env.update(PATH=f'{self.bin}:{os.environ["PATH"]}', TRACE=str(self.trace), MAKE_STATUS=str(make_status),
                   **environment)
        return subprocess.run(['/bin/bash', str(self.repo / 'scripts/factory/rollback.sh'), *arguments],
                              env=env, capture_output=True, text=True)

    def installs(self):
        return self.trace.read_text().splitlines() if self.trace.exists() else []

    def assert_no_worktree_left(self):
        self.assertEqual(len(self.git('worktree', 'list').splitlines()), 1)
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.commits[-1])

    def test_default_installs_the_parent_of_head(self):
        result = self.rollback()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('will build', result.stdout)
        self.assertEqual(self.installs(), ['second install DEVELOPMENT_TEAM = TEST'])
        self.assert_no_worktree_left()

    def test_named_commit_is_installed(self):
        result = self.rollback(self.commits[0])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.installs(), ['first install DEVELOPMENT_TEAM = TEST'])
        self.assert_no_worktree_left()

    def test_failed_install_still_removes_the_worktree(self):
        result = self.rollback(make_status=2)
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_worktree_left()

    def test_unknown_commit_is_refused_before_building(self):
        result = self.rollback('no-such-commit')
        self.assertEqual(result.returncode, 1)
        self.assertIn('unknown commit', result.stderr)
        self.assertEqual(self.installs(), [])

    def test_ci_and_remote_sessions_are_refused(self):
        for variable in ('CI', 'CLAUDE_CODE_REMOTE'):
            result = self.rollback(**{variable: 'true'})
            self.assertEqual(result.returncode, 1)
            self.assertIn('local Mac', result.stderr)
        self.assertEqual(self.installs(), [])


if __name__ == '__main__':
    unittest.main()
