import Foundation

struct CartographDocumentData: Codable {
    var version: Int = 1
    var seed: UInt64
    var plateCount: Int
    var seaLevel: Float
    var erosionParticleCount: Int
    var erosionRate: Float
    var settlements: [Settlement]
}
