import Foundation

enum DrySpellConstants {
    nonisolated static let appGroupIdentifier = "group.com.justinchapdelaine.dryspell"
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

    static func dryDayThresholdSummary(for dryDayThresholdDays: Int) -> String {
        switch dryDayThresholdDays {
        case 3:
            return "A 3-day threshold checks in sooner after a short dry stretch."
        case 7:
            return "A 7-day threshold waits longer before nudging you to water."
        default:
            return "A 5-day threshold balances an early heads-up with a steadier reminder cadence."
        }
    }

    static func partialSuccessMessage(
        for completedAction: String,
        followUpIssues: [String]
    ) -> String {
        let issueSummary: String

        if followUpIssues.count == 1 {
            issueSummary = "it couldn't \(followUpIssues[0])."
        } else {
            issueSummary = "it couldn't \(followUpIssues.dropLast().joined(separator: ", ")) or \(followUpIssues.last!)."
        }

        return "Dry Spell \(completedAction), but \(issueSummary)"
    }
}
