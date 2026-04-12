# Cartograph

A native macOS app (SwiftUI + Metal) that generates procedural fantasy world maps rendered in historical cartographic styles. Writers, game designers, and worldbuilders use it to produce maps that look hand-drawn by a historical cartographer — not computer-generated. Targets the Age of Exploration portolan chart style. Offline-only, no accounts, no network.

## Tech Stack
- **Swift**: 5.10+ (Xcode 15.4+) — `@Observable` macro, no legacy `ObservableObject`
- **SwiftUI**: macOS 14+ — declarative UI, no AppKit views except MTKView bridge
- **Metal**: Metal 3 (macOS 14+) — 7-pass GPU render pipeline for portolan style
- **MetalKit**: macOS 14+ — `MTKView` + `MTKViewDelegate` as the Metal/SwiftUI bridge
- **Accelerate**: vDSP for CPU-side noise and biome smoothing
- **Core Text**: label rendering and font layout
- No external Swift packages — all algorithms in-house

## Status
Phase 4 complete — all planned functionality shipped:
- Phase 0: Xcode scaffold, Metal pipeline, core types
- Phase 1+2: Tectonic simulation, hydraulic erosion, river networks, climate pipeline
- Phase 3: Portolan chart renderer — 7-pass Metal pipeline (merged via PR #1)
- Phase 4: Settlement placement, save/load, manual override UI

## Build & Run
Open `Cartograph.xcodeproj` in Xcode 15.4+ and build for macOS 14+.

```bash
# Command line build
xcodebuild -project Cartograph.xcodeproj -scheme Cartograph -configuration Debug build
```

Requires macOS 14 Sonoma or later. No external dependencies to install.

## Architecture
- `Cartograph/` — SwiftUI app target: views, view models, `@Observable` state
- `Cartograph/Metal/` — Metal shaders (`.metal`) and `ShaderTypes.h` (shared Swift/Metal structs)
- `ShaderTypes.h` is the single source of truth for all Metal/Swift shared structs — never duplicated in Swift
- All coordinate math in normalized UV space (0.0–1.0); converted to pixel space only at render time
- Terrain generation pipeline runs in background `Task {}` blocks — never on the main actor
- Document format: `.cartograph` directory bundle — macOS-native, diff-friendly, no database required
- Bundled OFL fonts: IM Fell English + Cinzel Decorative

## Known Issues
- GPU Frame Capture validation should be run after any Metal shader changes
- Export resolution is 4096×4096 upsampled from 1024×1024 internal — quality artifacts possible at high zoom
