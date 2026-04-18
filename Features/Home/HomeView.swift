import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GardenProfile.createdAt) private var gardenProfiles: [GardenProfile]
    @Query(sort: \WeatherSnapshot.fetchedAt, order: .reverse) private var weatherSnapshots: [WeatherSnapshot]
    @Query(sort: \ManualWaterEvent.occurredAt, order: .reverse) private var manualWaterEvents: [ManualWaterEvent]

    @State private var isRefreshingWeather = false
    @State private var isMarkingWatered = false
    @State private var isShowingSettings = false
    @State private var weatherRefreshError: String?
    @State private var activeAlert: HomeAlert?

    private let recommendationEngine = RecommendationEngine()
    private let notificationScheduler = NotificationScheduler()
    private let backgroundRefreshScheduler = BackgroundRefreshScheduler()

    private var gardenProfile: GardenProfile? {
        gardenProfiles.first
    }

    private var weatherSnapshot: WeatherSnapshot? {
        weatherSnapshots.first
    }

    var body: some View {
        Group {
            if let gardenProfile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        recommendationHeader(for: gardenProfile)
                        metricsSection(for: gardenProfile)
                        explanationSection
                        attributionSection
                        actionsSection(for: gardenProfile)

                        if let weatherRefreshError {
                            Label(weatherRefreshError, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("Weather refresh issue. \(weatherRefreshError)")
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Set up your garden",
                    systemImage: "location.slash",
                    description: Text("Choose one garden location to start tracking rain, recommendations, reminders, and the widget.")
                )
            }
        }
        .navigationTitle("Dry Spell")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingSettings) {
            if let gardenProfile {
                SettingsView(
                    gardenProfile: gardenProfile,
                    weatherSnapshot: weatherSnapshot
                )
            }
        }
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task(id: gardenProfile?.updatedAt) {
            guard let gardenProfile else {
                return
            }

            if shouldRefreshWeatherSnapshot(currentSnapshot: weatherSnapshot) {
                await refreshWeather(for: gardenProfile)
            } else {
                _ = try? DrySpellStore(modelContext: modelContext).reevaluateWeatherSnapshot(
                    for: gardenProfile,
                    recommendationEngine: recommendationEngine,
                    now: .now
                )
                await syncReminders()
            }
        }
        .task(id: weatherSnapshot?.fetchedAt) {
            guard let gardenProfile else {
                return
            }

            await monitorFreshnessTransitions(for: gardenProfile)
        }
    }

    @ViewBuilder
    private func recommendationHeader(for gardenProfile: GardenProfile) -> some View {
        let display = recommendationDisplay(for: gardenProfile)

        VStack(alignment: .leading, spacing: 12) {
            Label(display.badgeTitle, systemImage: display.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(display.badgeColor)
                .accessibilityLabel(display.badgeTitle)

            Text(display.title)
                .font(.largeTitle.weight(.bold))

            Text(display.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)

            if let weatherSnapshot {
                Text(updatedText(for: weatherSnapshot))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if isRefreshingWeather {
                Label("Refreshing weather...", systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func metricsSection(for gardenProfile: GardenProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rain and Moisture")
                .font(.headline)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    MetricRow(
                        title: "Last Meaningful Rain",
                        value: lastMeaningfulRainText
                    )

                    if let lastMeaningfulRainDateText {
                        Text(lastMeaningfulRainDateText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Last meaningful rain date, \(lastMeaningfulRainDateText)")
                    }
                }
                MetricRow(
                    title: "Observed 7-Day Rain",
                    value: measurementText(weatherSnapshot?.observed7DayRainMM ?? 0)
                )
                MetricRow(
                    title: "Forecast Next 48 Hours",
                    value: measurementText(weatherSnapshot?.forecast48hRainMM ?? 0)
                )
                MetricRow(
                    title: "Weekly Target",
                    value: measurementText(DrySpellConstants.defaultWeeklyWaterTargetMM)
                )
                MetricRow(
                    title: "Dry-Day Threshold",
                    value: "\(gardenProfile.dryDayThresholdDays) days"
                )
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendation")
                .font(.headline)

            Text(explanationText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var attributionSection: some View {
        if let weatherSnapshot, !weatherSnapshot.attributionText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weather Attribution")
                    .font(.headline)

                Text(weatherSnapshot.attributionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let attributionURL = URL(string: weatherSnapshot.attributionURLString) {
                    Link("Open Legal Attribution", destination: attributionURL)
                        .font(.footnote.weight(.semibold))
                        .accessibilityHint("Opens Apple Weather attribution details.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private func actionsSection(for gardenProfile: GardenProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            Button {
                Task {
                    await markWatered(for: gardenProfile)
                }
            } label: {
                HStack {
                    if isMarkingWatered {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }

                    Text(wateredToday(for: gardenProfile) ? "Watered Today" : "Mark Watered")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canMarkWatered || wateredToday(for: gardenProfile) || isMarkingWatered)
            .accessibilityHint("Records that you've already watered today.")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    secondaryActionButtons(for: gardenProfile)
                }

                VStack(spacing: 12) {
                    secondaryActionButtons(for: gardenProfile)
                }
            }
        }
    }

    @ViewBuilder
    private func secondaryActionButtons(for gardenProfile: GardenProfile) -> some View {
        Button {
            Task {
                await refreshWeather(for: gardenProfile)
            }
        } label: {
            Label(
                isRefreshingWeather ? "Refreshing..." : "Refresh Weather",
                systemImage: "arrow.clockwise"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(isRefreshingWeather)
        .accessibilityHint("Fetches the latest weather for your saved garden.")

        Button {
            isShowingSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Edits your saved location, threshold, reminders, and attribution.")
    }

    private func shouldRefreshWeatherSnapshot(currentSnapshot: WeatherSnapshot?) -> Bool {
        guard let currentSnapshot else {
            return true
        }

        return Date().timeIntervalSince(currentSnapshot.fetchedAt) >= 6 * 60 * 60
    }

    @MainActor
    private func refreshWeather(for gardenProfile: GardenProfile) async {
        isRefreshingWeather = true
        weatherRefreshError = nil
        defer { isRefreshingWeather = false }

        do {
            let weatherClient = WeatherClient()
            let snapshot = try await weatherClient.refreshSnapshot(
                for: gardenProfile,
                existingSnapshot: weatherSnapshot,
                manualWaterEvents: manualWaterEvents
            )
            let store = DrySpellStore(modelContext: modelContext)
            _ = try store.saveWeatherSnapshot(snapshot)
            try store.writeWidgetSnapshot(now: snapshot.fetchedAt)
            backgroundRefreshScheduler.submitNextRefresh()
        } catch {
            await notificationScheduler.cancelReminder()
            let store = DrySpellStore(modelContext: modelContext)
            _ = try? store.reevaluateWeatherSnapshot(
                for: gardenProfile,
                recommendationEngine: recommendationEngine,
                now: .now
            )
            try? store.writeWidgetSnapshot(now: .now)
            weatherRefreshError = "Couldn't refresh weather right now. Dry Spell is showing the last known status if it's still usable."
            return
        }

        do {
            let store = DrySpellStore(modelContext: modelContext)
            try await syncReminders(using: store, now: .now)
        } catch {
            weatherRefreshError = "Weather updated, but Dry Spell couldn't refresh the reminder schedule."
        }
    }

    @MainActor
    private func markWatered(for gardenProfile: GardenProfile) async {
        guard let weatherSnapshot, canMarkWatered else {
            activeAlert = HomeAlert(
                title: "Weather Update Needed",
                message: "Refresh weather before marking watered so Dry Spell can apply the correct watering credit."
            )
            return
        }

        isMarkingWatered = true
        defer { isMarkingWatered = false }

        do {
            let now = Date()
            let store = DrySpellStore(modelContext: modelContext)
            try store.recordManualWatering(
                for: gardenProfile,
                weatherSnapshot: weatherSnapshot,
                recommendationEngine: recommendationEngine,
                now: now
            )
            try store.writeWidgetSnapshot(now: now)
            backgroundRefreshScheduler.submitNextRefresh()
        } catch {
            activeAlert = HomeAlert(
                title: "Couldn't Save Watering",
                message: error.localizedDescription
            )
            return
        }

        do {
            let store = DrySpellStore(modelContext: modelContext)
            try await syncReminders(using: store, now: .now)
        } catch {
            activeAlert = HomeAlert(
                title: "Watering Saved",
                message: "Dry Spell saved your watering update, but it couldn't update the reminder schedule."
            )
        }
    }

    @MainActor
    private func syncReminders() async {
        do {
            let store = DrySpellStore(modelContext: modelContext)
            try await syncReminders(using: store, now: .now)
        } catch {
            weatherRefreshError = "Dry Spell couldn't update the reminder schedule."
        }
    }

    @MainActor
    private func syncReminders(using store: DrySpellStore, now: Date) async throws {
        let appState = try store.loadAppState()
        try await notificationScheduler.syncReminder(
            gardenProfile: appState.gardenProfile,
            weatherSnapshot: appState.weatherSnapshot,
            manualWaterEvents: appState.manualWaterEvents,
            now: now
        )
    }

    private func recommendationDisplay(for gardenProfile: GardenProfile) -> RecommendationDisplay {
        guard let weatherSnapshot else {
            return RecommendationDisplay(
                title: "Weather update needed",
                subtitle: "Dry Spell is waiting on fresh weather for \(gardenProfile.displayName).",
                badgeTitle: "Weather unavailable",
                symbolName: "icloud.slash",
                badgeColor: .orange
            )
        }

        let status = RecommendationStatus(rawValue: weatherSnapshot.recommendationRawValue) ?? .weatherUnavailable

        switch status {
        case .setupNeeded:
            return RecommendationDisplay(
                title: "Set up your garden",
                subtitle: "Add a saved location to start tracking rainfall.",
                badgeTitle: "Setup needed",
                symbolName: "location.slash",
                badgeColor: .secondary
            )
        case .weatherUnavailable:
            return RecommendationDisplay(
                title: "Weather update needed",
                subtitle: "Dry Spell can’t make a fresh watering call right now.",
                badgeTitle: "Weather unavailable",
                symbolName: "icloud.slash",
                badgeColor: .orange
            )
        case .recentlyWatered:
            return RecommendationDisplay(
                title: "Recently watered",
                subtitle: "Dry Spell will treat today as covered.",
                badgeTitle: "Watered today",
                symbolName: "checkmark.circle.fill",
                badgeColor: .green
            )
        case .rainExpected:
            return RecommendationDisplay(
                title: "Rain expected",
                subtitle: "Enough rain is forecast soon, so you can hold off.",
                badgeTitle: "Hold off watering",
                symbolName: "cloud.rain.fill",
                badgeColor: .blue
            )
        case .waterSoon:
            return RecommendationDisplay(
                title: "Water soon",
                subtitle: "It has been dry and the forecast doesn't cover the deficit.",
                badgeTitle: "Watering recommended",
                symbolName: "drop.fill",
                badgeColor: .teal
            )
        case .okayForNow:
            return RecommendationDisplay(
                title: "Okay for now",
                subtitle: "Recent moisture is keeping the garden on track.",
                badgeTitle: "No action needed",
                symbolName: "leaf.fill",
                badgeColor: .green
            )
        }
    }

    private func wateredToday(for gardenProfile: GardenProfile) -> Bool {
        recommendationEngine.userWateredToday(
            manualWaterEvents: manualWaterEvents,
            now: .now,
            calendar: calendar(for: gardenProfile.timeZoneIdentifier)
        )
    }

    private var canMarkWatered: Bool {
        recommendationEngine.canApplyManualWatering(using: weatherSnapshot, now: .now)
    }

    private var lastMeaningfulRainText: String {
        guard let weatherSnapshot else {
            return "Waiting for weather"
        }

        guard weatherSnapshot.lastMeaningfulRainDate != nil else {
            return weatherSnapshot.dryDays > 0 ? "More than \(weatherSnapshot.dryDays) days ago" : "No recent rain found"
        }

        return "\(weatherSnapshot.dryDays) days ago"
    }

    private var lastMeaningfulRainDateText: String? {
        guard let lastMeaningfulRainDate = weatherSnapshot?.lastMeaningfulRainDate else {
            return nil
        }

        return lastMeaningfulRainDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var explanationText: String {
        if let weatherSnapshot, !weatherSnapshot.explanationText.isEmpty {
            return weatherSnapshot.explanationText
        }

        return "Dry Spell will show a recommendation here after the next weather update."
    }

    private func measurementText(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) mm"
    }

    private func updatedText(for weatherSnapshot: WeatherSnapshot) -> String {
        let statusSuffix: String

        if weatherSnapshot.isUnavailable {
            statusSuffix = "Weather unavailable"
        } else if weatherSnapshot.isStale {
            statusSuffix = "Stale"
        } else {
            statusSuffix = "Fresh"
        }

        return "Updated \(weatherSnapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)) · \(statusSuffix)"
    }

    @MainActor
    private func monitorFreshnessTransitions(for gardenProfile: GardenProfile) async {
        while !Task.isCancelled {
            guard let snapshot = weatherSnapshot else {
                return
            }

            guard let nextTransition = recommendationEngine.nextFreshnessTransitionDate(
                for: snapshot,
                now: .now
            ) else {
                return
            }

            let interval = nextTransition.timeIntervalSinceNow

            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }

            guard !Task.isCancelled else {
                return
            }

            do {
                let now = Date()
                let store = DrySpellStore(modelContext: modelContext)
                _ = try store.reevaluateWeatherSnapshot(
                    for: gardenProfile,
                    recommendationEngine: recommendationEngine,
                    now: now
                )
                try store.writeWidgetSnapshot(now: now)
                try await syncReminders(using: store, now: now)
            } catch {
                weatherRefreshError = "Dry Spell couldn't update weather freshness state."
                return
            }
        }
    }

    private func calendar(for timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }
}

private struct RecommendationDisplay {
    let title: String
    let subtitle: String
    let badgeTitle: String
    let symbolName: String
    let badgeColor: Color
}

private struct MetricRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(value)")
    }
}

private struct HomeAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    HomeView()
        .modelContainer(DrySpellModelContainer.preview)
}
