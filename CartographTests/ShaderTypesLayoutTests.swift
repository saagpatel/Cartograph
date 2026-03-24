import XCTest
@testable import Cartograph

/// Verifies that the C structs declared in ShaderTypes.h have the memory layouts
/// expected by the Metal shaders.  If any of these assertions fail it means the
/// struct was changed without updating the corresponding shader buffer bindings.
final class ShaderTypesLayoutTests: XCTestCase {

    func testStrokeVertexSize() {
        // simd_float2 position (8) + simd_float2 normal (8) + float width (4) + float distFromCenter (4) = 24
        XCTAssertEqual(MemoryLayout<StrokeVertex>.size, 24,
                       "StrokeVertex must be 24 bytes: 2×simd_float2 + 2×float")
    }

    func testParchmentParamsSize() {
        // 6×float (24) + uint32 seed (4) + float _pad0 (4) = 32
        XCTAssertEqual(MemoryLayout<ParchmentParams>.size, 32,
                       "ParchmentParams must be 32 bytes")
    }

    func testTerrainColorParamsSize() {
        // 8×float = 32
        XCTAssertEqual(MemoryLayout<TerrainColorParams>.size, 32,
                       "TerrainColorParams must be 32 bytes: 8×float")
    }

    func testStrokeColorParamsSize() {
        // simd_float4 = 16
        XCTAssertEqual(MemoryLayout<StrokeColorParams>.size, 16,
                       "StrokeColorParams must be 16 bytes: 1×simd_float4")
    }

    func testVertexSize() {
        // simd_float2 position (8) + simd_float2 texCoord (8) = 16
        XCTAssertEqual(MemoryLayout<Vertex>.size, 16,
                       "Vertex must be 16 bytes: 2×simd_float2")
    }

    func testUniformsSize() {
        // simd_float4x4 (64) + simd_float2 mapSize (8) + float time (4) + float seaLevel (4) = 80
        XCTAssertEqual(MemoryLayout<Uniforms>.size, 80,
                       "Uniforms must be 80 bytes: simd_float4x4 + simd_float2 + 2×float")
    }
}
