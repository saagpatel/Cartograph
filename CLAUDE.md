# Cartograph

## Overview
Cartograph is a native macOS app (SwiftUI + Metal) that generates procedural fantasy world maps rendered in historical cartographic styles. Writers, game designers, and worldbuilders use it to produce maps that look hand-drawn by a historical cartographer — not computer-generated. v1 targets a single style: Age of Exploration portolan chart. Offline-only, no accounts, no network.

## Tech Stack
- Swift: 5.10+ (Xcode 15.4+) — `@Observable` macro, no legacy `ObservableObject`
- SwiftUI: macOS 14+ — declarative UI only, no AppKit views except MTKView bridge
- Metal: Metal 3 (macOS 14+) — GPU compute for erosion, GPU render pipeline for style
- MetalKit: macOS 14+ — `MTKView` + `MTKViewDelegate` as the Metal/SwiftUI bridge
- Accelerate: stdlib — vDSP for CPU-side noise and biome smoothing
- Core Text: stdlib — label rendering and font layout
- No external Swift packages — all algorithms implemented in-house via SPM

## Development Conventions
- Swift strict concurrency: all pipeline passes run in `Task {}` blocks on background executors; never block the main actor
- `ShaderTypes.h` is the single source of truth for all Metal/Swift shared structs — never duplicate struct definitions in Swift
- All coordinate math in normalized UV space (0.0–1.0); convert to pixel space only at render time
- File naming: PascalCase for Swift types, camelCase for functions, `snake_case` for Metal functions
- Every new pipeline stage must pass GPU Frame Capture validation before moving to the next task
- Unit tests required for all terrain data transforms (height map, river network, biome assignment)

## Current Phase
**Phase 0: Foundation**
See IMPLEMENTATION-ROADMAP.md for full task list, acceptance criteria, and verification checklist.

## Key Decisions
| Decision | Choice | Why |
|----------|--------|-----|
| Platform | macOS 14+ only | Easier dev loop than iPad; larger canvas |
| Height map resolution | 1024×1024 internal, 4096×4096 export | Fast iteration; upsampled for export |
| Coordinate system | Normalized UV (0.0–1.0) throughout | Eliminates cross-pipeline coordinate mismatch |
| River generation | Flow accumulation from eroded height map | Produces correct branching watershed networks |
| Typography | IM Fell English + Cinzel Decorative (bundled OFL fonts) | High quality, free to bundle, no procedural lettering complexity |
| Document format | `.cartograph` directory bundle | macOS-native, diff-friendly, no database required |
| Erosion | Metal compute shader from Phase 2 | CPU erosion at 1024² resolution is 30–120s — unacceptable |
| External packages | None | Stay in-house so learner understands every algorithm |

## Do NOT
- Do not add features not in the current phase of IMPLEMENTATION-ROADMAP.md
- Do not write any Swift struct that mirrors a struct in `ShaderTypes.h` — `ShaderTypes.h` is the source of truth for shared types; use the bridging header
- Do not run terrain generation passes on the main actor — always dispatch to a background `Task {}`
- Do not add network entitlements to the sandbox — this app is offline-only by design
- Do not use CocoaPods or Carthage — Swift Package Manager only
- Do not implement the style render pipeline before the terrain data pipeline is complete and verified
- Do not skip GPU Frame Capture validation after adding any new Metal shader
