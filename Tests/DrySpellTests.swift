import BackgroundTasks
import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import DrySpell

struct DrySpellTests {
    @Test
    @MainActor
    func storeSeedsEmptyAppState() throws {
        let container = DrySpellModelContainer.makePreviewContainer()
        let store = DrySpellStore(modelContext: ModelContext(container))

        let state = try store.seedEmptyAppState()

        #expect(state.gardenProfile == nil)
        #expect(state.weatherSnapshot == nil)
        #expect(state.manualWaterEvents.isEmpty)
    }

    @Test
    @MainActor
    func storePersistsProfileSnapshotAndManualWaterEvent() throws {
        let container = DrySpellModelContainer.makePreviewContainer()
        let store = DrySpellStore(modelContext: ModelContext(container))
        let createdAt = Date(timeIntervalSince1970: 1_713_369_600)
        let fetchedAt = Date(timeIntervalSince1970: 1_713_456_000)
        let wateredAt = Date(timeIntervalSince1970: 1_713_542_400)

        let savedProfile = try store.saveGardenProfile(
            GardenProfile(
                displayName: "Back Garden",
                latitude: 49.2827,
                longitude: -123.1207,
                timeZoneIdentifier: "America/Vancouver",
                createdAt: createdAt,
                updatedAt: createdAt
            )
        )
        let savedSnapshot = try store.saveWeatherSnapshot(
            WeatherSnapshot(
                fetchedAt: fetchedAt,
                lastMeaningfulRainDate: createdAt,
                observed7DayRainMM: 9.5,
                forecast48hRainMM: 3.2,
                effective7DayMoistureMM: 9.5,
                deficitMM: 15.9,
                dryDays: 4,
                recommendationRawValue: RecommendationStatus.waterSoon.rawValue,
                isForecastSuppressed: false,
                isStale: false,
                attributionText: "Weather data from Apple Weather.",
                attributionURLString: "https://weatherkit.apple.com/legal-attribution.html"
            )
        )
        let savedEvent = try store.saveManualWaterEvent(
            ManualWaterEvent(
                occurredAt: wateredAt,
                creditedMM: 15.9
            )
        )

        let loadedState = try store.loadAppState()

        #expect(loadedState.gardenProfile?.displayName == savedProfile.displayName)
        #expect(loadedState.weatherSnapshot?.recommendationRawValue == savedSnapshot.recommendationRawValue)
        #expect(loadedState.manualWaterEvents.count == 1)
        #expect(loadedState.manualWaterEvents.first?.creditedMM == savedEvent.creditedMM)
    }

    @Test
    @MainActor
    func storeResetsLocationDependentData() throws {
        let container = DrySpellModelContainer.makePreviewContainer()
        let store = DrySpellStore(modelContext: ModelContext(container))

        _ = try store.saveWeatherSnapshot(
            WeatherSnapshot(
                fetchedAt: .now,
                observed7DayRainMM: 6.3,
                forecast48hRainMM: 1.4,
                dryDays: 3
            )
        )
        _ = try store.saveManualWaterEvent(
            ManualWaterEvent(
                occurredAt: .now,
                creditedMM: 8.0
            )
        )

        try store.resetLocationDependentData()

        #expect(try store.loadLatestWeatherSnapshot() == nil)
        #expect(try store.loadManualWaterEvents().isEmpty)
    }

