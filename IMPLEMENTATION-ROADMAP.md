# Cartograph — Implementation Roadmap

## Architecture

### System Overview
```
User Input (SwiftUI controls + gesture recognizers)
        ↓
TerrainEngine (@Observable — owns all pipeline state)
        ↓
┌─────────────────────────────────────────────────────────┐
│                  GENERATION PIPELINE                     │
│                                                         │
│  TectonicSimulator → HeightMap (Float32[1024×1024])     │
│         ↓                                               │
│  ErosionEngine (Metal Compute) → eroded HeightMap       │
│         ↓                                               │
│  RiverNetwork (flow accumulation) → RiverGraph          │
│         ↓                                               │
│  ClimateModel → BiomeMap (enum[1024×1024])              │
│         ↓                                               │
│  SettlementPlacer → [Settlement]                        │
└─────────────────────────────────────────────────────────┘
        ↓
MapRenderer (MTKViewDelegate — reads TerrainEngine state)
        ↓
┌─────────────────────────────────────────────────────────┐
│              PORTOLAN STYLE PIPELINE (Metal)            │
│                                                         │
│  ParchmentPass → base texture (cached)                  │
│  TerrainPass   → biome colors + ambient occlusion       │
│  CoastlinePass → variable-width wobbly ink strokes      │
│  RiverPass     → tapered river strokes                  │
│  MountainPass  → instanced mountain profile strokes     │
│  LabelPass     → CoreText labels composited over Metal  │
│  DecorPass     → compass rose, border frame, monsters   │
└─────────────────────────────────────────────────────────┘
        ↓
MetalMapView (NSViewRepresentable wrapping MTKView)
        ↓
ExportEngine → offscreen 4096×4096 render → PNG
```

### File Structure
```
Cartograph/
├── Cartograph.xcodeproj/
├── Cartograph/
│   ├── App/
│   │   ├── CartographApp.swift         # @main, document-based app setup
│   │   └── AppDelegate.swift           # NSApplicationDelegate, menu bar, Quick Look
│   │
│   ├── Model/
│   │   ├── TerrainEngine.swift         # @Observable — owns all pipeline state
│   │   ├── HeightMap.swift             # Float32 grid, UV-space accessors, seaLevel
│   │   ├── RiverNetwork.swift          # RiverNode graph + flow accumulation data
│   │   ├── BiomeMap.swift              # Biome enum grid + color table
│   │   ├── SettlementModel.swift       # Settlement struct + SettlementType enum
│   │   └── CartographDocument.swift    # FileDocument — save/load .cartograph bundles
│   │
│   ├── Pipeline/
│   │   ├── TectonicSimulator.swift     # Voronoi plates, mountain/rift placement
│   │   ├── ErosionEngine.swift         # Dispatches Metal compute, manages buffers
│   │   ├── ClimateModel.swift          # Köppen-simplified biome assignment
│   │   └── SettlementPlacer.swift      # Scored heuristic placement algorithm
│   │
│   ├── Rendering/
│   │   ├── MapRenderer.swift           # MTKViewDelegate — orchestrates render passes
│   │   ├── MetalMapView.swift          # NSViewRepresentable wrapping MTKView
│   │   ├── ParchmentPass.swift         # Procedural parchment base texture (cached)
│   │   ├── CoastlinePass.swift         # Marching squares contour → stroke render
│   │   ├── TerrainPass.swift           # Biome color + ambient occlusion
│   │   ├── RiverPass.swift             # Tapered line primitives along river graph
│   │   ├── MountainPass.swift          # Instanced mountain-profile strokes
│   │   ├── LabelPass.swift             # CoreText label layout composited to texture
│   │   └── DecorPass.swift             # Compass rose, border, sea monsters
│   │
│   ├── Shaders/
│   │   ├── Erosion.metal               # Compute shader — particle erosion simulation
│   │   ├── CoastlineStroke.metal       # Vertex+fragment — variable-width wobble stroke
│   │   ├── TerrainColor.metal          # Fragment — biome lookup + hill shading
│   │   ├── MountainStroke.metal        # Vertex+fragment — instanced mountain strokes
│   │   ├── Parchment.metal             # Fragment — procedural parchment texture
│   │   └── ShaderTypes.h               # Shared structs — MUST match Swift byte-for-byte
│   │
│   ├── Views/
│   │   ├── ContentView.swift           # Root split view: sidebar + map canvas
│   │   ├── SidebarView.swift           # Parameter controls, sliders, Generate button
│   │   ├── MapCanvasView.swift         # MetalMapView + gesture recognizers
│   │   ├── ProgressOverlayView.swift   # Pipeline progress HUD (4 named stages)
│   │   └── ExportPanel.swift           # Export options sheet
│   │
│   ├── Resources/
│   │   ├── Fonts/
│   │   │   ├── IMFellEnglish-Regular.ttf
│   │   │   └── CinzelDecorative-Regular.ttf
│   │   └── Assets/
│   │       ├── compass_rose.pdf        # Vector, renders at any resolution
│   │       └── sea_monsters/           # Pre-rendered PNGs (SVG→PNG at 512×256)
│   │
│   └── Utilities/
│       ├── NoiseGenerator.swift        # Simplex noise + fBm — no external dependency
│       ├── VoronoiDiagram.swift        # Nearest-seed brute-force (sufficient for v1)
│       ├── MarchingSquares.swift       # Coastline contour extraction from height map
│       └── Extensions.swift            # simd_float2 helpers, CGPoint ↔ UV conversions
│
├── CartographTests/
│   ├── HeightMapTests.swift
│   ├── NoiseGeneratorTests.swift
│   ├── RiverNetworkTests.swift
│   └── TectonicSimulatorTests.swift
│
├── CLAUDE.md
└── IMPLEMENTATION-ROADMAP.md
```

