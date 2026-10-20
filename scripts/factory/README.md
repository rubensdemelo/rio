| Script | Rio behavior |
| --- | --- |
| `bootstrap.sh` | Check Git/Python and native toolchain on Mac; explain Linux limits |
| `format.sh [files...]` | No-op: no formatter configured; does not fail for deleted paths |
| `test.sh [RioTests/Class[/method]]` | Tooling tests plus selected unsigned Debug tests; all without selector |
| `gate.sh` | All tooling/Debug tests and unsigned Release build; never installs |
| `smoke.sh [signed-app]` | Installed app by default; signature/entitlements and synthetic Keychain check |
| `rollback.sh /absolute/saved-release/Rio.app` | Explicit saved signed bundle through verified installer; local Mac only |

Native tests fail clearly outside macOS rather than report a partial gate as
passed. Run only the tooling tests on Linux with
`python3 -m unittest discover -s scripts/tests -p 'test_*.py'`.
Signing and interactive installation remain in the existing Makefile.
Instruction/tooling-only changes use that Python suite on any supported host;
`test.sh` accepts XCTest selectors rather than affected file paths. The suite
also checks retained instruction dependencies. To run just that check, use
`python3 scripts/check-agent-instructions.py`.
See `docs/DEVELOPMENT.md` and `docs/DISTRIBUTION.md` for acceptance boundaries.
