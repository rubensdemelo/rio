"""Validate instruction dependencies with synthetic fixtures and the real tree."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('agent_instructions', ROOT / 'scripts/check-agent-instructions.py')
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class AdoptionContractTests(unittest.TestCase):
    def fixture(self, text, resources=()):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        skill = root / '.agents/skills/example'
        skill.mkdir(parents=True)
        (skill / 'SKILL.md').write_text(text)
        for name in resources:
            resource = skill / name
            resource.parent.mkdir(parents=True, exist_ok=True)
            resource.write_text('fixture')
        return root

    def test_missing_named_and_slash_skills_are_reported(self):
        root = self.fixture('See the `code-review` skill. Then run `/build --quick`.')
        errors = CHECKER.check(root)
        self.assertEqual(len(errors), 2, errors)
        self.assertTrue(any('missing local skill code-review' in error for error in errors))
        self.assertTrue(any('missing local skill build' in error for error in errors))

    def test_missing_resource_in_supporting_markdown_is_reported(self):
        root = self.fixture('[Guide](guide.md)', ('guide.md',))
        (root / '.agents/skills/example/guide.md').write_text('[helper](helpers/missing.sh)')
        errors = CHECKER.check(root)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn('guide.md:1: missing local resource helpers/missing.sh', errors[0])

    def test_existing_dependencies_and_examples_are_allowed(self):
        root = self.fixture('''Use the `example` skill and `/example --flag`.
[Guide](guide.md#section) and [helper](helpers/run.sh).
[External](https://example.com/missing) [anchor](#missing)
[Template](docs/<slug>.md) [glob](docs/*.md)
Example: `[future](future.md)`.
Write temporary files in `/tmp`; show the `/settings` route.
```markdown
Use `/absent` and [missing](missing.md).
```
~~~markdown
See the `absent` skill.
~~~
''', ('guide.md', 'helpers/run.sh'))
        self.assertEqual(CHECKER.check(root), [])

    def test_obsolete_installer_lock_is_rejected(self):
        root = self.fixture('Use `/example`.')
        (root / 'skills-lock.json').write_text('{"skills":{"code-review":{},"research":{}}}')
        self.assertEqual(len(CHECKER.check(root)), 1)
        self.assertIn('obsolete installer metadata', CHECKER.check(root)[0])

    def test_repository_dependencies(self):
        self.assertEqual(CHECKER.check(ROOT), [])
