---
name: install
description: Install and launch the current signed Rio macOS app when the owner requests installation, refresh, or launch.
---

# Install Rio

Use this skill when the user asks to install, refresh, or launch the current Rio
build. A completed change or release alone does not request installation. The
primary agent owns interactive app and hardware validation. Read
`docs/DEVELOPMENT.md` and `docs/DISTRIBUTION.md` before running this flow.

## Workflow

1. For the latest source, run `make install` to build the signed arm64 Debug
   app, verify its signature and synthetic Keychain round-trip, and
   transactionally replace and launch `/Applications/Rio.app`. Use `make final`
   to run the test suite before that same install flow.
2. For a specific archive or release app, run
   `scripts/install-rio.sh <source-app>`. It stages and verifies the app before
   stopping Rio or replacing the installed copy. If verification fails, the
   existing installation remains intact. Preserve the artifact's signing; do
   not re-sign or alter the bundle during installation.

The opt-in `LOCAL_SIGNED=NO make final` mode uses a separate build directory,
runs tests and builds an ad-hoc app without stopping, installing, or launching
Rio. It is only for validation on machines without a development signing
identity; never install or interactively launch that artifact. `make install`
requires the signed Debug build.
