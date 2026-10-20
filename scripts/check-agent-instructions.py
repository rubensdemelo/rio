#!/usr/bin/env python3
"""Check vendored skills' explicit local dependencies, not arbitrary prose.

Grammar: backticked `/name [arguments]` after run/use/invoke, or followed
by skill/session; backticked `name` followed
by 'skill', and Markdown inline links relative to their containing document.
Fenced examples, inline-code examples containing links, URL/anchor links and
placeholder paths are excluded. External/global skills must be described as
such instead of using the local invocation grammar. This is not a Markdown
parser or a validator of future output paths mentioned in prose.
"""
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

def prose_lines(text):
    """Keep line numbers, ignoring fenced examples (backticks or tildes)."""
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        marker = re.match(r'^\s*(`{3,}|~{3,})', line)
        if marker:
            run = marker.group(1)
            if fence is None:
                fence = run
            elif run[0] == fence[0] and len(run) >= len(fence):
                fence = None
            continue
        if fence is None:
            yield number, line


def check(root):
    root = Path(root)
    skills = root / '.agents/skills'
    errors = []
    for document in sorted(skills.rglob('*.md')):
        for number, line in prose_lines(document.read_text()):
            location = f'{document.relative_to(root)}:{number}'
            invocation = r'`/([a-z][a-z0-9-]*)(?:\s+[^`]*)?`'
            names = set(re.findall(r'\b(?:run|use|invoke)\s+(?:(?:the|a|stateful)\s+)*' + invocation, line, re.I))
            names.update(re.findall(invocation + r'\s+(?:skill|session)\b', line))
            names.update(re.findall(r'`([a-z][a-z0-9-]*)`\s+skill\b', line))
            for name in sorted(names):
                if not (skills / name / 'SKILL.md').is_file():
                    errors.append(f'{location}: missing local skill {name}; restore it or update the reference')
            # Inline code may contain a complete illustrative Markdown link.
            plain = re.sub(r'`[^`]*`', '', line)
            for target in re.findall(r'\]\(([^\s)]+)(?:\s+"[^"]*")?\)', plain):
                if any(character in target for character in '<>{}*'):
                    continue
                url = urlsplit(target)
                if url.scheme or url.netloc or not url.path:
                    continue
                path = unquote(url.path)
                if path.startswith(('~', '/')):
                    continue
                if not (document.parent / path).exists():
                    errors.append(f'{location}: missing local resource {path}; restore it or update the link')
    if (root / 'skills-lock.json').exists():
        errors.append('skills-lock.json: obsolete installer metadata can restore removed or replace factory skills; remove it')
    return errors


if __name__ == '__main__':
    if len(sys.argv) > 2:
        sys.exit('Usage: python3 scripts/check-agent-instructions.py [repository]')
    problems = check(Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1])
    print('\n'.join(problems) if problems else 'Agent instruction dependencies passed.')
    sys.exit(bool(problems))
