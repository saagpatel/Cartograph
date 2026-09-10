# Cartograph Developer ID Preflight

Date: 2026-06-20

Status: preflight packet created; release not yet executed. Local build/test
preflight is blocked until full Xcode 26.3+ is active.

## Release lane

- Lane: Apple Developer ID macOS app
- Default visibility: public
- Artifact target: Developer ID signed macOS app, packaged as a notarized and
  stapled distribution artifact
- Portfolio status rule: do not mark shipped until receipt and smoke proof exist

## Current release facts

- Source branch at intake: `main`
- Remote tracking at intake: `main...origin/main`
- Bundle identifier: `com.cartograph.app`
- Team ID: `3TGZFKFNA4`
- Deployment target: macOS 14.0
- Hardened runtime: enabled
- Sandbox entitlement: enabled
- User-selected read/write entitlement: enabled
- Privacy manifest: present
- Export option: `Config/ExportOptions/DeveloperID.plist`

## Verification performed

- `git status --short --branch`: `main...origin/main` with only this new
  release packet untracked during implementation.
- `plutil -lint` passed for:
  - `Config/ExportOptions/DeveloperID.plist`
  - `Config/ExportOptions/AppStoreConnect.plist`
  - `Cartograph/App/Info.plist`
  - `Cartograph/Resources/PrivacyInfo.xcprivacy`
- Basic PII/secret pattern scan across release-facing docs/config/source did
  not surface secrets or PII. The only `/Users/d` hit was portfolio context in
  `CLAUDE.md`.
- GitHub Dependabot alerts: no open alerts found.
- GitHub code-scanning alerts: no open alerts found.

## Current blocker

`xcodebuild` cannot run in the current environment because `xcode-select -p`
returns `/Library/Developer/CommandLineTools`, and no full Xcode app was visible
under `/Applications`. Do not attempt archive, Developer ID export, notarization,
or Gatekeeper verification until full Xcode 26.3+ is installed or selected for
the session with `DEVELOPER_DIR`.

## Release-blocking gates

- Clean release source ref
- No release-blocking GitHub security findings
- `make verify` passes
- `make test` passes
- `make export-developer-id` passes
- Code signature verification passes
- Notarization succeeds
- Stapling succeeds
- Gatekeeper assessment passes
- Fresh launch smoke passes
- Artifact checksum recorded
- Receipt completed
- Portfolio update recorded

## Preflight commands

```bash
git status --short --branch
plutil -lint Config/ExportOptions/DeveloperID.plist Config/ExportOptions/AppStoreConnect.plist Cartograph/App/Info.plist Cartograph/Resources/PrivacyInfo.xcprivacy
make verify
make test
make export-developer-id
codesign --verify --deep --strict --verbose=2 .derivedData/exports/developer-id/Cartograph.app
```

After final artifact packaging is selected:

```bash
xcrun notarytool submit <artifact> --wait
xcrun stapler staple <artifact>
spctl --assess --type execute --verbose=4 <app-or-mounted-app>
shasum -a 256 <artifact>
```

## Receipt draft

```yaml
repo: Cartograph
visibility: public
lane: Apple Developer ID macOS
version:
tag:
source_ref:
artifact_urls:
checksums:
signing_status:
notarization_status:
registry_status: not_applicable
security_status:
verification_commands:
verification_results:
install_smoke:
rollback_plan:
portfolio_update_ref:
known_residual_risks:
waivers_with_expiry:
operator:
shipped_at:
```

## Acceptance

This packet is complete only when the receipt fields above are filled with
actual release evidence and the portfolio update points at that verified
release state.
