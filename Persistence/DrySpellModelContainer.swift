import Foundation
import SwiftData

enum DrySpellModelContainer {
    static let schema = Schema([
        GardenProfile.self,
        WeatherSnapshot.self,
        ManualWaterEvent.self,
    ])

    static let shared: ModelContainer = makeContainer(inMemory: false)
    static let preview: ModelContainer = makeContainer(inMemory: true)

    static func makePreviewContainer() -> ModelContainer {
        makeContainer(inMemory: true)
    }

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let configuration = makeConfiguration(inMemory: inMemory)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let containerKind = inMemory ? "in-memory" : "persistent"
            let storeDescription = inMemory ? "preview container" : persistentStoreURL().path()
            fatalError("Unable to create \(containerKind) ModelContainer for \(storeDescription): \(error)")
        }
    }

    private static func makeConfiguration(inMemory: Bool) -> ModelConfiguration {
        if inMemory {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        }

        let storeURL = persistentStoreURL()
        let directoryURL = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return ModelConfiguration(schema: schema, url: storeURL)
    }

    private static func persistentStoreURL() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupportURL
            .appending(path: "DrySpell", directoryHint: .isDirectory)
            .appending(path: "DrySpell.store")
    }
}

struct DrySpellAppState: Sendable {
    let gardenProfile: GardenProfile?
    let weatherSnapshot: WeatherSnapshot?
    let manualWaterEvents: [ManualWaterEvent]

    static let empty = DrySpellAppState(
        gardenProfile: nil,
        weatherSnapshot: nil,
        manualWaterEvents: []
    )
}

@MainActor
struct DrySpellStore {
    let modelContext: ModelContext

    func seedEmptyAppState() throws -> DrySpellAppState {
        try loadAppState()
    }

    func loadAppState() throws -> DrySpellAppState {
        DrySpellAppState(
            gardenProfile: try loadGardenProfile(),
            weatherSnapshot: try loadLatestWeatherSnapshot(),
            manualWaterEvents: try loadManualWaterEvents()
        )
    }

