import Foundation
import SwiftData

enum RecommendationStatus: String, Codable, Sendable, CaseIterable {
    case setupNeeded
    case weatherUnavailable
    case recentlyWatered
    case rainExpected
    case waterSoon
    case okayForNow
}

@Model
final class WeatherSnapshot {
    @Attribute(.unique) var id: UUID
    var fetchedAt: Date
    var lastMeaningfulRainDate: Date?
    var observed7DayRainMM: Double
    var forecast48hRainMM: Double
    var effective7DayMoistureMM: Double
    var deficitMM: Double
    var dryDays: Int
    var recommendationRawValue: String
    var explanationText: String
    var isForecastSuppressed: Bool
    var isStale: Bool
    var isUnavailable: Bool
    var attributionText: String
    var attributionURLString: String

    init(
        id: UUID = UUID(),
        fetchedAt: Date = .now,
        lastMeaningfulRainDate: Date? = nil,
        observed7DayRainMM: Double = 0,
        forecast48hRainMM: Double = 0,
        effective7DayMoistureMM: Double = 0,
        deficitMM: Double = 0,
        dryDays: Int = 0,
        recommendationRawValue: String = RecommendationStatus.weatherUnavailable.rawValue,
        explanationText: String = "",
        isForecastSuppressed: Bool = false,
        isStale: Bool = false,
        isUnavailable: Bool = false,
        attributionText: String = "",
        attributionURLString: String = ""
    ) {
        self.id = id
        self.fetchedAt = fetchedAt
        self.lastMeaningfulRainDate = lastMeaningfulRainDate
        self.observed7DayRainMM = observed7DayRainMM
        self.forecast48hRainMM = forecast48hRainMM
        self.effective7DayMoistureMM = effective7DayMoistureMM
        self.deficitMM = deficitMM
        self.dryDays = dryDays
        self.recommendationRawValue = recommendationRawValue
        self.explanationText = explanationText
        self.isForecastSuppressed = isForecastSuppressed
        self.isStale = isStale
        self.isUnavailable = isUnavailable
        self.attributionText = attributionText
        self.attributionURLString = attributionURLString
    }
}
