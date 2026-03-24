import Foundation
import simd

// MARK: - Types

struct TectonicPlate: Identifiable {
    let id: UUID
    let index: Int
    var center: SIMD2<Float>
    var velocity: SIMD2<Float>
    var isOceanic: Bool
    var cellCount: Int = 0
}

struct PlateBoundary {
    enum BoundaryType {
        case convergent, divergent, transform
    }

    var type: BoundaryType
    var plateIndices: (Int, Int)
    var normal: SIMD2<Float>
    var cells: Set<Int>
}

struct TectonicParameters {
    var seed: UInt64 = 42
    var plateCount: Int = 8
    var seaLevel: Float = 0.35
    var mountainHeight: Float = 0.6
    var noiseScale: Float = 0.5
}

struct CellBoundaryInfo {
    var distance: Int = Int.max
    var boundaryKey: IntPair?
}

// MARK: - Simulator

struct TectonicSimulator {
    static let width = 1024
    static let height = 1024

    static func run(params: TectonicParameters) -> (heightMap: HeightMap, plateIndex: [Int]) {
        let width = Self.width
        let height = Self.height
        let cellCount = width * height
        let noise = NoiseGenerator(seed: params.seed)
        var rng = Xorshift64(seed: params.seed)

        // Step 1: Generate plate seeds and properties
        var seeds = [SIMD2<Float>]()
        var plates = [TectonicPlate]()
        for i in 0..<params.plateCount {
            let center = SIMD2<Float>(rng.nextFloat(), rng.nextFloat())
            seeds.append(center)

            let isOceanic = rng.nextFloat() < 0.6
            let angle = rng.nextFloat() * 2.0 * Float.pi
            let magnitude = 0.01 + rng.nextFloat() * 0.04
            let velocity = SIMD2<Float>(cos(angle), sin(angle)) * magnitude

            plates.append(TectonicPlate(
                id: UUID(),
                index: i,
                center: center,
                velocity: velocity,
                isOceanic: isOceanic
            ))
        }

        // Step 2: Voronoi tessellation
        let plateIndex = VoronoiDiagram.assign(seeds: seeds, width: width, height: height)

        // Count cells per plate
        var cellCounts = [Int](repeating: 0, count: params.plateCount)
        for idx in plateIndex { cellCounts[idx] += 1 }
        for i in 0..<params.plateCount { plates[i].cellCount = cellCounts[i] }

        // Step 3: Boundary detection (Moore 8-neighbor)
        let offsets: [(Int, Int)] = [(-1,-1), (0,-1), (1,-1), (-1,0), (1,0), (-1,1), (0,1), (1,1)]
        var boundaryMap = [Bool](repeating: false, count: cellCount)
        var boundaryPairCells = [IntPair: Set<Int>]()

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let myPlate = plateIndex[idx]
                for (dx, dy) in offsets {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let neighborPlate = plateIndex[ny * width + nx]
                    if neighborPlate != myPlate {
                        boundaryMap[idx] = true
                        let pair = IntPair(myPlate, neighborPlate)
                        boundaryPairCells[pair, default: []].insert(idx)
                        break
                    }
                }
            }
        }

        // Step 4: Classify boundaries
        var boundaries = [IntPair: PlateBoundary]()
        for (pair, cells) in boundaryPairCells {
            let plateA = plates[pair.a]
            let plateB = plates[pair.b]

            let centerDiff = plateB.center - plateA.center
            let dist = simd_length(centerDiff)
            let normal: SIMD2<Float> = dist > 1e-6 ? centerDiff / dist : SIMD2(1, 0)

            let vRel = plateA.velocity - plateB.velocity
            let convergence = simd_dot(vRel, normal)

            let type: PlateBoundary.BoundaryType
            if convergence > 0.01 {
                type = .convergent
            } else if convergence < -0.01 {
                type = .divergent
            } else {
                type = .transform
            }

            boundaries[pair] = PlateBoundary(
                type: type,
                plateIndices: (pair.a, pair.b),
                normal: normal,
                cells: cells
            )
        }

        // Step 5: BFS distance field with boundary metadata
        var cellInfo = [CellBoundaryInfo](repeating: CellBoundaryInfo(), count: cellCount)
        var queue = [Int]()
        queue.reserveCapacity(cellCount / 4)
        var head = 0

        // Seed BFS from all boundary cells
        for i in 0..<cellCount where boundaryMap[i] {
            cellInfo[i].distance = 0
            // Find the boundary pair this cell belongs to
            let myPlate = plateIndex[i]
            for (dx, dy) in offsets {
                let x = i % width, y = i / width
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let neighborPlate = plateIndex[ny * width + nx]
                if neighborPlate != myPlate {
                    cellInfo[i].boundaryKey = IntPair(myPlate, neighborPlate)
                    break
                }
            }
            queue.append(i)
        }

        let maxRadius = 50
        while head < queue.count {
            let idx = queue[head]
            head += 1
            let dist = cellInfo[idx].distance
            if dist >= maxRadius { continue }
            let x = idx % width, y = idx / width
            for (dx, dy) in offsets {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let nIdx = ny * width + nx
                if cellInfo[nIdx].distance > dist + 1 {
                    cellInfo[nIdx].distance = dist + 1
                    cellInfo[nIdx].boundaryKey = cellInfo[idx].boundaryKey
                    queue.append(nIdx)
                }
            }
        }

        // Step 6: Base heights (continental 0.38–0.55, oceanic 0.15–0.32)
        var heightData = [Float](repeating: 0, count: cellCount)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let plateIdx = plateIndex[idx]
                let plate = plates[plateIdx]
                let ux = Float(x) / Float(width)
                let uy = Float(y) / Float(height)

                let cellNoise = noise.simplex2D(x: ux * 8.0, y: uy * 8.0)
                let t = (cellNoise + 1.0) / 2.0

                if plate.isOceanic {
                    heightData[idx] = 0.15 + t * 0.17
                } else {
                    heightData[idx] = 0.38 + t * 0.17
                }
            }
        }

        // Step 7: Mountain features
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let info = cellInfo[idx]
                guard info.distance < maxRadius, let key = info.boundaryKey else { continue }
                guard let boundary = boundaries[key] else { continue }

                let distUV = Float(info.distance) / Float(width)

                let plateA = plates[boundary.plateIndices.0]
                let plateB = plates[boundary.plateIndices.1]

                switch boundary.type {
                case .convergent:
                    let bothContinental = !plateA.isOceanic && !plateB.isOceanic
                    let isSubduction = plateA.isOceanic != plateB.isOceanic

                    if bothContinental {
                        let sigma: Float = 0.015
                        let peak = 0.4 * params.mountainHeight
                        heightData[idx] += peak * exp(-(distUV * distUV) / (2.0 * sigma * sigma))
                    } else if isSubduction {
                        let cellPlate = plateIndex[idx]
                        let continentalIdx = plateA.isOceanic ? plateB.index : plateA.index
                        let isOnContinentalSide = (cellPlate == continentalIdx)

                        if isOnContinentalSide {
                            let peakOffsetCells = 10
                            let effectiveDist = abs(info.distance - peakOffsetCells)
                            let effectiveUV = Float(effectiveDist) / Float(width)
                            let sigma: Float = 0.015
                            let peak = 0.25 * params.mountainHeight
                            heightData[idx] += peak * exp(-(effectiveUV * effectiveUV) / (2.0 * sigma * sigma))
                        } else if info.distance < 5 {
                            heightData[idx] -= 0.02
                        }
                    }

                case .divergent:
                    let sigma: Float = 0.01
                    heightData[idx] -= 0.05 * exp(-(distUV * distUV) / (2.0 * sigma * sigma))

                case .transform:
                    break
                }
            }
        }

        // Step 8: fBm noise modulation
        let noiseAmplitude = 0.12 * params.noiseScale
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let nx = Float(x) / 256.0
                let ny = Float(y) / 256.0
                let fbm = noise.fBm(x: nx, y: ny, octaves: 6, lacunarity: 2.0, gain: 0.5)
                heightData[idx] += fbm * noiseAmplitude
            }
        }

        // Step 9: Clamp and return
        for i in 0..<cellCount {
            heightData[i] = max(0.0, min(1.0, heightData[i]))
        }

        var result = HeightMap()
        result.data = heightData
        result.seaLevel = params.seaLevel
        return (result, plateIndex)
    }
}
