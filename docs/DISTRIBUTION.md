# Rio GitHub distribution

Rio is distributed as a notarized Developer ID DMG through GitHub Releases.
This document describes the one-time maintainer setup and the release
workflow; end users only need the DMG from the
[latest release](https://github.com/rubensdemelo/rio/releases/latest).

## One-time setup

The repository needs these GitHub Actions credentials:

- Developer ID certificate P12 and its password
- Developer ID provisioning profile
- App Store Connect notarization API key, key ID, and issuer ID
- Apple Team ID repository variable

After installing and authenticating the GitHub CLI, run these commands from the
repository root. The three credential files are base64-encoded while piping directly
to `gh`, so their contents are not written into the repository or shell history:

```sh
base64 < /path/to/developer-id.p12 | tr -d '\n' | gh secret set APPLE_DEVELOPER_ID_CERTIFICATE_BASE64
gh secret set APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
base64 < /path/to/rio.provisionprofile | tr -d '\n' | gh secret set APPLE_PROVISIONING_PROFILE_BASE64
gh secret set APPLE_NOTARY_KEY_ID
gh secret set APPLE_NOTARY_ISSUER_ID
base64 < /path/to/AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | gh secret set APPLE_NOTARY_PRIVATE_KEY_BASE64
gh variable set APPLE_TEAM_ID
```

`gh secret set` and `gh variable set` prompt for each value. Keep the `.p12`,
provisioning profile, and `.p8` files outside the repository; remove temporary
local copies after setup.

## Continuous integration

Pushes to `main` and pull requests targeting `main` run
[`ci.yml`](../.github/workflows/ci.yml). It tests Rio and builds the Release
configuration without Apple signing credentials, notarization, or DMG creation.
The workflow has read-only repository permissions.

## Publish a release

Push a semantic-version tag from `main` or publish a GitHub Release for that
tag. Either action runs the release workflow:

```sh
git tag v1.2.3
git push origin v1.2.3
```

For a new tag, Actions runs the same CI checks on the tagged commit, then signs,
notarizes, and creates a GitHub Release with the DMG. Publishing a release for an
existing tag also runs the workflow and attaches a DMG to that release. If the
release already has its versioned DMG, the workflow skips CI and the build. Tag
updates are ignored.

The release job uses a full checkout and rejects a tag whose commit is not an
ancestor of `origin/main`. A semantic version alone is not release provenance.

The workflow in [`.github/workflows/release.yml`](../.github/workflows/release.yml)
then:

1. Builds the arm64-only Release app for Apple Silicon.
2. Signs it with Developer ID Application and Hardened Runtime.
3. Packages and Developer ID-signs a drag-installable DMG.
4. Submits the DMG to Apple for notarization.
5. Staples the notarization ticket, then verifies the exact DMG and its mounted
   app payload.
6. Publishes that verified DMG as a GitHub Release asset and records its final
   SHA-256 checksum in the workflow output.

The OpenAI API key is never part of the repository, workflow, app bundle, or
DMG. Each Mac adds its own key through Rio’s Provider settings.

## Release checks

The packaging and verification helpers are:

- [`scripts/package-dmg.sh`](../scripts/package-dmg.sh)
- [`scripts/verify-release.sh`](../scripts/verify-release.sh)
- [`scripts/verify-keychain-access.sh`](../scripts/verify-keychain-access.sh)

`verify-release.sh` first checks the outer image's Developer ID signature,
stapled ticket, and Gatekeeper disk-image assessment. It then mounts the image
read-only, always detaches it on exit, and requires exactly `Rio.app` plus an
`Applications` symlink. The mounted app must have the expected Developer ID
team, Hardened Runtime, production entitlements, the `arm64` architecture,
release version/build, macOS 26.0 minimum, and a successful Gatekeeper
assessment.

Before publishing a GA candidate, retain content-free evidence for the exact
release commit and final SHA-256 shown by the workflow. Also install that same
downloaded artifact on a supported clean Mac with quarantine metadata intact
and record the Gatekeeper launch result. CI verification is necessary but does
not replace that clean-machine check, the live hardware soak, or the model
quality gates in the GA release plan.
