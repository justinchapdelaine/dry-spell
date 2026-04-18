import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        NavigationStack {
            RootContentView()
        }
    }
}

private struct RootContentView: View {
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
            try? store.writeWidgetSnapshot(now: .now)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(DrySpellModelContainer.preview)
}
