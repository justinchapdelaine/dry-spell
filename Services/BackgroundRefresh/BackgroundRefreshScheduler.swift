import BackgroundTasks
import Foundation
import SwiftData

protocol BackgroundRefreshScheduling {
    func submit(_ request: BGTaskRequest) throws
    func cancel(taskRequestWithIdentifier identifier: String)
}

extension BGTaskScheduler: BackgroundRefreshScheduling {}

struct BackgroundRefreshScheduler {
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

        scheduler.cancel(taskRequestWithIdentifier: DrySpellConstants.backgroundRefreshTaskIdentifier)

        do {
            try scheduler.submit(request)
        } catch {
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
                try? store.writeWidgetSnapshot(now: now)
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
                _ = try? store.reevaluateWeatherSnapshot(
                    for: gardenProfile,
                    recommendationEngine: RecommendationEngine(),
                    now: now
                )
            }

            try? store.writeWidgetSnapshot(now: now)

            let refreshedState = try store.loadAppState()
            try? await notificationScheduler.syncReminder(
                gardenProfile: refreshedState.gardenProfile,
                weatherSnapshot: refreshedState.weatherSnapshot,
                manualWaterEvents: refreshedState.manualWaterEvents,
                now: now
            )
        } catch {
            return
        }
    }
}
