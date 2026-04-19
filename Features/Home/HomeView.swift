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
    @State private var isShowingAttributionDetails = false
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

    private let contentMaxWidth: CGFloat = 760

    var body: some View {
        Group {
            if let gardenProfile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        recommendationHeader(for: gardenProfile)
                        metricsSection(for: gardenProfile)
                        explanationSection

                        if let weatherRefreshError {
                            weatherIssueBanner(weatherRefreshError)
                        }

                        attributionSection
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .refreshable {
                    await refreshWeather(for: gardenProfile)
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
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let gardenProfile {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await refreshWeather(for: gardenProfile)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshingWeather)
                    .accessibilityLabel(isRefreshingWeather ? "Refreshing weather" : "Refresh weather")
                    .accessibilityHint("Fetches the latest weather for your saved garden.")

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Open settings")
                    .accessibilityHint("Edits your saved location, threshold, reminders, and attribution.")
                }
            }
        }
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
            HStack(alignment: .top, spacing: 16) {
                Label(display.badgeTitle, systemImage: display.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(display.badgeColor)
                    .accessibilityLabel(display.badgeTitle)

                Spacer(minLength: 0)

                if let weatherSnapshot {
                    Text(updatedText(for: weatherSnapshot))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } else if isRefreshingWeather {
                    Label("Refreshing weather...", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text(display.title)
                .font(.largeTitle.weight(.bold))

            Text(display.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await markWatered(for: gardenProfile)
                }
            } label: {
                HStack {
                    if isMarkingWatered {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }

                    Text(wateredToday(for: gardenProfile) ? "Watered Today" : "Mark Watered")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canMarkWatered || wateredToday(for: gardenProfile) || isMarkingWatered)
            .accessibilityHint("Records that you've already watered today.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    display.badgeColor.opacity(0.16),
                    display.badgeColor.opacity(0.04),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .glassEffect(.regular.tint(display.badgeColor.opacity(0.08)), in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func metricsSection(for gardenProfile: GardenProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Conditions")
                    .font(.headline)

                Text("Observed rain, forecast, and your saved threshold.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 16) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(conditionMetrics(for: gardenProfile)) { metric in
                        ConditionMetricCard(metric: metric)
                    }
                }
            }
        }
    }

    private var explanationSection: some View {
        GroupBox {
            Text(explanationText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
        } label: {
            Text("Recommendation")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var attributionSection: some View {
        if let weatherSnapshot, !weatherSnapshot.attributionText.isEmpty {
            GroupBox {
                DisclosureGroup("Weather Attribution", isExpanded: $isShowingAttributionDetails) {
                    VStack(alignment: .leading, spacing: 12) {
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
                }
            }
        }
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

    private func conditionMetrics(for gardenProfile: GardenProfile) -> [HomeConditionMetric] {
        [
            HomeConditionMetric(
                title: "Last Meaningful Rain",
                value: lastMeaningfulRainText,
                detail: lastMeaningfulRainDateText,
                symbolName: "cloud.rain",
                tint: .blue
            ),
            HomeConditionMetric(
                title: "Observed 7-Day Rain",
                value: measurementText(weatherSnapshot?.observed7DayRainMM ?? 0),
                symbolName: "chart.bar.xaxis",
                tint: .teal
            ),
            HomeConditionMetric(
                title: "Forecast Next 48 Hours",
                value: measurementText(weatherSnapshot?.forecast48hRainMM ?? 0),
                symbolName: "cloud.drizzle",
                tint: .indigo
            ),
            HomeConditionMetric(
                title: "Weekly Target",
                value: measurementText(DrySpellConstants.defaultWeeklyWaterTargetMM),
                symbolName: "drop.circle",
                tint: .cyan
            ),
            HomeConditionMetric(
                title: "Dry-Day Threshold",
                value: "\(gardenProfile.dryDayThresholdDays) days",
                symbolName: "sun.max",
                tint: .orange
            ),
        ]
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

    private func weatherIssueBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityLabel("Weather refresh issue. \(message)")
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

private struct HomeConditionMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String?
    let symbolName: String
    let tint: Color

    init(title: String, value: String, detail: String? = nil, symbolName: String, tint: Color) {
        self.title = title
        self.value = value
        self.detail = detail
        self.symbolName = symbolName
        self.tint = tint
    }
}

private struct ConditionMetricCard: View {
    let metric: HomeConditionMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: metric.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.tint)

            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(metric.value)
                .font(.title3.weight(.semibold))

            if let detail = metric.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    metric.tint.opacity(0.14),
                    metric.tint.opacity(0.04),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .glassEffect(.regular.tint(metric.tint.opacity(0.08)), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([metric.title, metric.value, metric.detail].compactMap { $0 }.joined(separator: ", "))
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
