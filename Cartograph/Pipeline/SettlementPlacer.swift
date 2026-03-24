import Foundation
import simd

struct SettlementPlacer {

    static func place(
        heightData: [Float],
        biomeData: [Biome],
        riverNodes: [RiverNode],
        width: Int,
        height: Int,
        seaLevel: Float,
        plateCount: Int,
        seed: UInt64
    ) -> [Settlement] {

        let count = width * height
        let targetCount = max(3, plateCount * 2)

        // --- Build coastal distance map (BFS from ocean cells) ---
        // coastDist[i] = UV distance to nearest below-seaLevel cell
        var coastDist = [Float](repeating: Float.infinity, count: count)
        var queue: [Int] = []
        for i in 0..<count {
            if heightData[i] < seaLevel {
                coastDist[i] = 0
                queue.append(i)
            }
        }
        var head = 0
        while head < queue.count {
            let idx = queue[head]; head += 1
            let x = idx % width
            let y = idx / width
            let neighbors = [
                (x-1, y), (x+1, y), (x, y-1), (x, y+1)
            ]
            for (nx, ny) in neighbors {
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let ni = ny * width + nx
                let d = coastDist[idx] + 1.0 / Float(width)
                if d < coastDist[ni] {
                    coastDist[ni] = d
                    queue.append(ni)
                }
            }
        }

        // --- Build river access map: min UV distance to any river node with flow > 200 ---
        let significantRivers = riverNodes.filter { $0.flowAccumulation > 200 }

        // --- Score every land cell ---
        struct CellScore {
            let index: Int
            let uv: SIMD2<Float>
            let score: Float
            let coastalAccess: Float
            let elevation: Float
        }

        var candidates: [CellScore] = []
        candidates.reserveCapacity(count / 4)

        for i in 0..<count {
            guard heightData[i] >= seaLevel else { continue }

            let x = i % width
            let y = i / width
            let uv = SIMD2<Float>(Float(x) / Float(width), Float(y) / Float(height))
            let elevation = heightData[i]

            // 1. River access
            var minRiverDist = Float.infinity
            for rn in significantRivers {
                let d = simd_distance(uv, rn.position)
                if d < minRiverDist { minRiverDist = d }
            }
            let riverAccess = significantRivers.isEmpty ? 0 : max(0, 1 - minRiverDist * 20)

            // 2. Coastal access
            let coastalAccess = max(0, 1 - coastDist[i] * 15)

            // 3. Elevation suitability
            let elevSuit = max(0, 1 - abs(elevation - 0.42) * 8)

            // 4. Biome score
            let biomeScore: Float
            switch biomeData[i] {
            case .grassland, .temperateForest, .savanna: biomeScore = 1.0
            case .beach, .borealForest, .tundra: biomeScore = 0.5
            case .deepOcean, .shallowOcean: biomeScore = 0.0
            default: biomeScore = 0.3
            }

            let baseScore = (riverAccess + coastalAccess + elevSuit + biomeScore) / 4

            candidates.append(CellScore(
                index: i,
                uv: uv,
                score: baseScore,
                coastalAccess: coastalAccess,
                elevation: elevation
            ))
        }

        // Sort by score descending (deterministic: stable sort with index tiebreak)
        candidates.sort {
            if abs($0.score - $1.score) > 1e-6 { return $0.score > $1.score }
            return $0.index < $1.index
        }

        // --- Greedy placement with spacing penalty ---
        var placed: [Settlement] = []
        placed.reserveCapacity(targetCount)

        for candidate in candidates {
            guard placed.count < targetCount else { break }

            // Check minimum spacing from all existing settlements
            var tooClose = false
            for existing in placed {
                if simd_distance(candidate.uv, existing.position) < 0.05 {
                    tooClose = true
                    break
                }
            }
            if tooClose { continue }

            // Assign type
            let i = placed.count
            let settlementType: Settlement.SettlementType
            if candidate.coastalAccess > 0.7 {
                settlementType = .port
            } else if candidate.elevation > seaLevel + 0.35 {
                settlementType = .fortress
            } else if i == 0 {
                settlementType = .capital
            } else if i < 3 {
                settlementType = .city
            } else if i < 6 {
                settlementType = .town
            } else {
                settlementType = .village
            }

            placed.append(Settlement(
                id: UUID(),
                name: "Settlement_\(i + 1)",
                position: candidate.uv,
                type: settlementType,
                placementScore: candidate.score
            ))
        }

        return placed
    }
}
