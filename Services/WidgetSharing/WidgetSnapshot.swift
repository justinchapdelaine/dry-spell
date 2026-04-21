import Foundation

struct WidgetSnapshot: Codable, Equatable, Sendable {
    let statusTitle: String
    let statusSubtitle: String
    let lastMeaningfulRainDate: Date?
    let dryDays: Int
    let observed7DayRainMM: Double
    let forecast48hRainMM: Double
    let updatedAt: Date
    let isStale: Bool
    let isUnavailable: Bool

    init(
        statusTitle: String,
        statusSubtitle: String,
        lastMeaningfulRainDate: Date? = nil,
        dryDays: Int = 0,
        observed7DayRainMM: Double = 0,
        forecast48hRainMM: Double = 0,
        updatedAt: Date = .now,
        isStale: Bool = false,
        isUnavailable: Bool = false
    ) {
        self.statusTitle = statusTitle
        self.statusSubtitle = statusSubtitle
        self.lastMeaningfulRainDate = lastMeaningfulRainDate
        self.dryDays = dryDays
        self.observed7DayRainMM = observed7DayRainMM
        self.forecast48hRainMM = forecast48hRainMM
        self.updatedAt = updatedAt
        self.isStale = isStale
        self.isUnavailable = isUnavailable
    }

    static let preview = WidgetSnapshot(
        statusTitle: "Water soon",
        statusSubtitle: "Dry for 5 days",
        lastMeaningfulRainDate: Calendar.current.date(byAdding: .day, value: -5, to: .now),
        dryDays: 5,
        observed7DayRainMM: 8.2,
        forecast48hRainMM: 1.1,
        updatedAt: .now,
        isStale: false,
        isUnavailable: false
    )

    static func setupNeeded(now: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(
            statusTitle: "Set up your garden",
            statusSubtitle: "Add your garden location to get started.",
            updatedAt: now,
            isStale: false,
            isUnavailable: false
        )
    }

    static func unavailable(now: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(
            statusTitle: "Weather unavailable",
            statusSubtitle: "Open Dry Spell for the latest weather.",
            updatedAt: now,
            isStale: false,
            isUnavailable: true
        )
    }

    static func make(
        hasGardenProfile: Bool,
        recommendationRawValue: String?,
        lastMeaningfulRainDate: Date?,
        dryDays: Int,
        observed7DayRainMM: Double,
        forecast48hRainMM: Double,
        fetchedAt: Date?,
        isStale: Bool,
        isUnavailable: Bool,
        now: Date = .now
    ) -> WidgetSnapshot {
        guard hasGardenProfile else {
            return .setupNeeded(now: now)
        }

        guard let recommendationRawValue, let fetchedAt else {
            return .unavailable(now: now)
        }

        let dryDaysText = dryDays > 0 ? "Dry for \(dryDays) days" : "Check the app for details"
        let title: String
        let subtitle: String

        switch recommendationRawValue {
        case "setupNeeded":
            return .setupNeeded(now: now)
        case "weatherUnavailable":
            return WidgetSnapshot(
                statusTitle: "Weather unavailable",
                statusSubtitle: "Open Dry Spell for the latest weather.",
                lastMeaningfulRainDate: lastMeaningfulRainDate,
                dryDays: dryDays,
                observed7DayRainMM: observed7DayRainMM,
                forecast48hRainMM: forecast48hRainMM,
                updatedAt: fetchedAt,
                isStale: isStale,
                isUnavailable: true
            )
        case "recentlyWatered":
            title = "Okay for now"
            subtitle = "Watered today"
        case "rainExpected":
            title = "Rain expected"
            subtitle = dryDaysText
        case "waterSoon":
            title = "Water soon"
            subtitle = dryDaysText
        case "okayForNow":
            title = "Okay for now"
            subtitle = dryDays > 0 ? dryDaysText : "Conditions steady"
        default:
            return .unavailable(now: now)
        }

        return WidgetSnapshot(
            statusTitle: title,
            statusSubtitle: subtitle,
            lastMeaningfulRainDate: lastMeaningfulRainDate,
            dryDays: dryDays,
            observed7DayRainMM: observed7DayRainMM,
            forecast48hRainMM: forecast48hRainMM,
            updatedAt: fetchedAt,
            isStale: isStale,
            isUnavailable: isUnavailable
        )
    }
}
