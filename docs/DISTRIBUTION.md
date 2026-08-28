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

The wizard stores credentials as masked GitHub Actions secrets. Keep exported
`.p12` and `.p8` files outside the repository and remove temporary local copies
after setup.

## Publish a release

Push a semantic-version tag from `main`:

```sh
git tag v1.2.3
git push origin v1.2.3
```

The workflow in [`.github/workflows/release.yml`](../.github/workflows/release.yml)
then:

1. Builds the universal Release app.
2. Signs it with Developer ID Application and Hardened Runtime.
3. Packages a drag-installable DMG.
4. Submits the DMG to Apple for notarization.
5. Staples and validates the notarization ticket.
6. Publishes the DMG as a GitHub Release asset and records its SHA-256 checksum
   in the workflow output.

The OpenAI API key is never part of the repository, workflow, app bundle, or
DMG. Each Mac adds its own key through Rio’s Provider settings.

## Release checks

The packaging and verification helpers are:

- [`scripts/package-dmg.sh`](../scripts/package-dmg.sh)
- [`scripts/verify-release.sh`](../scripts/verify-release.sh)
- [`scripts/verify-keychain-access.sh`](../scripts/verify-keychain-access.sh)
