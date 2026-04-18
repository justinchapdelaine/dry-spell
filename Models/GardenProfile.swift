import Foundation
import SwiftData

@Model
final class GardenProfile {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var dryDayThresholdDays: Int
    var notificationsEnabled: Bool
    var notificationHour: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        dryDayThresholdDays: Int = DrySpellConstants.defaultDryDayThresholdDays,
        notificationsEnabled: Bool = false,
        notificationHour: Int = DrySpellConstants.defaultNotificationHour,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dryDayThresholdDays = dryDayThresholdDays
        self.notificationsEnabled = notificationsEnabled
        self.notificationHour = notificationHour
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
