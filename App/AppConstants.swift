import Foundation

enum DrySpellConstants {
    static let appGroupIdentifier = "group.com.justinchapdelaine.dryspell"
    static let widgetSnapshotFilename = "widget-snapshot.json"
    static let backgroundRefreshTaskIdentifier = "com.justinchapdelaine.dryspell.refresh"
    static let backgroundRefreshEarliestIntervalHours = 4
    static let wateringReminderIdentifier = "com.justinchapdelaine.dryspell.watering-reminder"
    static let allowedDryDayThresholds = [3, 5, 7]
    static let defaultDryDayThresholdDays = 5
    static let defaultNotificationHour = 9
    static let defaultWeeklyWaterTargetMM = 25.4
    static let meaningfulRainDayThresholdMM = 2.5
    static let forecastSuppressionWindowHours = 48
}
