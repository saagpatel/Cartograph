import Foundation
import simd

struct ClimateModel {

    /// Generate biome map and moisture map from height data.
    static func generate(
        heightData: [Float],
        width: Int,
        height: Int,
        seaLevel: Float,
        riverNodes: [RiverNode]
    ) -> (biomeMap: BiomeMap, moistureMap: [Float]) {
        // Step 1: Compute moisture via ocean distance BFS
        let moisture = computeMoisture(
            heightData: heightData, width: width, height: height,
            seaLevel: seaLevel, riverNodes: riverNodes
        )

        // Step 2: Assign biomes
        var biomeMap = BiomeMap()
        for y in 0..<height {
            let latitude = Float(y) / Float(height)  // 0=south pole, 0.5=equator, 1=north pole
            for x in 0..<width {
                let idx = y * width + x
                let elevation = heightData[idx]
                biomeMap.data[idx] = assignBiome(
                    latitude: latitude,
                    elevation: elevation,
                    moisture: moisture[idx],
                    seaLevel: seaLevel
                )
            }
        }

        return (biomeMap, moisture)
    }

    /// Biome assignment lookup (exact roadmap spec).
    static func assignBiome(latitude: Float, elevation: Float, moisture: Float, seaLevel: Float) -> Biome {
        guard elevation >= seaLevel else {
            return elevation < seaLevel - 0.08 ? .deepOcean : .shallowOcean
        }
        guard elevation >= seaLevel + 0.02 else { return .beach }
        if elevation > 0.85 { return moisture > 0.4 ? .glacier : .mountain }
        let equatorDist = abs(latitude - 0.5) * 2.0  // 0=equator, 1=pole
        if equatorDist < 0.2 { return moisture > 0.5 ? .tropicalRainforest : .desert }
        if equatorDist < 0.4 { return moisture > 0.4 ? .temperateForest : .savanna }
        if equatorDist < 0.65 { return moisture > 0.3 ? .borealForest : .grassland }
        return moisture > 0.3 ? .tundra : .glacier
    }

    /// Compute moisture map: distance to nearest ocean cell, normalized, with river bonus.
    private static func computeMoisture(
        heightData: [Float],
        width: Int,
        height: Int,
        seaLevel: Float,
        riverNodes: [RiverNode]
    ) -> [Float] {
        let cellCount = width * height
        let offsets: [(Int, Int)] = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

        // BFS from all ocean cells
        var oceanDistance = [Int](repeating: Int.max, count: cellCount)
        var queue = [Int]()
        queue.reserveCapacity(cellCount / 2)
        var head = 0

        // Seed: all cells below sea level
        for i in 0..<cellCount where heightData[i] < seaLevel {
            oceanDistance[i] = 0
            queue.append(i)
        }

        // BFS flood fill
        while head < queue.count {
            let idx = queue[head]
            head += 1
            let dist = oceanDistance[idx]
            let x = idx % width, y = idx / width
            for (dx, dy) in offsets {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let nIdx = ny * width + nx
                if oceanDistance[nIdx] > dist + 1 {
                    oceanDistance[nIdx] = dist + 1
                    queue.append(nIdx)
                }
            }
        }

        // Normalize to moisture [0, 1]; guard against all-land map (maxDist == 0)
        let maxDist = oceanDistance.filter { $0 != Int.max }.max() ?? 0
        var moisture = [Float](repeating: 0, count: cellCount)
        for i in 0..<cellCount {
            if oceanDistance[i] == Int.max || maxDist == 0 {
                moisture[i] = 0  // no ocean reachable, or all cells are ocean seeds
            } else {
                moisture[i] = 1.0 - Float(oceanDistance[i]) / Float(maxDist)
            }
        }

        // River moisture bonus: cells near rivers get elevated moisture
        let riverRadius = 8
        let riverRadiusF = Float(riverRadius)
        for node in riverNodes {
            let rx = Int(node.position.x * Float(width))
            let ry = Int(node.position.y * Float(height))
            for dy in -riverRadius...riverRadius {
                for dx in -riverRadius...riverRadius {
                    let nx = rx + dx, ny = ry + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let dist = sqrt(Float(dx * dx + dy * dy))
                    if dist <= riverRadiusF {
                        let bonus = 0.15 * (1.0 - dist / riverRadiusF)
                        let nIdx = ny * width + nx
                        moisture[nIdx] = min(1.0, moisture[nIdx] + bonus)
                    }
                }
            }
        }

        // 3x3 box blur to smooth biome boundaries
        var smoothed = [Float](repeating: 0, count: cellCount)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                var count: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        sum += moisture[ny * width + nx]
                        count += 1
                    }
                }
                smoothed[y * width + x] = sum / count
            }
        }

        return smoothed
    }
}
