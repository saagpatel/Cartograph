# Cartograph — Proof Loop

A walkthrough for checking the procedural map pipeline, from a clean checkout
to a rendered portolan-style fantasy map on screen. Automated component checks
and manual visual inspection provide different evidence; neither guarantees
that every regression will be detected.

> **Audience:** anyone resuming work, demoing the renderer, or capturing a
> baseline before changes.

---

## 0. Prerequisites

- macOS with Metal-capable GPU (any Apple Silicon Mac)
- Xcode 26.3+ (matches `project.yml`)
- XcodeGen (`brew install xcodegen`)

```bash
xcodebuild -version
xcodegen --version
system_profiler SPDisplaysDataType | grep "Metal Family"
```

---

## 1. Regenerate Xcode project from `project.yml`

```bash
# Run from the repository root
xcodegen generate
```

**Expected:** `Cartograph.xcodeproj` rebuilt clean. No warnings.

**If it fails:** `xcodegen --quiet generate` for clean errors. Usually a new
shader or Swift file not declared.

---

## 2. Build for macOS

```bash
xcodebuild \
  -project Cartograph.xcodeproj \
  -scheme Cartograph \
  -configuration Debug \
  -destination 'platform=macOS' \
  build CODE_SIGNING_ALLOWED=NO
```

**Expected:** `BUILD SUCCEEDED`. Metal shader compilation reports zero errors.

**If it fails:**
- These unsigned commands do not need a signing team. If a signing error appears,
  confirm that `CODE_SIGNING_ALLOWED=NO` reached xcodebuild; do not change the team
  or provisioning state to run tests.
- For shader struct errors, inspect `Cartograph/Shaders/ShaderTypes.h`, shared
  with Swift via `Cartograph/Cartograph-Bridging-Header.h`. See
  `ShaderTypesLayoutTests` for the layout contract.

---

## 3. Run the unit-test suite — pipeline stage gates

Component tests cover the stages below; no test invokes the full generation pipeline.

```bash
xcodebuild \
  -project Cartograph.xcodeproj \
  -scheme Cartograph \
  -destination 'platform=macOS' \
  test CODE_SIGNING_ALLOWED=NO
```

**Expected coverage map (stage → test file):**

| Pipeline stage | Test file | What it proves |
|---|---|---|
| Noise primitive | `NoiseGeneratorTests` | Simplex determinism/seed variation and sampled simplex/fBm ranges |
| Tectonic plate sim | `TectonicSimulatorTests` | Determinism, height ranges, mountain-height response, and sea-level propagation |
| Heightmap shape | `HeightMapTests` | 1024×1024 allocation, row-major indexing, UV conversion, default sea level |
| Erosion (Metal) | (not covered) | No test invokes ErosionEngine or the full pipeline |
| River network | `RiverNetworkTests` | RiverNode descent, downstream accumulation, determinism, river count, flow-map range |
| Climate / biomes | `ClimateModelTests` | Selected biome assignments, ocean classification, determinism, moisture range |
| Settlement placement | `SettlementPlacerTests` | On-land placement, spacing, minimum count, and determinism |
| Coastline geometry | `MarchingSquaresTests` | MS contour for the coastline produces closed loops at known thresholds |
| Stroke geometry | `StrokeGeometryTests` | Strip vertex/index counts, width offsets, and empty/single-point inputs |
| Doc serialization | `CartographDocumentTests` | Synthetic bundle save/load, selected metadata/data values, settlements, and missing-path errors |
| Shader struct ABI | `ShaderTypesLayoutTests` | Selected imported C-struct sizes match expected constants; no Metal-side comparison |

**If a single test fails:** investigate that component and its dependencies. Treat downstream
visual output as untrustworthy until the gate passes.

---

## 4. Launch the app and run a deterministic generation

```bash
open Cartograph.xcodeproj
# Hit Cmd-R with scheme = Cartograph
```

In the app:

1. **Seed** the generator with the canonical seed via the SwiftUI
   **Proof Seed → Seed 42** control. This also switches the renderer to
   **Portolan** mode.
2. **Generate** — the pipeline runs: TectonicSimulator → HeightMap →
   ErosionEngine (Metal) → RiverNetwork → ClimateModel → SettlementPlacer.
3. **Wait** for the MapRenderer to complete all portolan passes (Parchment,
   Terrain, Coastline, River, Mountain, Label, Decor).
4. **Verify the visual output** against the expected baseline (see Stage 5).

---

## 5. Visual proof — what "works" looks like

For seed `42` (the canonical proof seed):

| Visual element | Pass | Verification |
|---|---|---|
| Parchment background texture | `ParchmentPass` | Visible, not blank |
| Biome colors visible | `TerrainPass` | At least 3 biomes (e.g., forest/desert/grassland) |
| Coastline ink strokes | `CoastlinePass` | Wobbly variable-width lines around all landmasses |
| River strokes taper | `RiverPass` | Tapered ink from source to mouth; no broken/disconnected segments |
| Mountain profiles | `MountainPass` | Instanced profile glyphs over high-elevation terrain |
| Labels readable | `LabelPass` | CoreText labels over settlements; no overlap |
| Decor — compass rose | `DecorPass` | Compass rose in a corner |
| Decor — border frame | `DecorPass` | Cartouche/frame around the map |

