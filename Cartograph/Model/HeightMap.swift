import Foundation
import simd

struct HeightMap {
    let width: Int = 1024
    let height: Int = 1024
    var data: [Float]
    var seaLevel: Float = 0.35

    init() {
        data = [Float](repeating: 0, count: 1024 * 1024)
    }

    subscript(x: Int, y: Int) -> Float {
        get {
            precondition(x >= 0 && x < width && y >= 0 && y < height)
            return data[y * width + x]
        }
        set {
            precondition(x >= 0 && x < width && y >= 0 && y < height)
            data[y * width + x] = newValue
        }
    }

    func uv(x: Int, y: Int) -> SIMD2<Float> {
        SIMD2(Float(x) / Float(width), Float(y) / Float(height))
    }
}
