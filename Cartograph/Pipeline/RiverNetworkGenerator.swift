import Foundation
import simd

struct RiverNetworkGenerator {

    /// Generate river network from a height map using D8 flow accumulation.
    /// Returns traced river nodes and a normalized flow accumulation map for debug visualization.
    static func generate(
        heightData: [Float],
        width: Int,
        height: Int,
        seaLevel: Float,
        seed: UInt64
    ) -> (nodes: [RiverNode], flowMap: [Float]) {

        // Step 1: Perturb elevations to break flat-terrain ties
        let noise = NoiseGenerator(seed: seed ^ 0xDEADBEEF)
        var perturbed = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let ux = Float(x) / Float(width)
                let uy = Float(y) / Float(height)
                let perturbation = noise.simplex2D(x: ux * 512.0, y: uy * 512.0) * 0.001
                perturbed[y * width + x] = heightData[y * width + x] + perturbation
            }
        }

        // Step 2: D8 flow direction — steepest downhill neighbor among all 8
        let offsets: [(dx: Int, dy: Int, dist: Float)] = [
            (-1, -1, 1.41421356), (0, -1, 1.0), (1, -1, 1.41421356),
            (-1,  0, 1.0),                        (1,  0, 1.0),
            (-1,  1, 1.41421356), (0,  1, 1.0), (1,  1, 1.41421356)
        ]

        var flowDirection = [Int](repeating: -1, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let myHeight = perturbed[idx]
                var steepestSlope: Float = 0
                var steepestNeighbor = -1

                for (dx, dy, dist) in offsets {
                    let nx = x + dx, ny = y + dy
                    let neighborHeight: Float
                    if nx >= 0 && nx < width && ny >= 0 && ny < height {
                        neighborHeight = perturbed[ny * width + nx]
                    } else {
                        neighborHeight = 0  // off-grid = ocean
                    }
                    let slope = (myHeight - neighborHeight) / dist
                    if slope > steepestSlope {
                        steepestSlope = slope
                        if nx >= 0 && nx < width && ny >= 0 && ny < height {
                            steepestNeighbor = ny * width + nx
                        } else {
                            steepestNeighbor = -1  // drains off edge
                        }
                    }
                }
                flowDirection[idx] = steepestNeighbor
            }
        }

        // Step 3: Topological sort + flow accumulation
        // Process cells highest-first so upstream accumulation is added before downstream is visited
        var indices = Array(0..<(width * height))
        indices.sort { perturbed[$0] > perturbed[$1] }

        var flowAccumulation = [Int](repeating: 1, count: width * height)
        for idx in indices {
            let downstream = flowDirection[idx]
            if downstream >= 0 && downstream < width * height {
                flowAccumulation[downstream] += flowAccumulation[idx]
            }
        }

        // Step 4: Identify river cells — accumulation > threshold AND above sea level.
        // Threshold of 4000 produces ~10–40 major river systems on a 1024² map.
        let accThreshold = 4000
        var isRiver = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) {
            isRiver[i] = flowAccumulation[i] > accThreshold && heightData[i] >= seaLevel
        }

        // Step 5: Trace river chains
        // Find headwaters: river cells where no upstream river neighbor flows into them
        var isHeadwater = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) where isRiver[i] {
            var hasUpstreamRiver = false
            let x = i % width, y = i / width
            for (dx, dy, _) in offsets {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let nIdx = ny * width + nx
                if isRiver[nIdx] && flowDirection[nIdx] == i {
                    hasUpstreamRiver = true
                    break
                }
            }
            isHeadwater[i] = !hasUpstreamRiver
        }

        // Trace chains from each headwater downstream
        var cellToNodeID = [Int: UUID]()
        var allNodes = [RiverNode]()
        var nodeIndexByID = [UUID: Int]()  // O(1) index lookup for downstream linking

        for startIdx in 0..<(width * height) where isHeadwater[startIdx] {
            var current = startIdx
            var previousNodeID: UUID? = nil

            while true {
                // Confluence: this cell already has a node from another chain — link and stop
                if let existingID = cellToNodeID[current] {
                    if let prevID = previousNodeID,
                       let prevIdx = nodeIndexByID[prevID] {
                        allNodes[prevIdx].downstream = existingID
                    }
                    break
                }

                let x = current % width, y = current / width
                let node = RiverNode(
                    id: UUID(),
                    position: SIMD2(Float(x) / Float(width), Float(y) / Float(height)),
                    elevation: perturbed[current],  // perturbed elevation guarantees D8 monotone descent
                    flowAccumulation: flowAccumulation[current],
                    downstream: nil
                )

                // Link previous node downstream to this one
                if let prevID = previousNodeID,
                   let prevIdx = nodeIndexByID[prevID] {
                    allNodes[prevIdx].downstream = node.id
                }

                nodeIndexByID[node.id] = allNodes.count
                cellToNodeID[current] = node.id
                allNodes.append(node)
                previousNodeID = node.id

                // Advance downstream
                let next = flowDirection[current]
                if next < 0 || next >= width * height {
                    break  // off-grid or sink
                }
                if !isRiver[next] {
                    break  // downstream cell is below threshold — ocean terminus
                }
                current = next
            }
        }

        // Step 6: Normalized log-scale flow map for debug visualization
        let maxAcc = flowAccumulation.max() ?? 1
        let logMax = log(Float(1 + maxAcc))
        var flowMap = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            flowMap[i] = log(Float(1 + flowAccumulation[i])) / logMax
        }

        return (allNodes, flowMap)
    }
}
