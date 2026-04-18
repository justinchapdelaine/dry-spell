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
                } header: {
                    Text("Garden")
                } footer: {
                    Text("Changing your saved location clears the previous garden’s weather snapshot and manual watering history.")
                }

                Section {
                    Toggle("Watering Reminders", isOn: $notificationsEnabled)

                    Picker("Reminder Time", selection: $notificationHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(Self.reminderHourLabel(for: hour)).tag(hour)
                        }
                    }
                    .disabled(!notificationsEnabled)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Dry Spell only uses fresh weather data when deciding whether a reminder is eligible.")
                }

                Section {
                    if let weatherSnapshot, !weatherSnapshot.attributionText.isEmpty {
                        Text(weatherSnapshot.attributionText)

                        if let attributionURL = URL(string: weatherSnapshot.attributionURLString) {
                            Link("Open Legal Attribution", destination: attributionURL)
                        }
                    } else {
                        Text("Weather attribution will appear after the first successful weather update.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Weather Attribution")
                }

                Section {
                    LabeledContent("Version", value: appVersionString)
                    LabeledContent("Build", value: appBuildString)
                } header: {
                    Text("About")
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
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(!hasChanges || isSaving)
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
                    TextField("Search for a location", text: $locationSearch.query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                if isResolvingLocation {
                    Section {
                        ProgressView("Loading location details...")
                    }
                } else if locationSearch.isSearching {
                    Section {
                        ProgressView("Searching...")
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.title)
                                        .foregroundStyle(.primary)

                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(isResolvingLocation)
                        }
                    } header: {
                        Text("Suggestions")
                    }
                }

                if let resolvedLocation {
                    Section {
                        LabeledContent("Location", value: resolvedLocation.displayName)
                        LabeledContent("Time Zone", value: resolvedLocation.timeZoneIdentifier)
                        LabeledContent(
                            "Coordinates",
                            value: "\(resolvedLocation.latitude.formatted(.number.precision(.fractionLength(4)))), \(resolvedLocation.longitude.formatted(.number.precision(.fractionLength(4))))"
                        )

                        Button("Use This Location") {
                            selectedLocation = resolvedLocation
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    } header: {
                        Text("Confirm Location")
                    }
                }
            }
            .navigationTitle("Change Location")
            .navigationBarTitleDisplayMode(.inline)
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