### Shared Metal/Swift Type Definitions (ShaderTypes.h)

`ShaderTypes.h` is the **single source of truth** for all structs shared between Swift and Metal. Never redefine these in Swift — include via bridging header.

```c
// Cartograph/Shaders/ShaderTypes.h
#ifndef ShaderTypes_h
#define ShaderTypes_h
#include <simd/simd.h>

typedef struct {
    simd_float2 position;   // clip space -1..1
    simd_float2 texCoord;   // UV 0..1
} Vertex;

typedef struct {
    simd_float4x4 modelViewProjection;
    simd_float2 mapSize;    // width, height in pixels
    float time;             // reserved for future animation
    float seaLevel;         // normalized 0..1, default 0.35
} Uniforms;

typedef struct {
    simd_float2 position;   // UV space 0..1
    float elevation;
    float flowAccumulation; // normalized 0..1
} RiverVertex;

typedef struct {
    simd_float2 center;     // UV space — mountain ridge peak
    float size;             // world-space size multiplier
    float rotation;         // radians, along ridge direction
} MountainInstance;

typedef struct {
    uint32_t mapWidth;      // always 1024
    uint32_t mapHeight;     // always 1024
    uint32_t particleCount; // default 500000
    float inertia;          // 0.05
    float sedimentCapacity; // 4.0
    float minSlope;         // 0.01
    float erosionRate;      // 0.3
    float depositRate;      // 0.3
    float evaporationRate;  // 0.01
    uint32_t seed;
} ErosionParams;

#endif
```

Bridging header at `Cartograph/Cartograph-Bridging-Header.h`:
```c
#import "Shaders/ShaderTypes.h"
```

Build setting: `SWIFT_OBJC_BRIDGING_HEADER = Cartograph/Cartograph-Bridging-Header.h`

### Swift Data Models