    @Test
    @MainActor
    func storeRecordsManualWateringAndReevaluatesSnapshot() throws {
        let container = DrySpellModelContainer.makePreviewContainer()
        let store = DrySpellStore(modelContext: ModelContext(container))
        let profile = try store.saveGardenProfile(
            GardenProfile(
                displayName: "Back Garden",
                latitude: 49.2827,
                longitude: -123.1207,
                timeZoneIdentifier: "America/Vancouver",
                dryDayThresholdDays: 5
            )
        )
        let snapshot = try store.saveWeatherSnapshot(
            WeatherSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_713_456_000),
                observed7DayRainMM: 10.0,
                forecast48hRainMM: 0,
                effective7DayMoistureMM: 10.0,
                deficitMM: 15.4,
                dryDays: 6,
                recommendationRawValue: RecommendationStatus.waterSoon.rawValue
            )
        )

        try store.recordManualWatering(
            for: profile,
            weatherSnapshot: snapshot,
            recommendationEngine: RecommendationEngine(),
            now: Date(timeIntervalSince1970: 1_713_456_000)
        )

        let events = try store.loadManualWaterEvents()
        let latestSnapshot = try store.loadLatestWeatherSnapshot()
        let updatedSnapshot = try #require(latestSnapshot)

        #expect(events.count == 1)
        #expect(events[0].creditedMM == 15.4)
        #expect(updatedSnapshot.recommendationRawValue == RecommendationStatus.recentlyWatered.rawValue)
        #expect(updatedSnapshot.deficitMM == 0)
    }

    @Test
    @MainActor
    func storeSavesSettingsAndReevaluatesThresholdChanges() throws {
        let container = DrySpellModelContainer.makePreviewContainer()
        let store = DrySpellStore(modelContext: ModelContext(container))
        let existingProfile = try store.saveGardenProfile(
            GardenProfile(
                displayName: "Back Garden",
                latitude: 49.2827,
                longitude: -123.1207,
                timeZoneIdentifier: "America/Vancouver",
                dryDayThresholdDays: 7
            )
        )
        let snapshot = try store.saveWeatherSnapshot(
            WeatherSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_713_456_000),
                observed7DayRainMM: 8.0,
                forecast48hRainMM: 0,
                effective7DayMoistureMM: 8.0,
                deficitMM: 17.4,
                dryDays: 5,
                recommendationRawValue: RecommendationStatus.okayForNow.rawValue
            )
        )

        _ = try store.saveGardenSettings(
            existingProfile: existingProfile,
            location: ResolvedGardenLocation(
                displayName: "Back Garden",
                latitude: 49.2827,
                longitude: -123.1207,
                timeZoneIdentifier: "America/Vancouver"
            ),
            dryDayThresholdDays: 5,
            notificationsEnabled: false,
            notificationHour: 9,
            weatherSnapshot: snapshot,
            recommendationEngine: RecommendationEngine(),
            now: Date(timeIntervalSince1970: 1_713_456_000)
        )

        let latestSnapshot = try store.loadLatestWeatherSnapshot()
        let updatedSnapshot = try #require(latestSnapshot)

        #expect(updatedSnapshot.recommendationRawValue == RecommendationStatus.waterSoon.rawValue)
    }

    @Test
    func widgetSnapshotStoreRoundTripsCodablePayload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = WidgetSnapshotStore(
            containerURLProvider: { directory },
            reloadTimelines: {}
        )
        let snapshot = WidgetSnapshot(
            statusTitle: "Rain expected",
            statusSubtitle: "Dry 5 days",
            lastMeaningfulRainDate: Date(timeIntervalSince1970: 1_713_369_600),
            dryDays: 5,
            observed7DayRainMM: 12.4,
            forecast48hRainMM: 14.0,
            updatedAt: Date(timeIntervalSince1970: 1_713_456_000),
            isStale: false,
            isUnavailable: false
        )

        try store.write(snapshot)
        let loadedSnapshot = try store.read()

        #expect(loadedSnapshot == snapshot)
    }

    @Test
    func widgetSnapshotMapsRecommendationStateToWidgetCopy() {
        let snapshot = WidgetSnapshot.make(
            hasGardenProfile: true,
            recommendationRawValue: RecommendationStatus.recentlyWatered.rawValue,
            lastMeaningfulRainDate: Date(timeIntervalSince1970: 1_713_369_600),
            dryDays: 5,
            observed7DayRainMM: 8.0,
            forecast48hRainMM: 0.0,
            fetchedAt: Date(timeIntervalSince1970: 1_713_456_000),
            isStale: false,
            isUnavailable: false
        )

        #expect(snapshot.statusTitle == "Okay for now")
        #expect(snapshot.statusSubtitle == "Watered today")
        #expect(snapshot.dryDays == 5)
    }

    @Test
    func widgetSnapshotUsesSetupAndUnavailableFallbacks() {
        let emptySnapshot = WidgetSnapshot.make(
            hasGardenProfile: false,
            recommendationRawValue: nil,
            lastMeaningfulRainDate: nil,
            dryDays: 0,
            observed7DayRainMM: 0,
            forecast48hRainMM: 0,
            fetchedAt: nil,
            isStale: false,
            isUnavailable: false
        )
        let unavailableSnapshot = WidgetSnapshot.make(
            hasGardenProfile: true,
            recommendationRawValue: nil,
            lastMeaningfulRainDate: nil,
            dryDays: 0,
            observed7DayRainMM: 0,
            forecast48hRainMM: 0,
            fetchedAt: nil,
            isStale: false,
            isUnavailable: false
        )

        #expect(emptySnapshot.statusTitle == "Set up in app")
        #expect(unavailableSnapshot.statusTitle == "Weather unavailable")
        #expect(unavailableSnapshot.isUnavailable)
    }

    @Test
    func weatherMetricsUseRecentRainAnd48HourForecast() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        let now = Date(timeIntervalSince1970: 1_713_456_000)

        let daySamples = [
            WeatherDaySample(
                date: calendar.date(byAdding: .day, value: -8, to: now)!,
                precipitationMM: 6.0
            ),
            WeatherDaySample(
                date: calendar.date(byAdding: .day, value: -4, to: now)!,
                precipitationMM: 3.1
            ),
            WeatherDaySample(
                date: calendar.date(byAdding: .day, value: -1, to: now)!,
                precipitationMM: 1.8
            ),
        ]
        let hourSamples = [
            WeatherHourSample(date: now.addingTimeInterval(60 * 60), precipitationMM: 1.2),
            WeatherHourSample(date: now.addingTimeInterval(12 * 60 * 60), precipitationMM: 2.8),
            WeatherHourSample(date: now.addingTimeInterval(50 * 60 * 60), precipitationMM: 9.9),
        ]

        let metrics = WeatherClient.makeMetrics(
            daySamples: daySamples,
            hourSamples: hourSamples,
            now: now,
            calendar: calendar,
            previousLastMeaningfulRainDate: nil
        )

        #expect(metrics.lastMeaningfulRainDate == daySamples[1].date)
        #expect(metrics.observed7DayRainMM == 4.9)
        #expect(metrics.forecast48hRainMM == 4.0)
        #expect(metrics.dryDays == 4)
    }

    @Test
    func weatherMetricsCarryForwardLongDrySpell() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let previousMeaningfulRainDate = calendar.date(byAdding: .day, value: -42, to: now)!
        let drySamples = (0..<30).map { offset in
            WeatherDaySample(
                date: calendar.date(byAdding: .day, value: -offset, to: now)!,
                precipitationMM: 0.4
            )
        }

        let metrics = WeatherClient.makeMetrics(
            daySamples: drySamples,
            hourSamples: [],
            now: now,
            calendar: calendar,
            previousLastMeaningfulRainDate: previousMeaningfulRainDate
        )

        #expect(metrics.lastMeaningfulRainDate == previousMeaningfulRainDate)
        #expect(metrics.dryDays == 42)
        #expect(metrics.observed7DayRainMM == 2.8)
        #expect(metrics.forecast48hRainMM == 0)
    }

    @Test
    func recommendationEngineReturnsSetupNeededWithoutGarden() {
        let engine = RecommendationEngine()

        let result = engine.evaluate(
            gardenProfile: nil,
            weatherSnapshot: nil,
            manualWaterEvents: []
        )

        #expect(result.status == .setupNeeded)
        #expect(result.explanationText == "Add your garden location to get started.")
    }

    @Test
    func recommendationEngineReturnsWeatherUnavailableForTooStaleSnapshot() {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver"
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now.addingTimeInterval(-(25 * 60 * 60)),
            observed7DayRainMM: 5,
            forecast48hRainMM: 2,
            dryDays: 6
        )

        let result = engine.evaluate(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [],
            now: now
        )

        #expect(result.status == .weatherUnavailable)
        #expect(result.isUnavailable)
    }

    @Test
    func recommendationEngineReturnsLastKnownStatusWhenStaleButUsable() {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            dryDayThresholdDays: 5
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now.addingTimeInterval(-(7 * 60 * 60)),
            observed7DayRainMM: 9,
            forecast48hRainMM: 0,
            dryDays: 5
        )

        let result = engine.evaluate(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [],
            now: now
        )

        #expect(result.status == .waterSoon)
        #expect(result.freshness == .stale)
        #expect(!result.isUnavailable)
    }

    @Test
    func recommendationEngineReturnsWaterSoonAtExactDryThreshold() {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            dryDayThresholdDays: 5
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now,
            observed7DayRainMM: 12.0,
            forecast48hRainMM: 0,
            dryDays: 5
        )

        let result = engine.evaluate(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [],
            now: now
        )

        #expect(result.status == .waterSoon)
    }

    @Test
    func recommendationEngineReturnsOkayBelowDryThreshold() {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            dryDayThresholdDays: 5
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now,
            observed7DayRainMM: 8.0,
            forecast48hRainMM: 0,
            dryDays: 4
        )

        let result = engine.evaluate(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [],
            now: now
        )

        #expect(result.status == .okayForNow)
    }

    @Test
    func weatherMetricsResetDryStreakAfterMeaningfulRain() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let daySamples = [
            WeatherDaySample(
                date: now,
                precipitationMM: 3.0
            ),
            WeatherDaySample(
                date: calendar.date(byAdding: .day, value: -1, to: now)!,
                precipitationMM: 0.8
            ),
        ]

        let metrics = WeatherClient.makeMetrics(
            daySamples: daySamples,
            hourSamples: [],
            now: now,
            calendar: calendar,
            previousLastMeaningfulRainDate: nil
        )

        #expect(metrics.dryDays == 0)
        #expect(metrics.lastMeaningfulRainDate == daySamples[0].date)
    }

    @Test
    func recommendationEngineRespectsPriorityAndForecastSuppression() {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            dryDayThresholdDays: 5
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now,
            observed7DayRainMM: 10,
            forecast48hRainMM: 16,
            dryDays: 5
        )

        let rainExpected = engine.evaluate(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [],
            now: now,
            calendar: calendar
        )

        #expect(rainExpected.status == .rainExpected)
        #expect(rainExpected.forecastSuppressed)

        let wateredToday = engine.evaluate(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [
                ManualWaterEvent(occurredAt: now, creditedMM: 15.4)
            ],
            now: now,
            calendar: calendar
        )

        #expect(wateredToday.status == .recentlyWatered)
        #expect(wateredToday.explanationText == "You marked watered today.")
    }

    @Test
    func nextFreshnessTransitionReturnsSixHourBoundaryForFreshSnapshot() throws {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let snapshot = WeatherSnapshot(
            fetchedAt: now.addingTimeInterval(-(2 * 60 * 60)),
            observed7DayRainMM: 8,
            forecast48hRainMM: 0,
            dryDays: 5
        )

        let nextTransition = try #require(
            engine.nextFreshnessTransitionDate(for: snapshot, now: now)
        )

        #expect(nextTransition == snapshot.fetchedAt.addingTimeInterval(6 * 60 * 60))
    }

    @Test
    func nextFreshnessTransitionReturnsDayBoundaryForStaleSnapshot() throws {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let snapshot = WeatherSnapshot(
            fetchedAt: now.addingTimeInterval(-(8 * 60 * 60)),
            observed7DayRainMM: 8,
            forecast48hRainMM: 0,
            dryDays: 5
        )

        let nextTransition = try #require(
            engine.nextFreshnessTransitionDate(for: snapshot, now: now)
        )

        #expect(nextTransition == snapshot.fetchedAt.addingTimeInterval(24 * 60 * 60))
    }

    @Test
    func submitNextRefreshCancelsExistingRequestBeforeSubmitting() throws {
        let schedulerSpy = BackgroundRefreshSchedulingSpy()
        let scheduler = BackgroundRefreshScheduler(scheduler: schedulerSpy)

        scheduler.submitNextRefresh(after: 2 * 60 * 60)

        let request = try #require(schedulerSpy.submittedRequests.first as? BGAppRefreshTaskRequest)

        #expect(schedulerSpy.cancelledIdentifiers == [DrySpellConstants.backgroundRefreshTaskIdentifier])
        #expect(schedulerSpy.submittedRequests.count == 1)
        #expect(request.identifier == DrySpellConstants.backgroundRefreshTaskIdentifier)
        #expect(request.earliestBeginDate != nil)
    }

    @Test
    func notificationSchedulerSchedulesWhenEligible() async throws {
        let centerClient = NotificationCenterClientSpy(authorizationStatus: .authorized)
        let scheduler = NotificationScheduler(centerClient: centerClient)
        let now = Date(timeIntervalSince1970: 1_713_429_000) // 2024-04-18 08:30 PDT
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            dryDayThresholdDays: 5,
            notificationsEnabled: true,
            notificationHour: 9
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now,
            observed7DayRainMM: 8,
            forecast48hRainMM: 0,
            dryDays: 5
        )

        try await scheduler.syncReminder(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [],
            now: now
        )

        let removed = await centerClient.removedIdentifiers
        let addedRequests = await centerClient.addedRequests
        let request = try #require(addedRequests.first)

        #expect(removed == [[DrySpellConstants.wateringReminderIdentifier]])
        #expect(addedRequests.count == 1)
        #expect(request.identifier == DrySpellConstants.wateringReminderIdentifier)
        #expect(request.title == "Water soon")
        #expect(request.dateComponents.hour == 9)
        #expect(request.dateComponents.minute == 0)
        #expect(request.dateComponents.timeZone?.identifier == "America/Vancouver")
    }

    @Test
    func notificationSchedulerDoesNotScheduleWhenStale() async throws {
        let centerClient = NotificationCenterClientSpy(authorizationStatus: .authorized)
        let scheduler = NotificationScheduler(centerClient: centerClient)
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            dryDayThresholdDays: 5,
            notificationsEnabled: true,
            notificationHour: 9
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now.addingTimeInterval(-(7 * 60 * 60)),
            observed7DayRainMM: 8,
            forecast48hRainMM: 0,
            dryDays: 5
        )

        try await scheduler.syncReminder(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [],
            now: now
        )

        #expect(await centerClient.addedRequests.isEmpty)
        #expect(await centerClient.removedIdentifiers == [[DrySpellConstants.wateringReminderIdentifier]])
    }

    @Test
    func notificationSchedulerDoesNotScheduleWhenForecastSuppressed() async throws {
        let centerClient = NotificationCenterClientSpy(authorizationStatus: .authorized)
        let scheduler = NotificationScheduler(centerClient: centerClient)
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            dryDayThresholdDays: 5,
            notificationsEnabled: true,
            notificationHour: 9
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now,
            observed7DayRainMM: 20,
            forecast48hRainMM: 10,
            dryDays: 5
        )

        try await scheduler.syncReminder(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [],
            now: now
        )

        #expect(await centerClient.addedRequests.isEmpty)
        #expect(await centerClient.removedIdentifiers == [[DrySpellConstants.wateringReminderIdentifier]])
    }

    @Test
    func notificationSchedulerCancelsAfterManualWatering() async throws {
        let centerClient = NotificationCenterClientSpy(authorizationStatus: .authorized)
        let scheduler = NotificationScheduler(centerClient: centerClient)
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            dryDayThresholdDays: 5,
            notificationsEnabled: true,
            notificationHour: 9
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now,
            observed7DayRainMM: 8,
            forecast48hRainMM: 0,
            dryDays: 5
        )

        try await scheduler.syncReminder(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [ManualWaterEvent(occurredAt: now, creditedMM: 17.4)],
            now: now
        )

        #expect(await centerClient.addedRequests.isEmpty)
        #expect(await centerClient.removedIdentifiers == [[DrySpellConstants.wateringReminderIdentifier]])
    }

    @Test
    func notificationSchedulerCancelsAfterDisablingReminders() async throws {
        let centerClient = NotificationCenterClientSpy(authorizationStatus: .authorized)
        let scheduler = NotificationScheduler(centerClient: centerClient)
        let now = Date(timeIntervalSince1970: 1_713_456_000)
        let profile = GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            dryDayThresholdDays: 5,
            notificationsEnabled: false,
            notificationHour: 9
        )
        let snapshot = WeatherSnapshot(
            fetchedAt: now,
            observed7DayRainMM: 8,
            forecast48hRainMM: 0,
            dryDays: 5
        )

        try await scheduler.syncReminder(
            gardenProfile: profile,
            weatherSnapshot: snapshot,
            manualWaterEvents: [],
            now: now
        )

        #expect(await centerClient.addedRequests.isEmpty)
        #expect(await centerClient.removedIdentifiers == [[DrySpellConstants.wateringReminderIdentifier]])
    }

}

private actor NotificationCenterClientSpy: UserNotificationCenterClient {
    private(set) var addedRequests: [ScheduledNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []
    private let status: UNAuthorizationStatus

    init(authorizationStatus: UNAuthorizationStatus) {
        self.status = authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        status == .authorized
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func add(_ request: ScheduledNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        removedIdentifiers.append(identifiers)
    }
}

private final class BackgroundRefreshSchedulingSpy: BackgroundRefreshScheduling {
    private(set) var submittedRequests: [BGTaskRequest] = []
    private(set) var cancelledIdentifiers: [String] = []

    func submit(_ request: BGTaskRequest) throws {
        submittedRequests.append(request)
    }

    func cancel(taskRequestWithIdentifier identifier: String) {
        cancelledIdentifiers.append(identifier)
    }
}
