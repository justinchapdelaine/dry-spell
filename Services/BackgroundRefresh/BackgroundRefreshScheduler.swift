import BackgroundTasks
import Foundation
import OSLog
import SwiftData

protocol BackgroundRefreshScheduling {
    func submit(_ request: BGTaskRequest) throws
}

extension BGTaskScheduler: BackgroundRefreshScheduling {}

struct BackgroundRefreshScheduler {
    private static let logger = Logger(
        subsystem: "com.justinchapdelaine.dryspell",
        category: "BackgroundRefresh"
    )
    private let scheduler: BackgroundRefreshScheduling
    private let weatherClient: WeatherClient
    private let notificationScheduler: NotificationScheduler

    init(
        scheduler: BackgroundRefreshScheduling = BGTaskScheduler.shared,
        weatherClient: WeatherClient = WeatherClient(),
        notificationScheduler: NotificationScheduler = NotificationScheduler()
    ) {
        self.scheduler = scheduler
        self.weatherClient = weatherClient
        self.notificationScheduler = notificationScheduler
    }

    func submitNextRefresh(
        after interval: TimeInterval = TimeInterval(DrySpellConstants.backgroundRefreshEarliestIntervalHours * 60 * 60)
    ) {
        let request = BGAppRefreshTaskRequest(identifier: DrySpellConstants.backgroundRefreshTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)

        do {
            try scheduler.submit(request)
        } catch {
            Self.logger.error("Failed to submit background refresh request: \(error.localizedDescription, privacy: .public)")
            return
        }
    }

    @MainActor
    func handleAppRefresh(
        modelContainer: ModelContainer,
        now: Date = .now
    ) async {
        defer {
            submitNextRefresh()
        }

        let modelContext = ModelContext(modelContainer)
        let store = DrySpellStore(modelContext: modelContext)

        do {
            let appState = try store.loadAppState()

            guard let gardenProfile = appState.gardenProfile else {
                do {
                    try store.writeWidgetSnapshot(now: now)
                } catch {
                    Self.logger.error("Failed to write widget snapshot during background refresh with no garden profile: \(error.localizedDescription, privacy: .public)")
                }
                await notificationScheduler.cancelReminder()
                return
            }

            do {
                let refreshedSnapshot = try await weatherClient.refreshSnapshot(
                    for: gardenProfile,
                    existingSnapshot: appState.weatherSnapshot,
                    manualWaterEvents: appState.manualWaterEvents
                )
                _ = try store.saveWeatherSnapshot(refreshedSnapshot)
            } catch {
                Self.logger.error("Background weather refresh failed; attempting fallback reevaluation: \(error.localizedDescription, privacy: .public)")
                do {
                    _ = try store.reevaluateWeatherSnapshot(
                        for: gardenProfile,
                        recommendationEngine: RecommendationEngine(),
                        now: now
                    )
                } catch {
                    Self.logger.error("Background fallback reevaluation failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            do {
                try store.writeWidgetSnapshot(now: now)
            } catch {
                Self.logger.error("Failed to write widget snapshot during background refresh: \(error.localizedDescription, privacy: .public)")
            }

            let refreshedState = try store.loadAppState()
            do {
                try await notificationScheduler.syncReminder(
                    gardenProfile: refreshedState.gardenProfile,
                    weatherSnapshot: refreshedState.weatherSnapshot,
                    manualWaterEvents: refreshedState.manualWaterEvents,
                    now: now
                )
            } catch {
                Self.logger.error("Failed to sync reminders during background refresh: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            Self.logger.error("Background refresh aborted because app state could not be loaded: \(error.localizedDescription, privacy: .public)")
            return
        }
    }
}
