# Cartograph

[![Swift](https://img.shields.io/badge/Swift-f05138?style=flat-square&logo=swift)](#) [![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](#)

> Simulate a planet's geology in minutes and render it as a hand-drawn Age of Exploration map.

Cartograph is a macOS procedural world-map generator that simulates plate tectonics, hydraulic erosion, climate modeling, river networks, and settlement placement, then renders everything through a multi-pass Metal pipeline as portolan-style cartographic art on parchment.

## Features

- **Tectonic simulation** — Voronoi-based plate generation with mountain ridges and rift valleys
- **GPU erosion** — particle hydraulic erosion via Metal compute shaders (500,000 particles)
- **Climate and biomes** — Köppen-simplified biome assignment from elevation and moisture
- **River networks** — flow accumulation across the heightmap produces branching river graphs
- **Settlement placement** — scored heuristic algorithm places settlements at defensible, resource-rich sites
- **Portolan rendering** — multi-pass Metal pipeline: parchment, terrain, coastlines, rivers, mountain profiles, CoreText labels, compass rose, and sea-monster decorations
- **4096×4096 export** — offscreen Metal render exported as PNG

## Quick Start

### Prerequisites
- macOS 14.0+, Xcode 15+
- XcodeGen (`brew install xcodegen`)

### Installation
```bash
git clone https://github.com/saagpatel/Cartograph.git
cd Cartograph
xcodegen generate
open Cartograph.xcodeproj
```

### Usage
Build and run, then click **Generate** to simulate a world and **Export** to save a 4096×4096 PNG to your chosen path.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Language | Swift 5 |
| UI | SwiftUI + NavigationSplitView |
| GPU | Metal, MetalKit, MetalPerformanceShaders |
| Typography | CoreText |
| Math | Accelerate, simd |
| Build | XcodeGen (project.yml) |

## License

MIT
