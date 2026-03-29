# Cartograph

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square)
![Swift](https://img.shields.io/badge/swift-5-orange?style=flat-square&logo=swift)
![Metal](https://img.shields.io/badge/GPU-Metal-silver?style=flat-square)
![License](https://img.shields.io/github/license/saagpatel/Cartograph?style=flat-square)
![Tests](https://img.shields.io/badge/tests-11%20suites-brightgreen?style=flat-square)

A macOS procedural world-map generator that produces portolan-style cartographic renders from simulated geology. Plate tectonics, hydraulic erosion, climate modeling, river networks, and settlement placement feed a multi-pass Metal renderer that outputs hand-drawn-looking maps on parchment.

## Screenshot

> _Screenshot placeholder — replace with an actual screenshot of a generated map._

## Features

- **Tectonic simulation** — Voronoi-based plate generation with mountain ridges and rift valleys
- **GPU erosion** — Particle hydraulic erosion via Metal compute shaders (500 000 particles by default)
- **Climate and biomes** — Köppen-simplified biome assignment driven by elevation and moisture
- **River networks** — Flow accumulation across the heightmap produces branching river graphs
- **Settlement placement** — Scored heuristic algorithm places settlements at defensible, resource-rich sites
- **Portolan rendering** — Multi-pass Metal pipeline: parchment base, terrain, coastlines, rivers, mountain profiles, CoreText labels, compass rose, and sea-monster decorations
- **Export** — Offscreen 4096×4096 render exported as PNG
- **Persistent documents** — Saves/loads `.cartograph` directory bundles containing heightmap, biomes, rivers, settlements, and a preview thumbnail

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5 |
| UI | SwiftUI + `NavigationSplitView` |
| GPU | Metal, MetalKit, MetalPerformanceShaders |
| Typography | CoreText |
| Math | Accelerate, simd |
| Target | macOS 14+ (native app, sandboxed) |
| Build | XcodeGen (`project.yml`) |

## Prerequisites

- macOS 14.0 or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — to generate the `.xcodeproj` from `project.yml`

```bash
brew install xcodegen
```

## Getting Started

```bash
# 1. Clone
git clone https://github.com/saagpatel/Cartograph.git
cd Cartograph

# 2. Generate the Xcode project
xcodegen generate

# 3. Open and run
open Cartograph.xcodeproj
```

Select the **Cartograph** scheme, choose **My Mac** as the destination, and press Run. Click **Generate** in the sidebar to produce a new world.

## Project Structure

```
Cartograph/
├── Cartograph/
│   ├── App/                 # App entry point, Info.plist
│   ├── Model/               # TerrainEngine, HeightMap, BiomeMap, RiverNetwork, SettlementModel, CartographDocument
│   ├── Pipeline/            # TectonicSimulator, ErosionEngine, ClimateModel, SettlementPlacer, RiverNetworkGenerator
│   ├── Rendering/           # MapRenderer, MetalMapView, render passes (Parchment, Terrain, Coastline, River, Mountain, Label, Decor), ExportEngine
│   ├── Shaders/             # Metal shaders (erosion compute, coastline stroke, terrain, river, mountain, label, decor, parchment)
│   ├── Utilities/           # Supporting helpers
│   └── Views/               # SwiftUI views (ContentView, SidebarView, SettlementOverlayView, ProgressOverlayView)
└── CartographTests/         # Unit tests for all major subsystems (11 test files)
```

## Running Tests

Open the project in Xcode and press **Cmd+U**, or run from the command line:

```bash
xcodebuild test -scheme CartographTests -destination 'platform=macOS'
```

Tests cover: document serialization, climate model, heightmap, marching squares, noise generator, river networks, settlement placement, shader type layout, stroke geometry, tectonic simulation, and Voronoi diagrams.

## License

MIT — see [LICENSE](LICENSE).
