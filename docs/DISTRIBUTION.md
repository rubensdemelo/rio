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

Run the interactive setup wizard after installing and authenticating the GitHub
CLI:

```sh
scripts/setup-github-release.sh
```

The wizard stores credentials as masked GitHub Actions secrets and the Team ID
as a repository variable. It writes only non-secret file paths and identifiers
to the ignored local `.env` file so a later run can reuse them; it never writes
the certificate password or credential file contents there. Keep exported
`.p12` and `.p8` files outside the repository and remove temporary local copies
after setup. A run is reported complete only when every required GitHub value
was written.

## Publish a release

Push a semantic-version tag from `main`:

```sh
git tag v1.2.3
git push origin v1.2.3
```

The release workflow runs only when that semantic-version tag is newly created.
Moving or force-updating an existing tag does not generate another DMG.

The release job uses a full checkout and rejects a tag whose commit is not an
ancestor of `origin/main`. A semantic version alone is not release provenance.

The workflow in [`.github/workflows/release.yml`](../.github/workflows/release.yml)
then:

1. Builds the universal Release app.
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
team, Hardened Runtime, production entitlements, `arm64` and `x86_64` slices,
release version/build, macOS 26.0 minimum, and a successful Gatekeeper
assessment.

Before publishing a GA candidate, retain content-free evidence for the exact
release commit and final SHA-256 shown by the workflow. Also install that same
downloaded artifact on a supported clean Mac with quarantine metadata intact
and record the Gatekeeper launch result. CI verification is necessary but does
not replace that clean-machine check, the live hardware soak, or the model
quality gates in the GA release plan.
