import Foundation

enum WeatherFreshness: Equatable, Sendable {
    case fresh
    case stale
    case tooStale
}

struct RecommendationResult: Equatable, Sendable {
    let status: RecommendationStatus
    let explanationText: String
    let effective7DayMoistureMM: Double
    let deficitMM: Double
    let forecastSuppressed: Bool
    let freshness: WeatherFreshness
    let isUnavailable: Bool
}

struct RecommendationEngine {
    func evaluate(
        gardenProfile: GardenProfile?,
        weatherSnapshot: WeatherSnapshot?,
        manualWaterEvents: [ManualWaterEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RecommendationResult {
        guard let gardenProfile else {
            return RecommendationResult(
                status: .setupNeeded,
                explanationText: "Add your garden location to get started.",
                effective7DayMoistureMM: 0,
                deficitMM: 0,
                forecastSuppressed: false,
                freshness: .tooStale,
                isUnavailable: false
            )
        }

        guard let weatherSnapshot else {
            return RecommendationResult(
                status: .weatherUnavailable,
                explanationText: "Weather update needed.",
                effective7DayMoistureMM: 0,
                deficitMM: DrySpellConstants.defaultWeeklyWaterTargetMM,
                forecastSuppressed: false,
                freshness: .tooStale,
                isUnavailable: true
            )
        }

        let freshness = freshness(for: weatherSnapshot, now: now)

        guard freshness != .tooStale, !weatherSnapshot.isUnavailable else {
            return RecommendationResult(
                status: .weatherUnavailable,
                explanationText: "Weather update needed.",
                effective7DayMoistureMM: weatherSnapshot.effective7DayMoistureMM,
                deficitMM: weatherSnapshot.deficitMM,
                forecastSuppressed: weatherSnapshot.isForecastSuppressed,
                freshness: freshness,
                isUnavailable: true
            )
        }

        let manualWaterCreditMM = manualWaterCredit(
            from: manualWaterEvents,
            now: now,
            calendar: calendar
        )
        let effective7DayMoistureMM = min(
            DrySpellConstants.defaultWeeklyWaterTargetMM,
            weatherSnapshot.observed7DayRainMM + manualWaterCreditMM
        )
        let deficitMM = max(0, DrySpellConstants.defaultWeeklyWaterTargetMM - effective7DayMoistureMM)
        let forecastSuppressed = deficitMM > 0 && weatherSnapshot.forecast48hRainMM >= deficitMM
        let wateredToday = userWateredToday(
            manualWaterEvents: manualWaterEvents,
            now: now,
            calendar: calendar
        )

        let status: RecommendationStatus
        let explanationText: String

        if wateredToday {
            status = .recentlyWatered
            explanationText = "You marked watered today."
        } else if weatherSnapshot.dryDays >= gardenProfile.dryDayThresholdDays, deficitMM > 0, forecastSuppressed {
            status = .rainExpected
            explanationText = "Dry threshold reached, but enough rain is forecast in the next 48 hours."
        } else if weatherSnapshot.dryDays >= gardenProfile.dryDayThresholdDays, deficitMM > 0 {
            status = .waterSoon
            explanationText = "Dry threshold reached and no meaningful rain is forecast."
        } else {
            status = .okayForNow
            explanationText = "Recent rain or forecast keeps watering need below the threshold."
        }

        return RecommendationResult(
            status: status,
            explanationText: explanationText,
            effective7DayMoistureMM: effective7DayMoistureMM,
            deficitMM: deficitMM,
            forecastSuppressed: forecastSuppressed,
            freshness: freshness,
            isUnavailable: false
        )
    }

    func freshness(for weatherSnapshot: WeatherSnapshot, now: Date = .now) -> WeatherFreshness {
        let age = now.timeIntervalSince(weatherSnapshot.fetchedAt)

        if age >= 24 * 60 * 60 {
            return .tooStale
        }

        if age > 6 * 60 * 60 {
            return .stale
        }

        return .fresh
    }

    func nextFreshnessTransitionDate(
        for weatherSnapshot: WeatherSnapshot?,
        now: Date = .now
    ) -> Date? {
        guard let weatherSnapshot else {
            return nil
        }

        let sixHourBoundary = weatherSnapshot.fetchedAt.addingTimeInterval(6 * 60 * 60)
        let dayBoundary = weatherSnapshot.fetchedAt.addingTimeInterval(24 * 60 * 60)

        if now < sixHourBoundary {
            return sixHourBoundary
        }

        if now < dayBoundary {
            return dayBoundary
        }

        return nil
    }

    func evaluatedSnapshot(
        gardenProfile: GardenProfile,
        weatherSnapshot: WeatherSnapshot,
        manualWaterEvents: [ManualWaterEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeatherSnapshot {
        let recommendation = evaluate(
            gardenProfile: gardenProfile,
            weatherSnapshot: weatherSnapshot,
            manualWaterEvents: manualWaterEvents,
            now: now,
            calendar: calendar
        )

        return WeatherSnapshot(
            id: weatherSnapshot.id,
            fetchedAt: weatherSnapshot.fetchedAt,
            lastMeaningfulRainDate: weatherSnapshot.lastMeaningfulRainDate,
            observed7DayRainMM: weatherSnapshot.observed7DayRainMM,
            forecast48hRainMM: weatherSnapshot.forecast48hRainMM,
            effective7DayMoistureMM: recommendation.effective7DayMoistureMM,
            deficitMM: recommendation.deficitMM,
            dryDays: weatherSnapshot.dryDays,
            recommendationRawValue: recommendation.status.rawValue,
            explanationText: recommendation.explanationText,
            isForecastSuppressed: recommendation.forecastSuppressed,
            isStale: recommendation.freshness == .stale,
            isUnavailable: recommendation.isUnavailable,
            attributionText: weatherSnapshot.attributionText,
            attributionURLString: weatherSnapshot.attributionURLString
        )
    }

    func manualWaterCredit(
        from manualWaterEvents: [ManualWaterEvent],
        now: Date,
        calendar: Calendar
    ) -> Double {
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now

        return manualWaterEvents
            .filter { $0.occurredAt >= sevenDaysAgo && $0.occurredAt <= now }
            .reduce(0) { $0 + $1.creditedMM }
    }

    func userWateredToday(
        manualWaterEvents: [ManualWaterEvent],
        now: Date,
        calendar: Calendar
    ) -> Bool {
        manualWaterEvents.contains { calendar.isDate($0.occurredAt, inSameDayAs: now) }
    }
}
