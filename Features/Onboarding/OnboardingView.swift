import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationSearch = LocationSearchService()

    @State private var step: OnboardingStep = .welcome
    @State private var selectedLocation: ResolvedGardenLocation?
    @State private var dryDayThresholdDays = DrySpellConstants.defaultDryDayThresholdDays
    @State private var isResolvingLocation = false
    @State private var isSaving = false
    @State private var activeAlert: OnboardingAlert?

    private let notificationAuthorizationService = NotificationAuthorizationService()
    private let backgroundRefreshScheduler = BackgroundRefreshScheduler()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(OnboardingStep.allCases.count))
                    .tint(.accentColor)

                currentStepView
            }
            .padding()
        }
        .navigationTitle("Dry Spell")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch step {
        case .welcome:
            WelcomeStep {
                step = .locationSearch
            }

        case .locationSearch:
            LocationSearchStep(
                locationSearch: locationSearch,
                isResolvingLocation: isResolvingLocation,
                onBack: {
                    step = .welcome
                },
                onSelectSuggestion: resolveSuggestion
            )

        case .confirmLocation:
            ConfirmLocationStep(
                location: selectedLocation,
                onBack: {
                    step = .locationSearch
                },
                onContinue: {
                    step = .dryDayThreshold
                }
            )

        case .dryDayThreshold:
            DryDayThresholdStep(
                dryDayThresholdDays: $dryDayThresholdDays,
                onBack: {
                    step = .confirmLocation
                },
                onContinue: {
                    step = .reminderOptIn
                }
            )

        case .reminderOptIn:
            ReminderOptInStep(
                isSaving: isSaving,
                onBack: {
                    step = .dryDayThreshold
                },
                onSkip: {
                    Task {
                        await finishOnboarding(notificationsEnabled: false)
                    }
                },
                onEnableReminders: {
                    Task {
                        await requestRemindersAndFinish()
                    }
                }
            )
        }
    }

    private func resolveSuggestion(_ suggestion: LocationSuggestion) {
        Task {
            isResolvingLocation = true
            defer { isResolvingLocation = false }

            do {
                selectedLocation = try await locationSearch.resolveSuggestion(suggestion)
                step = .confirmLocation
            } catch {
                activeAlert = OnboardingAlert(
                    title: "Invalid Location",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func requestRemindersAndFinish() async {
        do {
            let granted = try await notificationAuthorizationService.requestAuthorization()

            if granted {
                await finishOnboarding(notificationsEnabled: true)
            } else {
                activeAlert = OnboardingAlert(
                    title: "Notifications Off",
                    message: "Dry Spell couldn't enable reminders. You can keep going now and turn them on later in Settings."
                )
            }
        } catch {
            activeAlert = OnboardingAlert(
                title: "Notifications Unavailable",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func finishOnboarding(notificationsEnabled: Bool) async {
        guard let selectedLocation else {
            activeAlert = OnboardingAlert(
                title: "Location Needed",
                message: "Choose a garden location before finishing setup."
            )
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let store = DrySpellStore(modelContext: modelContext)
            _ = try store.saveGardenProfile(
                GardenProfile(
                    displayName: selectedLocation.displayName,
                    latitude: selectedLocation.latitude,
                    longitude: selectedLocation.longitude,
                    timeZoneIdentifier: selectedLocation.timeZoneIdentifier,
                    dryDayThresholdDays: dryDayThresholdDays,
                    notificationsEnabled: notificationsEnabled,
                    notificationHour: DrySpellConstants.defaultNotificationHour
                )
            )
            try store.writeWidgetSnapshot(now: .now)
            backgroundRefreshScheduler.submitNextRefresh()
        } catch {
            activeAlert = OnboardingAlert(
                title: "Couldn't Save Setup",
                message: error.localizedDescription
            )
        }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case locationSearch
    case confirmLocation
    case dryDayThreshold
    case reminderOptIn
}

private struct OnboardingAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Track rainfall for one garden location.")
                .font(.largeTitle.weight(.bold))

            Text("Get reminded when it has been dry, unless enough rain is coming soon.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Label("One saved garden location", systemImage: "leaf")
            Label("Simple local reminders", systemImage: "bell")
            Label("A small widget for quick status", systemImage: "square.grid.2x2")

            Button("Set Up Garden", action: onContinue)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LocationSearchStep: View {
    @ObservedObject var locationSearch: LocationSearchService

    let isResolvingLocation: Bool
    let onBack: () -> Void
    let onSelectSuggestion: (LocationSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose your garden location")
                .font(.title.bold())

            Text("Search by address, neighborhood, or place name. Dry Spell uses one saved location in v1 and never asks for live location permission.")
                .foregroundStyle(.secondary)

            TextField("Search for a location", text: $locationSearch.query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            if isResolvingLocation {
                ProgressView("Loading location details...")
            } else if locationSearch.isSearching {
                ProgressView("Searching...")
            }

            if let errorMessage = locationSearch.errorMessage {
                ContentUnavailableView(
                    "Location Search Unavailable",
                    systemImage: "exclamationmark.magnifyingglass",
                    description: Text(errorMessage)
                )
            } else if locationSearch.query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
                      locationSearch.suggestions.isEmpty,
                      !locationSearch.isSearching {
                ContentUnavailableView.search(text: locationSearch.query)
                    .frame(maxWidth: .infinity)
            } else if !locationSearch.suggestions.isEmpty {
                VStack(spacing: 12) {
                    ForEach(locationSearch.suggestions) { suggestion in
                        Button {
                            onSelectSuggestion(suggestion)
                        } label: {
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolvingLocation)
                    }
                }
            }

            Button("Back", action: onBack)
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConfirmLocationStep: View {
    let location: ResolvedGardenLocation?
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Confirm this location")
                .font(.title.bold())

            if let location {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Location", value: location.displayName)
                    LabeledContent("Time Zone", value: location.timeZoneIdentifier)
                    LabeledContent(
                        "Coordinates",
                        value: "\(location.latitude.formatted(.number.precision(.fractionLength(4)))), \(location.longitude.formatted(.number.precision(.fractionLength(4))))"
                    )
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else {
                ContentUnavailableView(
                    "No Location Selected",
                    systemImage: "location.slash",
                    description: Text("Go back and choose a garden location first.")
                )
            }

            HStack(spacing: 12) {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)

                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .disabled(location == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DryDayThresholdStep: View {
    @Binding var dryDayThresholdDays: Int

    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose a dry-day threshold")
                .font(.title.bold())

            Text("Dry Spell can remind you after 3, 5, or 7 dry days. The default is 5.")
                .foregroundStyle(.secondary)

            Picker("Dry-Day Threshold", selection: $dryDayThresholdDays) {
                ForEach(DrySpellConstants.allowedDryDayThresholds, id: \.self) { days in
                    Text("\(days) days").tag(days)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)

                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReminderOptInStep: View {
    let isSaving: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onEnableReminders: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Turn on reminders?")
                .font(.title.bold())

            Text("Dry Spell can send local reminders at 9:00 AM when conditions support watering. It won’t schedule reminders without fresh weather data.")
                .foregroundStyle(.secondary)

            if isSaving {
                ProgressView("Saving setup...")
            }

            HStack(spacing: 12) {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                    .disabled(isSaving)

                Button("Skip for Now", action: onSkip)
                    .buttonStyle(.bordered)
                    .disabled(isSaving)

                Button("Enable Reminders", action: onEnableReminders)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    OnboardingView()
        .modelContainer(DrySpellModelContainer.preview)
}
