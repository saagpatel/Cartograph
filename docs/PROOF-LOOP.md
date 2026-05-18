# Cartograph — Proof Loop

A one-pass walkthrough that proves the procedural map pipeline works
end-to-end: from a clean checkout to a rendered portolan-style fantasy map on
screen. Each stage of the pipeline has a verification gate so a regression
in any single stage is detectable.

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
cd /Users/d/Projects/Cartograph
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
  build
```

**Expected:** `BUILD SUCCEEDED`. Metal shader compilation reports zero errors.

**If it fails:**
- `DEVELOPMENT_TEAM` mismatch — fix in `project.yml` per commit `9de3cfd`.
- Shader compile errors usually mean a struct in `Cartograph-Bridging-Header.h`
  drifted from its Metal counterpart in `Shaders/`. See
  `ShaderTypesLayoutTests` for the layout contract.

---

## 3. Run the unit-test suite — pipeline stage gates

Each test file gates one stage of the generation pipeline.

```bash
xcodebuild \
  -project Cartograph.xcodeproj \
  -scheme Cartograph \
  -destination 'platform=macOS' \
  test
```

**Expected coverage map (stage → test file):**

| Pipeline stage | Test file | What it proves |
|---|---|---|
| Noise primitive | `NoiseGeneratorTests` | Perlin/simplex producers deterministic, in range |
| Tectonic plate sim | `TectonicSimulatorTests` | Plate motion + boundary types produce expected heightmap features |
| Heightmap shape | `HeightMapTests` | 1024×1024 Float32 grid, no NaN, valid range |
| Erosion (Metal) | (covered indirectly) | Eroded heightmap doesn't NaN; SettlementPlacer downstream works |
| River network | `RiverNetworkTests` | Flow accumulation builds a valid `RiverGraph`, no cycles |
| Climate / biomes | `ClimateModelTests` | BiomeMap enum coverage; latitude bands behave |
| Settlement placement | `SettlementPlacerTests` | Settlements respect water/elevation/biome constraints |
| Coastline geometry | `MarchingSquaresTests` | MS contour for the coastline produces closed loops at known thresholds |
| Stroke geometry | `StrokeGeometryTests` | Variable-width wobbly stroke math (used by CoastlinePass, RiverPass) |
| Doc serialization | `CartographDocumentTests` | Round-trip save/load of the full TerrainEngine state |
| Shader struct ABI | `ShaderTypesLayoutTests` | Swift ↔ Metal struct layouts match |

**If a single test fails:** that stage is the regression. Treat downstream
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

- **Coastline only:** disable other passes in the renderer's pass list, leave
  `ParchmentPass` + `CoastlinePass` enabled. Visual output should show only
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
#   - Texture cache hits for ParchmentPass (cached after first render)
```

Document any pass over 10ms as a regression candidate.

---

## 8. Privacy + signing posture (App Store ready check)

```bash
# Privacy manifest present (commit 8f382cb)
ls Cartograph/PrivacyInfo.xcprivacy

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

If any visual element in step 5 is missing, the corresponding test file in
step 3 should also have a failure — start the bisect there.

---

## When to re-run the loop

- After any change to a Pipeline stage (`Pipeline/` or `Shaders/`)
- Before opening an App Store submission PR
- After regenerating `project.yml` or upgrading Xcode
- Whenever a visual regression is suspected — the stage gates pinpoint the
  source
