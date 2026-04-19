import SwiftUI
import SwiftData

@main
struct DrySpellApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let modelContainer = DrySpellModelContainer.shared

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
        .backgroundTask(.appRefresh(DrySpellConstants.backgroundRefreshTaskIdentifier)) {
            await BackgroundRefreshScheduler().handleAppRefresh(modelContainer: modelContainer)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active || phase == .background else {
                return
            }

            BackgroundRefreshScheduler().submitNextRefresh()

            guard phase == .active else {
                return
            }

            Task { @MainActor in
                await ReminderStateResynchronizer().syncCurrentReminder(
                    modelContainer: modelContainer,
                    now: .now
                )
            }
        }
    }
}
