import Foundation
import WidgetKit

enum WidgetSnapshotStoreError: Error {
    case missingAppGroupContainer
}

struct WidgetSnapshotStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let containerURLProvider: @Sendable () -> URL?
    private let reloadTimelines: @Sendable () -> Void

    init(
        fileManager: FileManager = .default,
        containerURLProvider: @escaping @Sendable () -> URL? = {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: DrySpellConstants.appGroupIdentifier
            )
        },
        reloadTimelines: @escaping @Sendable () -> Void = {
            WidgetCenter.shared.reloadAllTimelines()
        }
    ) {
        self.fileManager = fileManager
        self.containerURLProvider = containerURLProvider
        self.reloadTimelines = reloadTimelines

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func read() throws -> WidgetSnapshot? {
        let fileURL = try snapshotFileURL()

        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }

    func write(_ snapshot: WidgetSnapshot) throws {
        let fileURL = try snapshotFileURL()
        let data = try encoder.encode(snapshot)

        try data.write(to: fileURL, options: .atomic)
        reloadTimelines()
    }

    func writeCurrentAppState(_ appState: DrySpellAppState, now: Date = .now) throws {
        try write(
            WidgetSnapshot.make(
                hasGardenProfile: appState.gardenProfile != nil,
                recommendationRawValue: appState.weatherSnapshot?.recommendationRawValue,
                lastMeaningfulRainDate: appState.weatherSnapshot?.lastMeaningfulRainDate,
                dryDays: appState.weatherSnapshot?.dryDays ?? 0,
                observed7DayRainMM: appState.weatherSnapshot?.observed7DayRainMM ?? 0,
                forecast48hRainMM: appState.weatherSnapshot?.forecast48hRainMM ?? 0,
                fetchedAt: appState.weatherSnapshot?.fetchedAt,
                isStale: appState.weatherSnapshot?.isStale ?? false,
                isUnavailable: appState.weatherSnapshot?.isUnavailable ?? false
            )
        )
    }

    static func previewSnapshot() -> WidgetSnapshot {
        .preview
    }

    private func snapshotFileURL() throws -> URL {
        guard let containerURL = containerURLProvider() else {
            throw WidgetSnapshotStoreError.missingAppGroupContainer
        }

        return containerURL.appending(path: DrySpellConstants.widgetSnapshotFilename, directoryHint: .notDirectory)
    }
}