```swift
// HeightMap.swift
struct HeightMap {
    let width: Int  = 1024
    let height: Int = 1024
    var data: [Float]        // row-major Float32, 0.0 = sea floor, 1.0 = peak
    var seaLevel: Float = 0.35

    subscript(x: Int, y: Int) -> Float {
        get { data[y * width + x] }
        set { data[y * width + x] = newValue }
    }
    func uv(x: Int, y: Int) -> SIMD2<Float> {
        SIMD2(Float(x) / Float(width), Float(y) / Float(height))
    }
}

// TectonicSimulator.swift
struct TectonicPlate: Identifiable {
    let id: UUID
    var center: SIMD2<Float>     // UV space
    var velocity: SIMD2<Float>   // direction + magnitude
    var isOceanic: Bool          // oceanic plates subduct under continental
    var cells: [SIMD2<Int>]      // grid cells belonging to this plate
}

struct PlateBoundary {
    enum BoundaryType { case convergent, divergent, transform }
    var type: BoundaryType
    var plates: (UUID, UUID)
    var points: [SIMD2<Float>]   // UV-space boundary line
}

// RiverNetwork.swift
struct RiverNode: Identifiable {
    let id: UUID
    var position: SIMD2<Float>   // UV space
    var elevation: Float
    var flowAccumulation: Int    // upstream cells draining through here
    var downstream: UUID?        // nil = ocean terminus
}

// BiomeMap.swift
enum Biome: UInt8 {
    case deepOcean = 0, shallowOcean = 1, beach = 2
    case desert = 3, savanna = 4, tropicalRainforest = 5
    case grassland = 6, temperateForest = 7, borealForest = 8
    case tundra = 9, glacier = 10, mountain = 11, volcano = 12
}

struct BiomeMap {
    let width = 1024, height = 1024
    var data: [Biome]
    static let colorTable: [Biome: SIMD4<Float>] = [
        .deepOcean:          SIMD4(0.08, 0.18, 0.32, 1.0),
        .shallowOcean:       SIMD4(0.15, 0.28, 0.48, 1.0),
        .beach:              SIMD4(0.76, 0.70, 0.50, 1.0),
        .desert:             SIMD4(0.82, 0.72, 0.45, 1.0),
        .savanna:            SIMD4(0.68, 0.65, 0.35, 1.0),
        .tropicalRainforest: SIMD4(0.12, 0.38, 0.15, 1.0),
        .grassland:          SIMD4(0.55, 0.68, 0.38, 1.0),
        .temperateForest:    SIMD4(0.25, 0.48, 0.22, 1.0),
        .borealForest:       SIMD4(0.20, 0.35, 0.25, 1.0),
        .tundra:             SIMD4(0.60, 0.62, 0.55, 1.0),
        .glacier:            SIMD4(0.88, 0.92, 0.95, 1.0),
        .mountain:           SIMD4(0.55, 0.50, 0.45, 1.0),
    ]
}

// SettlementModel.swift
struct Settlement: Identifiable, Codable {
    let id: UUID
    var name: String
    var position: SIMD2<Float>   // UV space
    enum SettlementType: String, Codable {
        case capital, city, town, village, port, fortress
    }
    var type: SettlementType
    var placementScore: Float    // 0–1
}

// CartographDocument.swift — serialized to metadata.json inside .cartograph bundle
struct CartographDocumentData: Codable {
    var version: Int = 1
    var seed: UInt64
    var plateCount: Int
    var seaLevel: Float
    var erosionParticleCount: Int
    var erosionRate: Float
    var settlements: [Settlement]
    // heightmap.bin, biomes.bin, rivers.json stored as sibling files in bundle
}
```

### Frameworks to Link (no install commands — all system frameworks)

In Xcode → Target → General → Frameworks, Libraries, and Embedded Content → add:
- `Metal.framework`
- `MetalKit.framework`
- `MetalPerformanceShaders.framework` (Gaussian blur for parchment ink-bleed)
- `Accelerate.framework` (vDSP for CPU noise, biome smoothing)
- `CoreText.framework` (label rendering)

Fonts to download and add to target (Copy Bundle Resources):
- IM Fell English: https://fonts.google.com/specimen/IM+Fell+English → `IMFellEnglish-Regular.ttf`
- Cinzel Decorative: https://fonts.google.com/specimen/Cinzel+Decorative → `CinzelDecorative-Regular.ttf`

### Metal Pipeline Patterns (reference for learner)

**Render pipeline** (draws geometry): uses `MTLRenderCommandEncoder`. Used by: CoastlinePass, TerrainPass, RiverPass, MountainPass, ParchmentPass, DecorPass.

**Compute pipeline** (parallel GPU computation): uses `MTLComputeCommandEncoder`. Used by: ErosionEngine only.

**Blit operations** (texture copy): uses `MTLBlitCommandEncoder`. Used by: ExportEngine (GPU → CPU readback).

Each pass creates its own encoder from a shared `MTLCommandBuffer` per frame.

### App Sandbox Entitlements

```xml
<!-- Cartograph.entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<!-- No network entitlement — offline-only by design -->
```

### Document Bundle Format (.cartograph)

```
MyWorld.cartograph/          ← directory package (appears as single file in Finder)
├── metadata.json            ← CartographDocumentData (Codable JSON)
├── heightmap.bin            ← raw Float32 array, 1024×1024×4 bytes = 4MB
├── biomes.bin               ← raw UInt8 array, 1024×1024×1 byte = 1MB
├── rivers.json              ← [RiverNode] array (Codable JSON)
├── settlements.json         ← [Settlement] array (Codable JSON)
└── preview.png              ← 512×512 thumbnail for Finder Quick Look
```

Register UTType in Info.plist:
```xml
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key>
    <string>com.yourname.cartograph.document</string>
    <key>UTTypeDescription</key>
    <string>Cartograph World Map</string>
    <key>UTTypeConformsTo</key>
    <array><string>public.directory</string></array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <array><string>cartograph</string></array>
    </dict>
  </dict>
</array>
```

---

## Scope Boundaries

