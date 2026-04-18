import Foundation
import SwiftData

enum ManualWaterSource: String, Codable, Sendable, CaseIterable {
    case userMarkedWatered
}

@Model
final class ManualWaterEvent {
    @Attribute(.unique) var id: UUID
    var occurredAt: Date
    var creditedMM: Double
    var sourceRawValue: String

    init(
        id: UUID = UUID(),
        occurredAt: Date = .now,
        creditedMM: Double,
        sourceRawValue: String = ManualWaterSource.userMarkedWatered.rawValue
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.creditedMM = creditedMM
        self.sourceRawValue = sourceRawValue
    }
}
