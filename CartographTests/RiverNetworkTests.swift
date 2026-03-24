import XCTest
@testable import Cartograph

final class RiverNetworkTests: XCTestCase {

    // Helper: generate a tectonic height map for testing
    private func makeTestHeightMap() -> (data: [Float], seaLevel: Float) {
        let params = TectonicParameters(seed: 42, plateCount: 8)
        let (heightMap, _) = TectonicSimulator.run(params: params)
        return (heightMap.data, heightMap.seaLevel)
    }

    func testNonEmpty() {
        let (data, seaLevel) = makeTestHeightMap()
        let (nodes, _) = RiverNetworkGenerator.generate(
            heightData: data, width: 1024, height: 1024, seaLevel: seaLevel, seed: 42
        )
        XCTAssertGreaterThan(nodes.count, 0, "Should produce at least one river node")
    }

    func testMonotoneDescent() {
        let (data, seaLevel) = makeTestHeightMap()
        let (nodes, _) = RiverNetworkGenerator.generate(
            heightData: data, width: 1024, height: 1024, seaLevel: seaLevel, seed: 42
        )
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for node in nodes {
            if let downstreamID = node.downstream, let downstream = nodeMap[downstreamID] {
                XCTAssertGreaterThanOrEqual(
                    node.elevation, downstream.elevation,
                    "River node at \(node.position) flows uphill: \(node.elevation) < \(downstream.elevation)"
                )
            }
        }
    }

    func testAccumulationIncreasesDownstream() {
        let (data, seaLevel) = makeTestHeightMap()
        let (nodes, _) = RiverNetworkGenerator.generate(
            heightData: data, width: 1024, height: 1024, seaLevel: seaLevel, seed: 42
        )
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for node in nodes {
            if let downstreamID = node.downstream, let downstream = nodeMap[downstreamID] {
                XCTAssertLessThanOrEqual(
                    node.flowAccumulation, downstream.flowAccumulation,
                    "Flow should increase downstream"
                )
            }
        }
    }

    func testDeterminism() {
        let (data, seaLevel) = makeTestHeightMap()
        let (nodes1, _) = RiverNetworkGenerator.generate(
            heightData: data, width: 1024, height: 1024, seaLevel: seaLevel, seed: 42
        )
        let (nodes2, _) = RiverNetworkGenerator.generate(
            heightData: data, width: 1024, height: 1024, seaLevel: seaLevel, seed: 42
        )
        XCTAssertEqual(nodes1.count, nodes2.count, "Same input should produce same river count")
        // Compare positions (UUIDs will differ but positions should match)
        for (n1, n2) in zip(nodes1, nodes2) {
            XCTAssertEqual(n1.position.x, n2.position.x, accuracy: 0.0001)
            XCTAssertEqual(n1.position.y, n2.position.y, accuracy: 0.0001)
            XCTAssertEqual(n1.elevation, n2.elevation, accuracy: 0.0001)
        }
    }

    func testRiverCountRange() {
        let (data, seaLevel) = makeTestHeightMap()
        let (nodes, _) = RiverNetworkGenerator.generate(
            heightData: data, width: 1024, height: 1024, seaLevel: seaLevel, seed: 42
        )
        // Count distinct river systems (nodes with no downstream)
        let termini = nodes.filter { $0.downstream == nil }.count
        XCTAssertGreaterThanOrEqual(termini, 1, "Should have at least 1 river system")
        XCTAssertLessThanOrEqual(termini, 50, "Should not have excessive river systems")
    }

    func testFlowMapRange() {
        let (data, seaLevel) = makeTestHeightMap()
        let (_, flowMap) = RiverNetworkGenerator.generate(
            heightData: data, width: 1024, height: 1024, seaLevel: seaLevel, seed: 42
        )
        for (i, v) in flowMap.enumerated() {
            XCTAssertGreaterThanOrEqual(v, 0.0, "Flow map value at \(i) below 0: \(v)")
            XCTAssertLessThanOrEqual(v, 1.0, "Flow map value at \(i) above 1: \(v)")
        }
    }
}
