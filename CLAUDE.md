# Cartograph

A native macOS app (SwiftUI + Metal) that generates procedural fantasy world maps rendered in historical cartographic styles. Writers, game designers, and worldbuilders use it to produce maps that look hand-drawn by a historical cartographer — not computer-generated. Targets the Age of Exploration portolan chart style. Offline-only, no accounts, no network.

## Tech Stack
- **Swift**: Swift 5 language mode (Xcode 26.3+) — `@Observable` macro, no legacy `ObservableObject`
- **SwiftUI**: macOS 14+ — declarative UI, MTKView bridge plus AppKit save/open panels
- **Metal**: Metal 3 (macOS 14+) — 7-pass GPU render pipeline for portolan style
- **MetalKit**: macOS 14+ — `MTKView` + `MTKViewDelegate` as the Metal/SwiftUI bridge
- **Accelerate**: linked framework; CPU noise and climate use Swift + simd, with no vDSP calls
- **Core Text**: label rendering and font layout
- No external Swift packages — all algorithms in-house

## Status
Phase 4 complete — all planned functionality shipped:
- Phase 0: Xcode scaffold, Metal pipeline, core types
- Phase 1+2: Tectonic simulation, hydraulic erosion, river networks, climate pipeline
- Phase 3: Portolan chart renderer — 7-pass Metal pipeline (merged via PR #1)
- Phase 4: Settlement placement, save/load, manual override UI

## Build & Run
Use the project-local runner for the normal Codex loop, or open
the generated `Cartograph.xcodeproj` in Xcode 26.3+ when you need the IDE.
XcodeGen is required; run `xcodegen generate` before opening the project.

```bash
./script/build_and_run.sh --verify
```

```bash
# Command line build
xcodegen generate
xcodebuild -project Cartograph.xcodeproj -scheme Cartograph -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Requires macOS 14 Sonoma or later, Xcode, and XcodeGen. No external Swift packages to install.

## Architecture
- `Cartograph/` — SwiftUI app target: views, view models, `@Observable` state
- `Cartograph/Shaders/` — Metal shaders (`.metal`) and `ShaderTypes.h` (shared Swift/Metal structs)
- `ShaderTypes.h` is the single source of truth for all Metal/Swift shared structs — never duplicated in Swift
- Map positions use normalized UV space (0.0–1.0); pipeline algorithms also use grid indices, and render geometry uses clip/local coordinates
- Terrain generation runs in background `Task.detached` blocks; state/progress updates use `MainActor.run`
- Document format: `.cartograph` directory bundle — macOS-native, diff-friendly, no database required
- Bundled OFL fonts: IM Fell English + Cinzel Decorative (Resources/Fonts, registered by LabelPass; Georgia fallbacks)

## Known Issues
- GPU Frame Capture validation should be run after any Metal shader changes
- Export renders all seven passes offscreen at 4096×4096 using 1024×1024 terrain data — quality artifacts possible at high zoom

<!-- portfolio-context:start -->
# Portfolio Context

## What This Project Is

Cartograph is an active local project in the ~/Projects portfolio.

## Current State

Phase 4 complete — all planned functionality shipped:
- Phase 0: Xcode scaffold, Metal pipeline, core types
- Phase 1+2: Tectonic simulation, hydraulic erosion, river networks, climate pipeline
- Phase 3: Portolan chart renderer — 7-pass Metal pipeline (merged via PR #1)
- Phase 4: Settlement placement, save/load, manual override UI

## Stack

- **Swift**: Swift 5 language mode (Xcode 26.3+) — `@Observable` macro, no legacy `ObservableObject`
- **SwiftUI**: macOS 14+ — declarative UI, MTKView bridge plus AppKit save/open panels
- **Metal**: Metal 3 (macOS 14+) — 7-pass GPU render pipeline for portolan style
- **MetalKit**: macOS 14+ — `MTKView` + `MTKViewDelegate` as the Metal/SwiftUI bridge
- **Accelerate**: linked framework; CPU noise and climate use Swift + simd, with no vDSP calls
- **Core Text**: label rendering and font layout
- No external Swift packages — all algorithms in-house

## How To Run

Use the project-local runner for the normal Codex loop, or open
the generated `Cartograph.xcodeproj` in Xcode 26.3+ when you need the IDE.
XcodeGen is required; run `xcodegen generate` before opening the project.

```bash
./script/build_and_run.sh --verify
```

```bash
# Command line build
xcodegen generate
xcodebuild -project Cartograph.xcodeproj -scheme Cartograph -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Requires macOS 14 Sonoma or later, Xcode, and XcodeGen. No external Swift packages to install.

## Known Risks

- GPU Frame Capture validation should be run after any Metal shader changes
- Export renders all seven passes offscreen at 4096×4096 using 1024×1024 terrain data — quality artifacts possible at high zoom

## Next Recommended Move

Use this context plus the README and supporting docs to resume the next active task, then promote the repo beyond minimum-viable by capturing a dedicated handoff, roadmap, or discovery artifact.

<!-- portfolio-context:end -->

<!-- secondbrain-breadcrumb -->
## SecondBrain knowledge vault

Prior lessons, decisions, and context for this project live in SecondBrain at `wiki/maps/projects/cartograph.md`. The whole vault is searchable via the `engraph` MCP — query it for this project + its stack before non-trivial work.