**In scope (v1 / TestFlight):**
- Full geological pipeline: tectonic simulation → hydraulic erosion → rivers → biomes → settlements
- Single cartographic style: Age of Exploration portolan chart
- Export: PNG at 4096×4096px
- Save/load `.cartograph` document bundles
- Settlement placement with manual override (drag, rename, add, remove)
- macOS 14+ only

**Out of scope (v1):**
- iPad / iPhone support
- Regional zoom (drilling into sub-maps)
- Procedurally generated place names
- Additional cartographic styles (Tolkien, nautical chart, Soviet topo, etc.)
- Sharing map configurations / community features
- Subscription or IAP (TestFlight-first, monetization decided post-feedback)
- Apple Pencil input (Mac-first)

**Deferred (post-TestFlight feedback):**
- v2 styles: Tolkien illustrated, nautical chart, Soviet topographic, sci-fi planetary, medieval illuminated
- v2: Regional zoom with detail level increase at local scale
- v2: Procedural place name generation (linguistic rules per culture)
- v2: Community map parameter sharing

---

## Security & Credentials

- No credentials — no network, no accounts, no external services
- No data leaves the machine under any circumstances
- Sandbox enabled from Phase 0 — only `files.user-selected.read-write` entitlement
- No telemetry, no crash reporting in v1 (add Sentry post-TestFlight if desired)
- All user data lives in `.cartograph` bundles the user explicitly saves — nothing written to Application Support without user action

---

## Phase 0: Foundation (Weeks 1–2)

**Objective:** Xcode project scaffolded, Metal smoke test renders a triangle, all core Swift types compile, grayscale noise height map visible in the app window.

**Tasks:**
1. Create macOS Document App in Xcode. Bundle ID: `com.yourname.cartograph`. Deployment: macOS 14.0. Language: Swift. Interface: SwiftUI. Delete placeholder `ContentView` and `CartographDocument` — you'll replace them. — **Acceptance:** `xcodebuild -scheme Cartograph build` exits 0.

2. Add Metal, MetalKit, MetalPerformanceShaders, Accelerate, CoreText frameworks to the target. — **Acceptance:** `import Metal` in any Swift file compiles without error.

3. Create `Cartograph/Shaders/ShaderTypes.h` with the full struct definitions from the Architecture section above. Create `Cartograph/Cartograph-Bridging-Header.h` containing `#import "Shaders/ShaderTypes.h"`. Set `SWIFT_OBJC_BRIDGING_HEADER` build setting. — **Acceptance:** A Swift file declaring `let v = Vertex()` compiles without error.

4. Build Metal triangle smoke test: `Shaders/Triangle.metal` (passthrough vertex shader, red fragment shader). `Rendering/MetalMapView.swift` as `NSViewRepresentable` wrapping `MTKView` with `MapRenderer` delegate rendering one red triangle. Place `MetalMapView()` in `ContentView`. — **Acceptance:** Launch app → red triangle on black background. GPU Frame Capture (Product > Profile > GPU Frame Capture) shows draw call with zero validation errors.

5. Implement all Swift data types: `HeightMap`, `TerrainEngine` (@Observable), `BiomeMap`, `TectonicPlate`, `PlateBoundary`, `RiverNode`, `Settlement`, `CartographDocumentData` — exact definitions from Architecture section above. — **Acceptance:** All types compile. `HeightMap()` initializer produces `data` array of length 1,048,576.

6. Implement `Utilities/NoiseGenerator.swift`: Simplex noise 2D + fBm layering. Expose `func simplex2D(x: Float, y: Float) -> Float` (returns -1.0...1.0) and `func fBm(x: Float, y: Float, octaves: Int, lacunarity: Float, gain: Float) -> Float`. Reference: Stefan Gustavson's public domain simplex noise. — **Acceptance:** Unit test asserts `simplex2D(0.5, 0.5)` ∈ -1.0...1.0 for 100 random inputs. `fBm(0.0, 0.0, octaves:6, lacunarity:2.0, gain:0.5)` ≠ `fBm(0.1, 0.0, ...)`.

7. Replace the triangle in `MapRenderer` with a grayscale height map debug view: generate a noise `HeightMap`, upload to `MTLTexture` (R32Float format), render using a simple fragment shader (`output = float4(h, h, h, 1.0)`). — **Acceptance:** App shows grayscale noise field with visible variation (not solid gray, not black).

**Verification checklist:**
- [ ] `xcodebuild -scheme Cartograph build` → exits 0, zero shader warnings
- [ ] App cold-launches in <2 seconds
- [ ] GPU Frame Capture: height map texture bound and sampled, no validation errors
- [ ] `xcodebuild test -scheme CartographTests` → 2 unit tests pass
- [ ] Window resizes without black borders or layout breaks

