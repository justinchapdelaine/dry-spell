import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let gardenProfile: GardenProfile
    let weatherSnapshot: WeatherSnapshot?

    @State private var draftLocation: ResolvedGardenLocation
    @State private var dryDayThresholdDays: Int
    @State private var notificationsEnabled: Bool
    @State private var notificationHour: Int
    @State private var isShowingLocationPicker = false
    @State private var isSaving = false
    @State private var activeAlert: SettingsAlert?

    private let notificationAuthorizationService = NotificationAuthorizationService()
    private let notificationScheduler = NotificationScheduler()
    private let backgroundRefreshScheduler = BackgroundRefreshScheduler()

    init(gardenProfile: GardenProfile, weatherSnapshot: WeatherSnapshot?) {
        self.gardenProfile = gardenProfile
        self.weatherSnapshot = weatherSnapshot
        _draftLocation = State(
            initialValue: ResolvedGardenLocation(
                displayName: gardenProfile.displayName,
                latitude: gardenProfile.latitude,
                longitude: gardenProfile.longitude,
                timeZoneIdentifier: gardenProfile.timeZoneIdentifier
            )
        )
        _dryDayThresholdDays = State(initialValue: gardenProfile.dryDayThresholdDays)
        _notificationsEnabled = State(initialValue: gardenProfile.notificationsEnabled)
        _notificationHour = State(initialValue: gardenProfile.notificationHour)
    }

    private var hasChanges: Bool {
        draftLocation.displayName != gardenProfile.displayName ||
        draftLocation.latitude != gardenProfile.latitude ||
        draftLocation.longitude != gardenProfile.longitude ||
        draftLocation.timeZoneIdentifier != gardenProfile.timeZoneIdentifier ||
        dryDayThresholdDays != gardenProfile.dryDayThresholdDays ||
        notificationsEnabled != gardenProfile.notificationsEnabled ||
        notificationHour != gardenProfile.notificationHour
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Saved Location", value: draftLocation.displayName)
                    LabeledContent("Time Zone", value: draftLocation.timeZoneIdentifier)

                    Button("Change Location") {
                        isShowingLocationPicker = true
                    }

                    Picker("Dry-Day Threshold", selection: $dryDayThresholdDays) {
                        ForEach(DrySpellConstants.allowedDryDayThresholds, id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Garden", systemImage: "leaf")
                } footer: {
                    Text("\(thresholdSummary) Changing your saved location clears the previous garden’s weather snapshot and manual watering history.")
                }

                Section {
                    Toggle("Watering Reminders", isOn: $notificationsEnabled)

                    if notificationsEnabled {
                        LabeledContent("Reminder Time", value: Self.reminderHourLabel(for: notificationHour))
                    }

                    Picker("Reminder Time", selection: $notificationHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(Self.reminderHourLabel(for: hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(!notificationsEnabled)
                } header: {
                    Label("Reminders", systemImage: "bell")
                } footer: {
                    Text(reminderSummary)
                }

                Section {
                    if let weatherSnapshot, !weatherSnapshot.attributionText.isEmpty {
                        DisclosureGroup("Show attribution details") {
                            Text(weatherSnapshot.attributionText)
                                .font(.footnote)

                            if let attributionURL = URL(string: weatherSnapshot.attributionURLString) {
                                Link("Open Legal Attribution", destination: attributionURL)
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                    } else {
                        Text("Weather attribution will appear after the first successful weather update.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Weather Attribution", systemImage: "cloud.sun")
                }

                Section {
                    LabeledContent("Version", value: appVersionString)
                    LabeledContent("Build", value: appBuildString)
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                await saveChanges()
                            }
                        }
                        .disabled(!hasChanges)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingLocationPicker) {
            LocationPickerSheet(selectedLocation: $draftLocation)
        }
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @MainActor
    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let shouldEnableNotifications = notificationsEnabled && !gardenProfile.notificationsEnabled

            if shouldEnableNotifications {
                let granted = try await notificationAuthorizationService.requestAuthorization()

                if !granted {
                    notificationsEnabled = false
                    activeAlert = SettingsAlert(
                        title: "Notifications Stay Off",
                        message: "Dry Spell couldn't enable reminders. Your other changes are still on screen, and you can save them after this alert."
                    )
                    return
                }
            }

            let store = DrySpellStore(modelContext: modelContext)
            _ = try store.saveGardenSettings(
                existingProfile: gardenProfile,
                location: draftLocation,
                dryDayThresholdDays: dryDayThresholdDays,
                notificationsEnabled: notificationsEnabled,
                notificationHour: notificationHour,
                weatherSnapshot: weatherSnapshot,
                recommendationEngine: RecommendationEngine(),
                now: .now
            )
            try store.writeWidgetSnapshot(now: .now)
            backgroundRefreshScheduler.submitNextRefresh()
        } catch {
            activeAlert = SettingsAlert(
                title: "Couldn't Save Settings",
                message: error.localizedDescription
            )
            return
        }

        do {
            let store = DrySpellStore(modelContext: modelContext)
            try await syncReminders(using: store, now: .now)
            dismiss()
        } catch {
            activeAlert = SettingsAlert(
                title: "Settings Saved",
                message: "Dry Spell saved your changes, but it couldn't update the reminder schedule."
            )
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

    private var appVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var appBuildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var thresholdSummary: String {
        switch dryDayThresholdDays {
        case 3:
            return "A 3-day threshold makes reminders more proactive."
        case 7:
            return "A 7-day threshold waits for longer dry stretches."
        default:
            return "A 5-day threshold balances responsiveness and restraint."
        }
    }

    private var reminderSummary: String {
        if notificationsEnabled {
            return "Dry Spell will consider reminders at \(Self.reminderHourLabel(for: notificationHour)) and only uses fresh weather data when deciding whether a reminder is eligible."
        }

        return "Reminders are off. Dry Spell only schedules new reminders when fresh weather supports watering."
    }

    private static func reminderHourLabel(for hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components) ?? .now

        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }
}

private struct SettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct LocationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationSearch = LocationSearchService()
    @Binding var selectedLocation: ResolvedGardenLocation

    @State private var resolvedLocation: ResolvedGardenLocation?
    @State private var isResolvingLocation = false
    @State private var activeAlert: SettingsAlert?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Location", value: selectedLocation.displayName)
                    LabeledContent("Time Zone", value: selectedLocation.timeZoneIdentifier)
                } header: {
                    Text("Current Selection")
                } footer: {
                    Text("Search for a new location, then review the closest match before saving it.")
                }

                if isResolvingLocation {
                    Section {
                        ProgressView("Loading location details...")
                    }
                }

                if let errorMessage = locationSearch.errorMessage {
                    Section {
                        ContentUnavailableView(
                            "Location Search Unavailable",
                            systemImage: "exclamationmark.magnifyingglass",
                            description: Text(errorMessage)
                        )
                    }
                } else if locationSearch.query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
                          locationSearch.suggestions.isEmpty,
                          !locationSearch.isSearching,
                          resolvedLocation == nil {
                    Section {
                        ContentUnavailableView.search(text: locationSearch.query)
                    }
                } else if !locationSearch.suggestions.isEmpty, resolvedLocation == nil {
                    Section {
                        ForEach(locationSearch.suggestions) { suggestion in
                            Button {
                                resolveSuggestion(suggestion)
                            } label: {
                                SettingsLocationSuggestionRow(suggestion: suggestion)
                            }
                            .buttonStyle(.plain)
                            .disabled(isResolvingLocation)
                        }
                    } header: {
                        Text("Suggestions")
                    } footer: {
                        Text("Choose the closest match, then confirm it before saving.")
                    }
                }

                if let resolvedLocation {
                    Section {
                        SettingsLocationSummaryCard(location: resolvedLocation)
                    } header: {
                        Text("Confirm Location")
                    } footer: {
                        Text("Use this location to replace your saved garden and clear weather history from the previous location.")
                    }
                }
            }
            .navigationTitle("Change Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $locationSearch.query, prompt: "Search for a location")
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .safeAreaInset(edge: .bottom) {
                if let resolvedLocation {
                    VStack(spacing: 0) {
                        Divider()

                        Button("Use This Location") {
                            selectedLocation = resolvedLocation
                            dismiss()
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.bar)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: locationSearch.query) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || resolvedLocation != nil {
                resolvedLocation = nil
            }
        }
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func resolveSuggestion(_ suggestion: LocationSuggestion) {
        Task {
            isResolvingLocation = true
            defer { isResolvingLocation = false }

            do {
                resolvedLocation = try await locationSearch.resolveSuggestion(suggestion)
            } catch {
                activeAlert = SettingsAlert(
                    title: "Invalid Location",
                    message: error.localizedDescription
                )
            }
        }
    }
}

private struct SettingsLocationSuggestionRow: View {
    let suggestion: LocationSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SettingsLocationSummaryCard: View {
    let location: ResolvedGardenLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Selected Result", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            LabeledContent("Location", value: location.displayName)
            LabeledContent("Time Zone", value: location.timeZoneIdentifier)
            LabeledContent(
                "Coordinates",
                value: "\(location.latitude.formatted(.number.precision(.fractionLength(4)))), \(location.longitude.formatted(.number.precision(.fractionLength(4))))"
            )
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

#Preview {
    SettingsView(
        gardenProfile: GardenProfile(
            displayName: "Back Garden",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver"
        ),
        weatherSnapshot: WeatherSnapshot(
            fetchedAt: .now,
            observed7DayRainMM: 12.8,
            forecast48hRainMM: 4.1,
            attributionText: "Weather data from Apple Weather.",
            attributionURLString: "https://weatherkit.apple.com/legal-attribution.html"
        )
    )
    .modelContainer(DrySpellModelContainer.preview)
}
