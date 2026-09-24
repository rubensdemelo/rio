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
   run `make final` first; the default gate signs it, verifies Keychain access,
   and launches it. Do not install an unbuilt source tree or an unsigned
   validation build.
2. Run `scripts/install-rio.sh <source-app>` to stage the app, verify its code
   signature, and perform the synthetic Keychain round-trip before stopping Rio
   or replacing `/Applications/Rio.app`. If either check fails, leave the
   existing installation running and intact. On success, launch the installed
   copy and confirm its executable exists. The target is the known Rio app
   bundle only; do not modify other applications.

For a specific release or archive build, use its explicit `.app` path as the
source instead of silently choosing another artifact. Preserve the release
artifact's signing; do not re-sign or alter the bundle during installation.

The opt-in `LOCAL_SIGNED=NO make final` mode uses a separate build directory,
does not stop or launch Rio, and skips Keychain verification. It is only for
validation on machines without a development signing identity; never install
or interactively launch that ad-hoc artifact.
