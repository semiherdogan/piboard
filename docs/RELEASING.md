# Releasing PiBoard

Releases are built by `.github/workflows/release.yml` in [`semiherdogan/piboard`](https://github.com/semiherdogan/piboard). It runs `scripts/release.sh`, creates the GitHub Release `v<version>` with `PiBoard-<version>.zip`, and publishes the Sparkle feed to the `gh-pages` branch.

GitHub Pages is enabled for `gh-pages`, so the feed is live at `https://semiherdogan.github.io/piboard/appcast.xml` (the `SUFeedURL` in `project.yml`).

Releases are arm64 only (`ARCHS: arm64` in `project.yml`) to match the bundled Node runtime; `scripts/fetch-node.sh` already detects x86_64, but supporting Intel would need a separate universal packaging step.

Runner requirements: Xcode 27 plus the Metal Toolchain component, because SwiftTerm ships a Metal shader. The workflow installs it with `xcodebuild -downloadComponent MetalToolchain` (about 840 MB) and skips the download when `xcrun -f metal` already resolves.

## One-time setup

1. Create the GitHub repo `semiherdogan/piboard` and push `main`.
2. Generate the Sparkle EdDSA key pair locally (after `make build`, so the Sparkle artifact exists):

   ```sh
   build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   The private key is stored in your login Keychain; the command prints the public key.
3. Replace `REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY` in `project.yml` (`SUPublicEDKey`) with that public key and commit it. Until then the app shows "Updates are not configured in this build" and `release.sh` refuses to publish an appcast.
4. Export the private key and store it as the repository secret `SPARKLE_PRIVATE_KEY`:

   ```sh
   build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key.txt
   ```

   Paste the file contents into the secret, then delete the file. Back up the key: losing it means existing installs can never verify another update.
5. Run the workflow once (step "Cutting a release"). It creates the `gh-pages` branch.
6. In repo Settings > Pages, set the source to "Deploy from a branch", branch `gh-pages`, folder `/ (root)`.

### Optional: Developer ID signing and notarization

Requires a paid Apple Developer account. When `DEVELOPER_ID_CERT_P12_BASE64` is set, the workflow signs with Developer ID; notarization and stapling run when the three API key secrets are also set.

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12_BASE64` | `base64 -i DeveloperID.p12` of the exported "Developer ID Application" certificate and key |
| `DEVELOPER_ID_CERT_PASSWORD` | Password of that `.p12` |
| `APPLE_TEAM_ID` | Your 10 character Team ID |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID |
| `APPLE_API_KEY_P8` | Contents of the `AuthKey_<id>.p8` file |

## Cutting a release

1. Actions > Release > Run workflow.
2. Fill in `version` (for example `0.2.0`), `channel` (`beta` marks the GitHub Release as a prerelease and the appcast item as Sparkle channel `beta`), `ref`, and optional `notes` (Markdown, embedded in the appcast).
3. Failed tests, signing or notarization stop the job before the release and appcast are published.

`CFBundleVersion` is `BUILD_NUMBER_BASE` (100) plus the workflow run number, so it always increases.

### Example: the first betas

The flow above produced three betas on 2026-10-06, all with `channel` `beta`:

| Version | Build | GitHub Release |
| --- | --- | --- |
| 0.1.0 | 102 | `v0.1.0`, prerelease |
| 0.1.1 | 103 | `v0.1.1`, prerelease |
| 0.1.2 | 104 | `v0.1.2`, prerelease |

Each run appended an item to the same `appcast.xml`, so an older install with the Beta channel selected is offered the newest beta through Sparkle. A Stable install ignores all three.

## Feed layout

Both channels share one feed, `appcast.xml`. Moving the feed to Cloudflare Pages or R2 is a possible future alternative to GitHub Pages; only `SUFeedURL` and the publish step would change. Beta items carry `<sparkle:channel>beta</sparkle:channel>`. Sparkle ignores them unless the app's channel picker is set to Beta. `release.sh` downloads the published feed first, and `generate_appcast` keeps its existing items, so no `releases/` folder is needed on `gh-pages`. Sparkle keeps the newest 3 items per branch by default.

## Free Apple account: what users see

Without Developer ID the app is ad-hoc signed and not notarized:

- First launch: Gatekeeper blocks it. On macOS 15 and later, right-click > Open no longer bypasses this; users open the app once, then click Open Anyway in System Settings > Privacy & Security and confirm. This is needed once per install.
- Updates still work: Sparkle verifies every download against the EdDSA public key embedded in the app, independent of Apple signing.

## Local dry run

```sh
make release-dry-run
```

This builds an ad-hoc signed `0.0.0` (build 1) beta into `build/release/PiBoard-0.0.0.zip`. Tests run first. With `SPARKLE_PRIVATE_KEY` unset, the appcast step is skipped and the run still succeeds. Run `scripts/release.sh --help` for all options.
