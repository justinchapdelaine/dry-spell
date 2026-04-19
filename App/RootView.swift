import SwiftUI
import SwiftData
import OSLog

struct RootView: View {
    var body: some View {
        NavigationStack {
            RootContentView()
        }
    }
}

private struct RootContentView: View {
    private static let logger = Logger(
        subsystem: "com.justinchapdelaine.dryspell",
        category: "RootView"
    )
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GardenProfile.createdAt) private var gardenProfiles: [GardenProfile]

    var body: some View {
        Group {
            if gardenProfiles.first == nil {
                OnboardingView()
            } else {
                HomeView()
            }
        }
        .task(id: gardenProfiles.first?.updatedAt) {
            let store = DrySpellStore(modelContext: modelContext)
            do {
                try store.writeWidgetSnapshot(now: .now)
            } catch {
                Self.logger.error("Failed to sync widget snapshot from root view: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(DrySpellModelContainer.preview)
}