**Capture a screencap** of the deterministic seed-42 render and check it into
`docs/media/proof-seed-42.png` if you want a permanent visual baseline.

---

## 6. Stage isolation — re-render only the changed pass

The portolan pipeline is pass-isolated. To prove a single pass independently:

- **Coastline only:** temporarily omit other encode calls in
  `Cartograph/Rendering/MapRenderer.swift`, keeping preparation intact and
  `ParchmentPass` + `CoastlinePass` encoding enabled. Visual output should show only
  coastline strokes on parchment.
- **River only:** Parchment + River. Should show rivers floating with no land
  context — useful for spotting stroke-geometry regressions.
- **Mountains only:** Parchment + Mountain. Instanced profiles over the
  height field.

Use this when one pass regresses visually but tests pass — the test catches
math, not pixel output.

---

## 7. Performance sanity (optional)

```
# In the app, Xcode > Debug > Capture GPU Frame after generation completes
# Look for:
#   - Each portolan pass < 5ms on M3 Pro
#   - No CPU-side blocking waits between passes
#   - ParchmentPass texture reuse (baked during prepare, reused by encode)
```

Document any pass over 10ms as a regression candidate.

---

## 8. Privacy + signing posture (App Store ready check)

```bash
# Privacy manifest present (commit 8f382cb)
ls Cartograph/Resources/PrivacyInfo.xcprivacy

# DEVELOPMENT_TEAM and real bundle ID set (commit 9de3cfd)
grep -E "DEVELOPMENT_TEAM|bundleIdPrefix" project.yml

# App Store metadata present (commit c414fd4)
ls APPSTORE-METADATA.md
```

---

## Proof-loop source of truth

This loop mirrors the build proof captured at commits:

- `8f382cb` — privacy manifest
- `9de3cfd` — DEVELOPMENT_TEAM + bundle ID
- `c414fd4` — App Store metadata
- Plus the full portolan pass pipeline shipped earlier

If a visual element in step 5 is missing, inspect that render pass and its
component tests. Passing unit tests do not guarantee the rendered visual output.

---

## When to re-run the loop

- After any change to a Pipeline stage (`Cartograph/Pipeline/` or `Cartograph/Shaders/`)
- Before opening an App Store submission PR
- After regenerating `project.yml` or upgrading Xcode
- Whenever a visual regression is suspected — the stage gates pinpoint the
  source

## Codex run loop

Use the project-local runner for repeatable build and launch checks:

```bash
./script/build_and_run.sh --verify
```

For release packaging validation:

```bash
make archive
make export-developer-id
codesign -dv --verbose=4 .derivedData/archives/Cartograph.xcarchive/Products/Applications/Cartograph.app 2>&1 | rg 'flags=|Runtime Version='
spctl -a -vvv --type execute .derivedData/exports/developer-id/Cartograph.app
```

`make archive` proves the Xcode archive path and local signing are healthy.
`make export-developer-id` proves Developer ID export works when the local
Developer ID Application identity is installed. `spctl` is expected to reject
the Developer ID export as `Unnotarized Developer ID` until notarization is
completed.

App Store/TestFlight export uses:

```bash
make export-app-store
```

As of June 6, 2026, this fails before export because no provisioning profile is
available for `com.cartograph.app`. Register the bundle ID and create/download
the App Store provisioning profile, then rerun the target.

## Choosing a verification lane

Run from the repository root with full Xcode selected (Command Line Tools alone
cannot build this macOS app), XcodeGen, and a Metal-capable Mac. The authoritative
provider sequence is [ci.yml](../.github/workflows/ci.yml): generate the project,
run unsigned XCTest, build the unsigned Release app, then inspect bundle
resources and plists. Generated projects and `.derivedData/` are local outputs.

For a focused test, generate first and select an existing XCTest class:

```sh
xcodegen generate
xcodebuild test -project Cartograph.xcodeproj -scheme Cartograph \
  -destination 'platform=macOS' -derivedDataPath .derivedData/focused-tests \
  -only-testing:CartographTests/NoiseGeneratorTests CODE_SIGNING_ALLOWED=NO
```

Use `make test` for the full suite and `make build` for an unsigned Debug build.
CI also validates Release packaging. No separate formatter/linter command is
configured in this repository; do not report a build as a formatting check.
If Xcode or Metal is unavailable, record the native lane as unavailable rather
than substituting a browser check.

Visual checks above matter when rendering/UI behavior changes. The
`build_and_run.sh --verify` helper always stops processes named Cartograph and
launches an app; it checks process presence only. Avoid it on an active session.
Unit tests do not establish visual quality, export fidelity, or human acceptance.
For manual export, choose a disposable output directory. Archive, signing,
provisioning, notarization, and distribution remain separate release work;
unsigned tests/builds need no Apple account or provisioning updates.
