#!/usr/bin/env python3
"""Classify the complete push range; uncertainty requires verification."""
import os
import subprocess

NOOP_FILES = {'.factory-version', 'AGENTS.md', 'CLAUDE.md', 'REVIEW.md', 'REVIEW.local.md'}
NOOP_PREFIXES = ('.claude/', '.agents/', 'docs/')


def needs_verification(paths):
    return any(path not in NOOP_FILES and not path.startswith(NOOP_PREFIXES) for path in paths)


def plan(event, before, after, run=subprocess.check_output):
    if event != 'push' or not before or set(before) == {'0'}:
        return True
    try:
        changed = run(['git', 'diff', '--name-only', '--no-renames', '-z', before, after])
    except subprocess.CalledProcessError:
        return True
    return needs_verification(changed.decode('utf-8', errors='surrogateescape').strip('\0').split('\0')) if changed else False


if __name__ == '__main__':
    result = str(plan(os.environ.get('EVENT_NAME'), os.environ.get('BEFORE_SHA'), os.environ.get('AFTER_SHA', 'HEAD'))).lower()
    line = f'deploy={result}'
    print(line)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(line + '\n')
