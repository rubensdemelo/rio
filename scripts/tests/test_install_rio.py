"""Exercise install-rio.sh with stubbed macOS tools; no real app is installed."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class InstallRioTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory)
        scripts = self.directory / 'scripts'
        scripts.mkdir()
        shutil.copy(ROOT / 'scripts/install-rio.sh', scripts)
        # Without this seam the installer would replace the real /Applications/Rio.app.
        if 'RIO_INSTALL_TARGET' not in (scripts / 'install-rio.sh').read_text():
            self.fail('install-rio.sh no longer reads RIO_INSTALL_TARGET; refusing to run against /Applications')
        self.stub(scripts / 'verify-keychain-access.sh', 'exit "$KEYCHAIN_STATUS"')
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        self.stub(self.bin / 'ditto', 'cp -R "${@: -2:1}" "${@: -1}"')
        self.stub(self.bin / 'pkill', 'exit 1')
        self.stub(self.bin / 'open', 'echo launched >> "$TRACE"; exit "$OPEN_STATUS"')
        self.source = self.app(self.directory / 'build/Rio.app', 'new')
        self.applications = self.directory / 'Applications'
        self.applications.mkdir()
        self.target = self.applications / 'Rio.app'

    def stub(self, path, body):
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)

    def app(self, path, version):
        (path / 'Contents/MacOS').mkdir(parents=True)
        self.stub(path / 'Contents/MacOS/Rio', f'# {version}')
        return path

    def version(self):
        return (self.target / 'Contents/MacOS/Rio').read_text().split('# ')[1].strip()

    def install(self, source=None, keychain=0, launch=0):
        trace = self.directory / 'trace'
        environment = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', TRACE=str(trace),
                           KEYCHAIN_STATUS=str(keychain), OPEN_STATUS=str(launch),
                           RIO_INSTALL_TARGET=str(self.target))
        result = subprocess.run(['/bin/bash', str(self.directory / 'scripts/install-rio.sh'),
                                 str(source or self.source)], env=environment, capture_output=True, text=True)
        self.assertEqual(sorted(p.name for p in self.applications.iterdir()),
                         ['Rio.app'] if self.target.exists() else [], 'staging directory left behind')
        return result, trace.exists()

    def test_fresh_install_launches_the_new_app(self):
        result, launched = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.version(), 'new')
        self.assertTrue(launched)

    def test_upgrade_replaces_the_previous_app(self):
        self.app(self.target, 'old')
        result, _ = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.version(), 'new')

    def test_failed_launch_restores_the_previous_app(self):
        self.app(self.target, 'old')
        result, _ = self.install(launch=1)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.version(), 'old')
        self.assertIn('restored the previous installation', result.stderr)

    def test_failed_launch_of_a_fresh_install_removes_it(self):
        result, _ = self.install(launch=1)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.target.exists())

    def test_failed_keychain_check_leaves_the_installed_app_untouched(self):
        self.app(self.target, 'old')
        result, launched = self.install(keychain=1)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.version(), 'old')
        self.assertFalse(launched)
        self.assertIn('Keychain', result.stderr)

    def test_installing_the_installed_app_onto_itself_is_refused(self):
        self.app(self.target, 'old')
        result, launched = self.install(source=self.target)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.version(), 'old')
        self.assertFalse(launched)

    def test_missing_source_is_refused(self):
        result, launched = self.install(source=self.directory / 'missing.app')
        self.assertEqual(result.returncode, 1)
        self.assertIn('not found', result.stderr)
        self.assertFalse(launched)
