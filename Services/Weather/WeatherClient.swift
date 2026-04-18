import CoreLocation
import Foundation
import WeatherKit

struct WeatherDaySample: Equatable, Sendable {
    let date: Date
    let precipitationMM: Double
}

struct WeatherHourSample: Equatable, Sendable {
    let date: Date
    let precipitationMM: Double
}

struct WeatherMetrics: Equatable, Sendable {
    let lastMeaningfulRainDate: Date?
    let observed7DayRainMM: Double
    let forecast48hRainMM: Double
    let dryDays: Int
}

struct WeatherClient {
    private let service: WeatherService
    private let recommendationEngine: RecommendationEngine

    init(
        service: WeatherService = .shared,
        recommendationEngine: RecommendationEngine = RecommendationEngine()
    ) {
        self.service = service
        self.recommendationEngine = recommendationEngine
    }

    func refreshSnapshot(
        for gardenProfile: GardenProfile,
        existingSnapshot: WeatherSnapshot?,
        manualWaterEvents: [ManualWaterEvent]
    ) async throws -> WeatherSnapshot {
        let location = CLLocation(
            latitude: gardenProfile.latitude,
            longitude: gardenProfile.longitude
        )
        let calendar = calendar(for: gardenProfile.timeZoneIdentifier)
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let trailingDailyInterval = DateInterval(
            start: calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart,
            end: calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        )
        let forecastEnd = now.addingTimeInterval(TimeInterval(DrySpellConstants.forecastSuppressionWindowHours * 60 * 60))
        let hourlyQuery: WeatherQuery<Forecast<HourWeather>> = .hourly(startDate: now, endDate: forecastEnd)

        async let attribution = service.attribution
        async let precipitationSummary: DailyWeatherSummary<DayPrecipitationSummary> = service.dailySummary(
            for: location,
            forDaysIn: trailingDailyInterval,
            including: .precipitation
        )
        async let hourlyForecast: Forecast<HourWeather> = service.weather(
            for: location,
            including: hourlyQuery
        )

        let (weatherAttribution, dailyPrecipitation, hourlyWeather) = try await (attribution, precipitationSummary, hourlyForecast)

        let daySamples = dailyPrecipitation.days.map {
            WeatherDaySample(
                date: $0.date,
                precipitationMM: Self.millimeters(from: $0.precipitationAmount)
            )
        }
        let hourSamples = hourlyWeather.forecast.map {
            WeatherHourSample(
                date: $0.date,
                precipitationMM: Self.millimeters(from: $0.precipitationAmount)
            )
        }
        let metrics = Self.makeMetrics(
            daySamples: daySamples,
            hourSamples: hourSamples,
            now: now,
            calendar: calendar,
            previousLastMeaningfulRainDate: existingSnapshot?.lastMeaningfulRainDate
        )
        let baseSnapshot = WeatherSnapshot(
            fetchedAt: now,
            lastMeaningfulRainDate: metrics.lastMeaningfulRainDate,
            observed7DayRainMM: metrics.observed7DayRainMM,
            forecast48hRainMM: metrics.forecast48hRainMM,
            effective7DayMoistureMM: 0,
            deficitMM: 0,
            dryDays: metrics.dryDays,
            recommendationRawValue: RecommendationStatus.weatherUnavailable.rawValue,
            explanationText: "",
            isForecastSuppressed: false,
            isStale: false,
            isUnavailable: false,
            attributionText: weatherAttribution.legalAttributionText,
            attributionURLString: weatherAttribution.legalPageURL.absoluteString
        )
        return recommendationEngine.evaluatedSnapshot(
            gardenProfile: gardenProfile,
            weatherSnapshot: baseSnapshot,
            manualWaterEvents: manualWaterEvents,
            now: now,
            calendar: calendar
        )
    }

    static func makeMetrics(
        daySamples: [WeatherDaySample],
        hourSamples: [WeatherHourSample],
        now: Date,
        calendar: Calendar,
        previousLastMeaningfulRainDate: Date?
    ) -> WeatherMetrics {
        let todayStart = calendar.startOfDay(for: now)
        let trailingSevenDayStarts = Set((0..<7).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: todayStart)
        })
        let sortedDaySamples = daySamples.sorted { $0.date < $1.date }
        let sortedHourSamples = hourSamples.sorted { $0.date < $1.date }

        let meaningfulRainDate = sortedDaySamples
            .last(where: { $0.precipitationMM >= DrySpellConstants.meaningfulRainDayThresholdMM })?
            .date
        let carriedMeaningfulRainDate: Date? = {
            guard meaningfulRainDate == nil else { return meaningfulRainDate }
            guard let previousLastMeaningfulRainDate else { return nil }
            return previousLastMeaningfulRainDate
        }()
        let observed7DayRainMM = sortedDaySamples
            .filter { trailingSevenDayStarts.contains(calendar.startOfDay(for: $0.date)) }
            .reduce(0) { $0 + $1.precipitationMM }
        let forecastEnd = now.addingTimeInterval(TimeInterval(DrySpellConstants.forecastSuppressionWindowHours * 60 * 60))
        let forecast48hRainMM = sortedHourSamples
            .filter { $0.date >= now && $0.date < forecastEnd }
            .reduce(0) { $0 + $1.precipitationMM }

        let dryDays: Int = {
            if let rainDate = carriedMeaningfulRainDate {
                return max(
                    0,
                    calendar.dateComponents([.day], from: calendar.startOfDay(for: rainDate), to: todayStart).day ?? 0
                )
            }

            guard let oldestSampleDate = sortedDaySamples.first?.date else {
                return 0
            }

            let oldestDayDifference = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: oldestSampleDate),
                to: todayStart
            ).day ?? 0

            return max(sortedDaySamples.count, oldestDayDifference)
        }()

        return WeatherMetrics(
            lastMeaningfulRainDate: carriedMeaningfulRainDate,
            observed7DayRainMM: observed7DayRainMM,
            forecast48hRainMM: forecast48hRainMM,
            dryDays: dryDays
        )
    }

    private static func millimeters(from measurement: Measurement<UnitLength>) -> Double {
        measurement.converted(to: .millimeters).value
    }

    private func calendar(for timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }
}
