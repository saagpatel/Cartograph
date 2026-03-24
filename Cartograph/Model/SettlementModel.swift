import Foundation
import simd

struct Settlement: Identifiable, Codable {
    let id: UUID
    var name: String
    var position: SIMD2<Float>
    var type: SettlementType
    var placementScore: Float

    enum SettlementType: String, Codable {
        case capital, city, town, village, port, fortress
    }

    enum CodingKeys: String, CodingKey {
        case id, name, positionX, positionY, type, placementScore
    }

    init(id: UUID = UUID(), name: String, position: SIMD2<Float>, type: SettlementType, placementScore: Float) {
        self.id = id
        self.name = name
        self.position = position
        self.type = type
        self.placementScore = placementScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let x = try container.decode(Float.self, forKey: .positionX)
        let y = try container.decode(Float.self, forKey: .positionY)
        position = SIMD2(x, y)
        type = try container.decode(SettlementType.self, forKey: .type)
        placementScore = try container.decode(Float.self, forKey: .placementScore)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)
        try container.encode(type, forKey: .type)
        try container.encode(placementScore, forKey: .placementScore)
    }
}
