---
name: install
description: Install and launch the current Rio macOS app after a development change or release build.
---

# Install Rio

Use this skill when the user asks to install, refresh, or launch the current Rio
build. Rio is still under development, so installation is expected after every
completed change and release.

## Workflow

1. Use the existing validated app when one is available at
   `.build/Iteration/Build/Products/Debug/Rio.app`. If it is missing or stale,
   run `make final` first; do not install an unbuilt source tree.
2. Run `scripts/install-rio.sh <source-app>` to stop Rio, replace
   `/Applications/Rio.app`, launch the installed copy, and confirm its
   executable exists. The target is the known Rio app bundle only; do not
   modify other applications.

For a specific release or archive build, use its explicit `.app` path as the
source instead of silently choosing another artifact. Preserve the release
artifact's signing; do not re-sign or alter the bundle during installation.

The default `make final` build is ad-hoc and intentionally omits signing-only
entitlements. A signed local build can be installed by running
`LOCAL_SIGNED=YES make final` before this skill when Keychain and privacy-grant
continuity need to be exercised.