    func loadGardenProfile() throws -> GardenProfile? {
        var descriptor = FetchDescriptor<GardenProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    func saveGardenProfile(_ profile: GardenProfile) throws -> GardenProfile {
        let savedProfile = try upsertGardenProfile(profile)
        try saveChangesIfNeeded()
        return savedProfile
    }

    func loadLatestWeatherSnapshot() throws -> WeatherSnapshot? {
        var descriptor = FetchDescriptor<WeatherSnapshot>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    func saveWeatherSnapshot(_ snapshot: WeatherSnapshot) throws -> WeatherSnapshot {
        let savedSnapshot = try replaceWeatherSnapshot(snapshot)
        try saveChangesIfNeeded()
        return savedSnapshot
    }

    func loadManualWaterEvents() throws -> [ManualWaterEvent] {
        let descriptor = FetchDescriptor<ManualWaterEvent>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    @discardableResult
    func saveManualWaterEvent(_ event: ManualWaterEvent) throws -> ManualWaterEvent {
        modelContext.insert(event)
        try saveChangesIfNeeded()
        return event
    }

    func recordManualWatering(
        for gardenProfile: GardenProfile,
        weatherSnapshot: WeatherSnapshot,
        recommendationEngine: RecommendationEngine,
        beforeCommit: (() throws -> Void)? = nil,
        now: Date = .now
    ) throws {
        let currentDeficit = min(
            DrySpellConstants.defaultWeeklyWaterTargetMM,
            max(0, weatherSnapshot.deficitMM)
        )
        let existingManualWaterEvents = try loadManualWaterEvents()
        let manualWaterEvent = ManualWaterEvent(
            occurredAt: now,
            creditedMM: currentDeficit
        )
        modelContext.insert(manualWaterEvent)

        do {
            let reevaluatedSnapshot = recommendationEngine.evaluatedSnapshot(
                gardenProfile: gardenProfile,
                weatherSnapshot: weatherSnapshot,
                manualWaterEvents: [manualWaterEvent] + existingManualWaterEvents,
                now: now,
                calendar: calendar(for: gardenProfile.timeZoneIdentifier)
            )
            _ = try replaceWeatherSnapshot(reevaluatedSnapshot)
            try beforeCommit?()
            try saveChangesIfNeeded()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    func saveGardenSettings(
        existingProfile: GardenProfile,
        location: ResolvedGardenLocation,
        dryDayThresholdDays: Int,
        notificationsEnabled: Bool,
        notificationHour: Int,
        weatherSnapshot: WeatherSnapshot?,
        recommendationEngine: RecommendationEngine,
        beforeCommit: (() throws -> Void)? = nil,
        now: Date = .now
    ) throws -> GardenProfile {
        let locationChanged = hasLocationChanged(
            existingProfile: existingProfile,
            location: location
        )
        let thresholdChanged = dryDayThresholdDays != existingProfile.dryDayThresholdDays
        let currentSnapshot = try loadLatestWeatherSnapshot()
        let manualWaterEvents = thresholdChanged && !locationChanged ? try loadManualWaterEvents() : []
        let savedProfile = try upsertGardenProfile(
            GardenProfile(
                id: existingProfile.id,
                displayName: location.displayName,
                latitude: location.latitude,
                longitude: location.longitude,
                timeZoneIdentifier: location.timeZoneIdentifier,
                dryDayThresholdDays: dryDayThresholdDays,
                notificationsEnabled: notificationsEnabled,
                notificationHour: notificationHour,
                createdAt: existingProfile.createdAt,
                updatedAt: now
            )
        )

        if locationChanged {
            try resetLocationDependentData(saveChanges: false)
        } else if thresholdChanged,
                  let currentSnapshot = weatherSnapshot ?? currentSnapshot {
            let reevaluatedSnapshot = recommendationEngine.evaluatedSnapshot(
                gardenProfile: savedProfile,
                weatherSnapshot: currentSnapshot,
                manualWaterEvents: manualWaterEvents,
                now: now,
                calendar: calendar(for: savedProfile.timeZoneIdentifier)
            )
            _ = try replaceWeatherSnapshot(reevaluatedSnapshot)
        }

        try beforeCommit?()
        try saveChangesIfNeeded()
        return savedProfile
    }

    func resetLocationDependentData() throws {
        try resetLocationDependentData(saveChanges: true)
    }

    @discardableResult
    func saveInitialGardenProfileAndWidgetSnapshot(
        _ profile: GardenProfile,
        widgetSnapshotStore: WidgetSnapshotStore? = nil,
        now: Date = .now
    ) throws -> GardenProfile {
        let savedProfile = try saveGardenProfile(profile)
        let widgetSnapshotStore = widgetSnapshotStore ?? WidgetSnapshotStore()

        do {
            try widgetSnapshotStore.writeCurrentAppState(
                DrySpellAppState(
                    gardenProfile: savedProfile,
                    weatherSnapshot: nil,
                    manualWaterEvents: []
                ),
                now: now
            )
            return savedProfile
        } catch {
            modelContext.delete(savedProfile)
            try saveChangesIfNeeded()
            throw error
        }
    }

    private func resetLocationDependentData(saveChanges: Bool) throws {
        for snapshot in try modelContext.fetch(FetchDescriptor<WeatherSnapshot>()) {
            modelContext.delete(snapshot)
        }

        for event in try modelContext.fetch(FetchDescriptor<ManualWaterEvent>()) {
            modelContext.delete(event)
        }

        if saveChanges {
            try saveChangesIfNeeded()
        }
    }

    func writeWidgetSnapshot(
        now: Date = .now
    ) throws {
        let appState = try loadAppState()
        let widgetSnapshotStore = WidgetSnapshotStore()
        try widgetSnapshotStore.writeCurrentAppState(appState, now: now)
    }

    @discardableResult
    func reevaluateWeatherSnapshot(
        for gardenProfile: GardenProfile,
        recommendationEngine: RecommendationEngine,
        now: Date = .now
    ) throws -> WeatherSnapshot? {
        guard let currentSnapshot = try loadLatestWeatherSnapshot() else {
            return nil
        }

        let manualWaterEvents = try loadManualWaterEvents()
        let reevaluatedSnapshot = recommendationEngine.evaluatedSnapshot(
            gardenProfile: gardenProfile,
            weatherSnapshot: currentSnapshot,
            manualWaterEvents: manualWaterEvents,
            now: now,
            calendar: calendar(for: gardenProfile.timeZoneIdentifier)
        )
        return try saveWeatherSnapshot(reevaluatedSnapshot)
    }

    private func saveChangesIfNeeded() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    private func upsertGardenProfile(_ profile: GardenProfile) throws -> GardenProfile {
        let profiles = try modelContext.fetch(FetchDescriptor<GardenProfile>())

        if let existing = profiles.first {
            existing.displayName = profile.displayName
            existing.latitude = profile.latitude
            existing.longitude = profile.longitude
            existing.timeZoneIdentifier = profile.timeZoneIdentifier
            existing.dryDayThresholdDays = profile.dryDayThresholdDays
            existing.notificationsEnabled = profile.notificationsEnabled
            existing.notificationHour = profile.notificationHour
            existing.updatedAt = profile.updatedAt

            for duplicate in profiles.dropFirst() {
                modelContext.delete(duplicate)
            }

            return existing
        }

        modelContext.insert(profile)
        return profile
    }

    private func replaceWeatherSnapshot(_ snapshot: WeatherSnapshot) throws -> WeatherSnapshot {
        let snapshots = try modelContext.fetch(FetchDescriptor<WeatherSnapshot>())

        for existing in snapshots {
            modelContext.delete(existing)
        }

        modelContext.insert(snapshot)
        return snapshot
    }

    private func hasLocationChanged(
        existingProfile: GardenProfile,
        location: ResolvedGardenLocation
    ) -> Bool {
        location.displayName != existingProfile.displayName ||
        location.latitude != existingProfile.latitude ||
        location.longitude != existingProfile.longitude ||
        location.timeZoneIdentifier != existingProfile.timeZoneIdentifier
    }

    private func calendar(for timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }
}
