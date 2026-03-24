import Metal
import simd

// MARK: - Protocol

/// Encapsulates a single render pass in the style pipeline.
/// Conforming types own their pipeline state and buffers; the host
/// renderer calls `prepare` once at setup time and `encode` each frame.
protocol RenderPass {
    var label: String { get }

    /// One-time setup: create pipeline state, allocate buffers, etc.
    mutating func prepare(
        device: MTLDevice,
        library: MTLLibrary,
        engine: TerrainEngine,
        sharedQuadVertexBuffer: MTLBuffer,
        sharedQuadIndexBuffer: MTLBuffer
    )

    /// Encode draw commands into an already-begun render command encoder.
    func encode(encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms)
}

// MARK: - Support Types

/// Camera pan and zoom state in UV space.
struct CameraState {
    /// Pan offset in UV space (0,0 = no pan).
    var offset: SIMD2<Float> = .zero
    /// Zoom multiplier (1.0 = no zoom, >1 = zoomed in).
    var zoom: Float = 1.0
}

/// A closed polygon representing a landmass contour extracted from the height map.
struct LandmassPolygon {
    /// Vertices in UV space (0–1), wound counter-clockwise.
    var points: [SIMD2<Float>]
    /// Average of all vertex positions.
    var centroid: SIMD2<Float>
    /// Signed area via the shoelace formula (always positive for CCW winding).
    var area: Float
}

/// A single cell in the mountain-ridge detection grid.
struct RidgeCell {
    /// Cell centre in UV space.
    var position: SIMD2<Float>
    /// Normalised elevation at this cell (0–1).
    var elevation: Float
    /// Angle (radians) of the dominant ridge direction.
    var ridgeDirection: Float
}
