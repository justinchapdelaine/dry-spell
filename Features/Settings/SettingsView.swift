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
    @State private var notificationPermissionState: NotificationPermissionState = .unknown

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
                    Text("\(thresholdSummary) Changing your garden location clears the previous location's weather history and manual watering log.")
                }

                Section {
                    Toggle("Watering Reminders", isOn: $notificationsEnabled)

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
        .task {
            await refreshNotificationPermissionState()
        }
    }

    @MainActor
    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let now = Date()

            if notificationsEnabled {
                let permissionState = try await notificationAuthorizationService.resolvePermissionStateForReminders()
                notificationPermissionState = permissionState

                if permissionState != .allowed {
                    notificationsEnabled = false
                    activeAlert = SettingsAlert(
                        title: "Notifications Stay Off",
                        message: reminderPermissionMessage(for: permissionState)
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
                now: now
            )
        } catch {
            activeAlert = SettingsAlert(
                title: "Couldn't Save Settings",
                message: error.localizedDescription
            )
            return
        }

        let now = Date()
        let store = DrySpellStore(modelContext: modelContext)
        var followUpIssues: [String] = []

        do {
            try store.writeWidgetSnapshot(now: now)
        } catch {
            followUpIssues.append("update the widget")
        }

        backgroundRefreshScheduler.submitNextRefresh()

        do {
            try await syncReminders(using: store, now: now)
        } catch {
            followUpIssues.append("update the reminder schedule")
        }

        if followUpIssues.isEmpty {
            dismiss()
        } else {
            activeAlert = SettingsAlert(
                title: "Settings Saved",
                message: DrySpellConstants.partialSuccessMessage(
                    for: "saved your changes",
                    followUpIssues: followUpIssues
                )
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
        DrySpellConstants.dryDayThresholdSummary(for: dryDayThresholdDays)
    }

    private var reminderSummary: String {
        if notificationsEnabled && notificationPermissionState == .denied {
            return "Notifications are turned off in iPhone Settings, so reminders can't be scheduled right now. Turn them back on there, then save again."
        }

        if notificationsEnabled {
            return "Dry Spell checks at \(Self.reminderHourLabel(for: notificationHour)) your time and only schedules reminders when the latest weather still points to watering."
        }

        return "Reminders are off. Turn them on to get a nudge when conditions point to watering."
    }

    @MainActor
    private func refreshNotificationPermissionState() async {
        notificationPermissionState = await notificationAuthorizationService.permissionState()
    }

    private func reminderPermissionMessage(for permissionState: NotificationPermissionState) -> String {
        switch permissionState {
        case .denied:
            return "Reminders can't be turned on because notifications are off in iPhone Settings. Your other changes are still here, and you can save them after this alert."
        case .notDetermined, .unknown:
            return "Notification access couldn't be confirmed. Your other changes are still here, and you can save them after this alert."
        case .allowed:
            return "Dry Spell is ready to schedule reminders."
        }
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
    @State private var isResolvingLocation = false
    @State private var activeAlert: SettingsAlert?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Location", value: selectedLocation.displayName)
                } header: {
                    Text("Current Selection")
                } footer: {
                    Text("Search for a new location, then pick the best match to update Settings.")
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
                          !locationSearch.isSearching {
                    Section {
                        ContentUnavailableView.search(text: locationSearch.query)
                    }
                } else if !locationSearch.suggestions.isEmpty {
                    Section {
                        ForEach(locationSearch.suggestions) { suggestion in
                            Button {
                                resolveSuggestion(suggestion)
                            } label: {
                                GardenLocationSuggestionRow(suggestion: suggestion)
                            }
                            .buttonStyle(.plain)
                            .disabled(isResolvingLocation)
                        }
                    } header: {
                        Text("Suggestions")
                    } footer: {
                        Text("Choose the closest match. You'll still need to tap Save in Settings to keep the change.")
                    }
                }
            }
            .navigationTitle("Change Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $locationSearch.query, prompt: "Search for a location")
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
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
                selectedLocation = try await locationSearch.resolveSuggestion(suggestion)
                dismiss()
            } catch {
                activeAlert = SettingsAlert(
                    title: "Invalid Location",
                    message: error.localizedDescription
                )
            }
        }
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
            attributionURLString: "https://weatherkit.apple.com/legal-attribution.html",
            attributionCombinedMarkLightURLString: "https://weatherkit.apple.com/assets/branding/combined-mark-light.png",
            attributionCombinedMarkDarkURLString: "https://weatherkit.apple.com/assets/branding/combined-mark-dark.png"
        )
    )
    .modelContainer(DrySpellModelContainer.preview)
}