**Risks:**
- ShaderTypes.h bridging fails: ensure it includes only `simd/simd.h` — no Objective-C. If needed, verify memory layout with `MemoryLayout<Vertex>.size == 16` (2× SIMD2<Float>).

---

## Phase 1: Tectonic Simulation (Weeks 3–4)

**Objective:** Voronoi-based plate simulation generates continental shapes. Mountain ranges at convergent boundaries. Height map populated and visible as debug view. Sidebar controls wired.

**Tasks:**
1. Implement `Utilities/VoronoiDiagram.swift`: nearest-seed brute-force Voronoi (not Fortune's — sufficient for v1). Input: `[SIMD2<Float>]` seeds in UV space, output: `[Int]` plate index per 1024×1024 cell (row-major). For 10 plates on 1024² grid: 10M comparisons, ~50ms on M4 Pro. — **Acceptance:** 10 seeds → every cell has valid index 0–9. Debug view colors each plate a random color — visually distinct regions.

2. Implement `Pipeline/TectonicSimulator.swift`. Steps: (a) generate N plates (default 8) with random Voronoi seeds + random `isOceanic` (60% oceanic probability); (b) random velocity vectors (magnitude 0.01–0.05); (c) detect boundaries by scanning adjacent cells with different plate IDs; (d) classify boundary type: convergent if `dot(v1-v2, boundary_normal) > 0.01`, divergent if < -0.01, else transform; (e) assign base heights: continental cells 0.38–0.55, oceanic 0.15–0.32; (f) at convergent continental-continental boundaries, add Gaussian mountain ridge: `height += 0.4 * exp(-dist² / (2 * 0.015²))`; at oceanic subduction, add island arc. — **Acceptance:** Seed 42 + 8 plates → visibly distinct landmasses, mountain bands at convergent boundaries, at least 1 island arc.

3. Add fBm noise modulation to coast lines: after tectonic assignment, add `fBm(octaves:6, lacunarity:2.0, gain:0.5) * 0.12` to break up geometric boundaries. — **Acceptance:** Coastline at `seaLevel = 0.35` threshold is irregular — not a polygon.

4. Wire sidebar controls: Plate Count slider (4–20, default 8), Sea Level (0.25–0.50, default 0.35), Mountain Height (0–1, default 0.6), Noise Scale (0–1, default 0.5). "Generate World" button calls `TerrainEngine.runTectonicPass()` inside `Task {}` on background executor. `ProgressOverlayView` appears during generation using `@Published var progress: Double`. — **Acceptance:** Adjust Plate Count 8→12, click Generate → visibly more plates. Progress overlay appears and disappears correctly.

**Verification checklist:**
- [ ] Determinism: seed 42 + 8 plates → identical height map on re-run
- [ ] Sea Level 0.25 → mostly land; 0.50 → mostly ocean — visible in debug view
- [ ] Mountain Height 0 → no ridges; 1.0 → bright ridges at boundaries
- [ ] Generation completes in <3 seconds (CPU-only phase, should be fast)
- [ ] Debug view updates without app relaunch

**Risks:**
- Voronoi boundary detection: if adjacent-cell scan misses diagonal neighbors, boundaries will be too thick. Scan all 8 neighbors (Moore neighborhood), not just 4 (Von Neumann).

---

## Phase 2: Erosion, Rivers, Climate (Weeks 5–7)

**Objective:** Hydraulic erosion via Metal compute shader makes terrain naturalistic. River network generated via flow accumulation. Biome map assigned. Full pipeline wired with progress reporting.

### Metal Compute Pattern (reference for learner)

```swift
// ErosionEngine.swift — dispatch pattern
let commandBuffer = commandQueue.makeCommandBuffer()!
let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
computeEncoder.setComputePipelineState(erosionPipeline)  // compiled from Erosion.metal
computeEncoder.setBuffer(heightMapBuffer, offset: 0, index: 0)
computeEncoder.setBytes(&params, length: MemoryLayout<ErosionParams>.size, index: 1)

let threadgroupSize = MTLSize(width: 64, height: 1, depth: 1)
let threadgroupCount = MTLSize(width: (500_000 + 63) / 64, height: 1, depth: 1)
computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
computeEncoder.endEncoding()
commandBuffer.commit()
commandBuffer.waitUntilCompleted()  // call from background Task only
```

**Tasks:**
1. Implement `Shaders/Erosion.metal` compute kernel. Each thread = one raindrop particle. Per-particle algorithm (30 steps max): (a) random start position; (b) compute gradient from 4 neighbors; (c) `velocity = velocity * inertia - gradient * (1 - inertia)` where inertia = 0.05; (d) move one step; (e) if downhill → erode (lower source, carry sediment); if decelerating → deposit; (f) evaporate (reduce water volume by `evaporationRate`). Use `metal::atomic<int>` with fixed-point for height map writes (multiply by 65536, use int atomic add, divide back). — **Acceptance:** GPU Frame Capture shows compute pass with 500,000 threads. Post-erosion height map shows carved valley features absent before erosion.

2. Implement `Pipeline/ErosionEngine.swift`. Create `MTLBuffer` from `HeightMap.data`. Compile compute pipeline from `Erosion.metal`. Dispatch in 10 batches of 50,000 particles; after each batch, readback buffer to CPU and update `TerrainEngine.previewHeightMap` (triggers SwiftUI redraw for live preview). — **Acceptance:** 500,000 particles complete in <8 seconds on M4 Pro. Preview updates visible during erosion (not just before/after).

3. Implement flow accumulation river network in `Model/RiverNetwork.swift`. Steps: (a) for each cell, find steepest downhill neighbor (D8 algorithm — all 8 neighbors); (b) build drainage tree by following each cell's downhill pointer to ocean; (c) count flow accumulation per cell (cells draining through it); (d) cells with accumulation > 500 become river cells; (e) trace connected river cells into `RiverNode` chains from headwater to mouth. — **Acceptance:** 3–15 distinct river systems for typical 8-plate world. All rivers terminate at cells below `seaLevel`. Unit test: `RiverNetworkTests` asserts every node's elevation ≥ downstream node's elevation (no uphill flow).

4. Implement `Pipeline/ClimateModel.swift`. Input per cell: latitude (y UV, 0=south pole, 1=north pole, 0.5=equator), elevation, moisture (1 - normalized distance to nearest ocean cell). Assignment via lookup table (not if-chains):
   ```swift
   func assignBiome(latitude: Float, elevation: Float, moisture: Float) -> Biome {
       guard elevation >= seaLevel else {
           return elevation < seaLevel - 0.08 ? .deepOcean : .shallowOcean
       }
       guard elevation >= seaLevel + 0.02 else { return .beach }
       if elevation > 0.85 { return moisture > 0.4 ? .glacier : .mountain }
       let equatorDist = abs(latitude - 0.5) * 2  // 0=equator, 1=pole
       if equatorDist < 0.2 { return moisture > 0.5 ? .tropicalRainforest : .desert }
       if equatorDist < 0.4 { return moisture > 0.4 ? .temperateForest : .savanna }
       if equatorDist < 0.65 { return moisture > 0.3 ? .borealForest : .grassland }
       return moisture > 0.3 ? .tundra : .glacier
   }
   ```
   — **Acceptance:** Biome debug view shows tropical forest near equator where moist, desert where dry, tundra near poles, glacier at high elevation.

5. Chain full pipeline in `TerrainEngine.runFullPipeline()`: tectonic → erosion → rivers → climate. Update `progress` 0.0→1.0 across all 4 stages. Add erosion controls to SidebarView: Erosion Iterations (100K–1M, default 500K) and Erosion Strength (0.1–1.0, default 0.3). — **Acceptance:** Click Generate → progress HUD shows 4 named stages → final debug view shows biome-colored map with river overlay.

**Verification checklist:**
- [ ] Erosion compute: GPU Frame Capture shows compute pass, no GPU validation errors
- [ ] Erosion <8 seconds for 500,000 particles on 1024×1024
- [ ] Rivers flow downhill: unit test passes (no node has elevation < downstream)
- [ ] Biome map: tropical cells only near equator, glacier only at poles or elevation > 0.85
- [ ] Full pipeline (all 4 stages) <30 seconds total

**Risks:**
- Atomic float writes in Metal: if `metal::atomic<float>` is unavailable, use fixed-point: `atomic_fetch_add_explicit(ptr, (int)(delta * 65536), memory_order_relaxed)` then divide by 65536 on readback.
- River uphill flow: caused by flat terrain regions where gradient is zero. Mitigation: add a tiny slope perturbation `elevation += noise * 0.001` before flow accumulation.

---

## Phase 3: Portolan Style Renderer (Weeks 8–12)

**Objective:** Transform terrain data into a convincing Age of Exploration portolan chart. Parchment, coastlines, biome colors, rivers, mountains, labels, decorations. PNG export at 4096×4096.

**PRE-PHASE REQUIREMENT:** Before writing any rendering code, collect 20 reference images of real portolan charts (British Library, Library of Congress digital collections — all public domain). Save to `Resources/ReferenceCharts/` (.gitignore this directory — dev reference only, not shipped). Print 3 of them. Every visual decision gets compared to a reference.

**Tasks:**
1. `Shaders/Parchment.metal` fragment shader: base color `float4(0.92, 0.87, 0.72, 1.0)` → add low-frequency Perlin grain (amplitude 0.04) → edge darkening `distance(uv, float2(0.5)) * 0.3` → sparse dark age-spot blotches (noise threshold) → 2–3 near-vertical fold crease darkenings. Cache result as `MTLTexture` — recompute only when parchment seed changes. — **Acceptance:** Side-by-side with real portolan reference: warm, aged, paper-like. Not white, not aggressively distressed.

2. `Utilities/MarchingSquares.swift`: contour extraction at `seaLevel` threshold → `[[SIMD2<Float>]]` (one closed polygon per landmass). Smooth each polygon with Catmull-Rom spline (tension 0.5). — **Acceptance:** Test on cone-shaped height map → single closed polygon. Typical 8-plate world → 2–8 distinct landmass polygons.

3. `Shaders/CoastlineStroke.metal`: variable-width stroke. Vertex shader expands each point into a quad via stroke normal + width. Width varies via noise (range 1.5–3.5px at 1:1 zoom). Fragment shader: darker at stroke center, lighter at edges (ink absorption). Vertex Perlin displacement: amplitude 0.002 UV units (hand wobble). — **Acceptance:** Shown to 1 non-technical person: does the coastline look hand-drawn? Compare to portolan reference for stroke weight and wobble quality.

4. `Shaders/TerrainColor.metal` fragment shader: sample biome color from 1D lookup texture (built from `BiomeMap.colorTable`) → compute AO from 8 height map neighbors (multiply result into range 0.6–1.0) → multiply biome color by AO → ocean cells: blend with parchment color at 70% opacity (portolan ocean = tinted parchment, not blue) → vignette (darken toward map edges). — **Acceptance:** Mountains visibly darker (AO). Ocean has warm parchment tint, not realistic blue. Distinct biome regions visible.

5. `Rendering/RiverPass.swift`: tapered stroke per river using same infrastructure as CoastlineStroke. Width at headwater = 0.5px, width at mouth = `min(2.5, log(flowAccumulation) * 0.3)`px. Color: `SIMD4(0.1, 0.12, 0.25, 1.0)` (blue-black ink). — **Acceptance:** Larger rivers (high flow accumulation) visibly thicker than headwater streams. Rivers visible against biome terrain.

6. `Shaders/MountainStroke.metal` instanced renderer: detect ridge cells (local maxima above `seaLevel + 0.3` within 5-cell radius) → create `MountainInstance` per ridge cell → vertex shader expands each instance to quad → fragment shader draws triangular profile stroke (thick base, thin peak, right-side shadow). Typical instance count: 200–800 per world. — **Acceptance:** Mountain ranges show clusters of triangular profile strokes. Compare to Waldseemüller map mountain convention — should be recognizable as the same icon family.

7. `Rendering/LabelPass.swift`: CoreText label layout composited to `CGBitmapContext` then uploaded as `MTLTexture`. Continent names: Cinzel Decorative 18pt italic, placed at centroid of each landmass. Ocean names: IM Fell English 14pt italic, rotated 15°, placed in large ocean areas (flow accumulation < 5). Grid-based overlap avoidance: divide map into 32×32 cells, mark occupied, skip conflicting placements. — **Acceptance:** "Test Continent" and "Test Ocean" labels visible without overlapping each other or coastlines.

8. `Rendering/DecorPass.swift`: (a) load `compass_rose.pdf` as `CGPDFDocument`, render to `MTLTexture` 256×256px, composite bottom-right corner; (b) border frame: double-line rectangle (8px outer, 4px inner), warm brown `SIMD4(0.35, 0.22, 0.12, 1.0)`, noise imperfection on edges; (c) sea monster PNGs (pre-rendered 512×256px): place 1–2 in deep ocean (accumulation < 5, elevation < 0.20). — **Acceptance:** Compass rose visible. Border surrounds map. At least 1 sea monster in a large ocean.

9. `Rendering/ExportEngine.swift`: create offscreen `MTLTexture` 4096×4096 (R8G8B8A8_Unorm) → re-run all render passes at 4× scale (UV-space geometry unchanged, pixel dimensions 4×) → `MTLBlitCommandEncoder` readback to CPU `MTLBuffer` → `CGImage` from buffer → PNG via `CGImageDestination`. Export sheet shows progress bar. — **Acceptance:** PNG produced in <10 seconds. Open in Preview → zoom 100% → mountain strokes and coastline wobble visible at print scale. File size <8MB.

**Verification checklist:**
- [ ] Full render pipeline <100ms per frame (smooth 60fps pan/zoom post-generation)
- [ ] Parchment passes "aged paper" test with non-technical viewer
- [ ] Coastline passes "hand-drawn" test (show to 2 people who don't know the app)
- [ ] Mountain strokes match portolan convention when compared to reference
- [ ] River widths scale correctly with flow accumulation
- [ ] PNG export: 4096×4096, <8MB, no visible pixelation at 100% zoom in Preview
- [ ] GPU Frame Capture: all 7 render passes execute in correct order, no validation errors

**Risks:**
- Label overlap algorithm too aggressive → skip automated placement for non-settlement labels in beta. Ship continent/ocean labels only; settlement labels in Phase 4.
- Style quality not convincing: budget 40% of Phase 3 time (8 days) to visual iteration. Treat shader parameters as art direction knobs, not code to ship and move on.

---

## Phase 4: Settlement Placement + TestFlight (Weeks 13–15)

**Objective:** Settlement heuristic + manual override. Save/load `.cartograph` bundles. TestFlight submission.

**Tasks:**
1. `Pipeline/SettlementPlacer.swift`: score every land cell on 5 criteria (each 0–1): (a) river access `max(1 - dist_to_river * 20, 0)`; (b) coastal access `max(1 - dist_to_coast * 15, 0)`; (c) elevation suitability `1 - abs(elevation - 0.42) * 8`; (d) arable biome (grassland/temperateForest/savanna → 1.0, else 0.3); (e) spacing penalty (exponential decay from existing settlements). Place `max(3, plateCount * 2)` settlements. Assign port if coastal access > 0.7. — **Acceptance:** 8-plate world → 5–20 settlements. No two within 0.05 UV units. At least 1 port on coastline. Deterministic for same seed.

2. Manual override UI: click settlement → popover (rename field, type picker, Remove button). Drag to reposition — snap to nearest land cell if dragged to ocean. Cmd+Click on map canvas adds new settlement at that position. — **Acceptance:** Rename "City_1" → "Port Auryn" → label updates on map within 0.5 seconds. Drag to ocean → snaps to nearest land cell.

3. `Model/CartographDocument.swift` save/load: write temp directory with all 6 bundle files (see bundle format in Architecture section), rename to `.cartograph`. Load reverses this. Register UTType in `Info.plist`. — **Acceptance:** Save → quit → reopen → map renders identically. Finder Quick Look (spacebar) shows 512×512 thumbnail.

4. TestFlight submission: App Store Connect record, provisioning profiles, archive (Product > Archive), upload, invite 10 external testers from r/worldbuilding or r/mapmaking. — **Acceptance:** Build appears in App Store Connect TestFlight tab. At least 1 external tester installs successfully.

**Verification checklist:**
- [ ] Settlement placement deterministic: seed 42 → identical 8 settlements on re-run
- [ ] Rename popover appears in <200ms after tap
- [ ] `.cartograph` bundle: 6 files present after save
- [ ] Round-trip test: save → reopen → settlement count matches, first settlement name matches, `heightmap[512, 512]` within Float32 epsilon
- [ ] TestFlight build installs on second Mac without error

---

## Testing Strategy

### Automated (all phases)
- `NoiseGeneratorTests.swift`: `simplex2D` output ∈ -1...1 for 100 random inputs. `fBm` produces different values at different positions.
- `HeightMapTests.swift`: subscript matches row-major index. UV conversion correct for corner cells `(0,0)`, `(1023,1023)`.
- `TectonicSimulatorTests.swift`: determinism (seed 42 → identical heights). Mountain test (convergent boundary cells have higher mean elevation than non-boundary). Sea level test (ocean cell fraction within ±5% of expected).
- `RiverNetworkTests.swift`: monotone (every node elevation ≥ downstream elevation). Terminus (all paths reach elevation < seaLevel). Accumulation increases headwater → mouth.

### Manual (Phase 3)
Generate 5 worlds with different seeds. Export each as PNG. Print 2. Compare to portolan reference charts side-by-side on paper. Measure: coastline wobble quality, mountain stroke readability, biome color distinction, label placement clearance.

### Performance (Phase 3)
Seed 42 → full pipeline + export: target <40 seconds total. Instrument each stage individually with `os_signpost` in `Instruments.app` (Time Profiler template). If any stage exceeds budget: erosion >8s, render >100ms/frame, export >10s — profile before optimizing.

### Integration (Phase 4)
Save/load round-trip: generate world, name 3 settlements, add 2 manual settlements, save, quit, reopen, export PNG. Total time <5 minutes, zero crashes.
