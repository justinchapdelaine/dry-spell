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
    private let contentMaxWidth: CGFloat = 720

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ProgressView(value: Double(step.rawValue + 1), total: Double(OnboardingStep.allCases.count))
                        .tint(.accentColor)
                }

                currentStepView
            }
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Dry Spell")
        .navigationBarTitleDisplayMode(.large)
        .scrollBounceBehavior(.basedOnSize)
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
            _ = try store.saveInitialGardenProfileAndWidgetSnapshot(
                GardenProfile(
                    displayName: selectedLocation.displayName,
                    latitude: selectedLocation.latitude,
                    longitude: selectedLocation.longitude,
                    timeZoneIdentifier: selectedLocation.timeZoneIdentifier,
                    dryDayThresholdDays: dryDayThresholdDays,
                    notificationsEnabled: notificationsEnabled,
                    notificationHour: DrySpellConstants.defaultNotificationHour
                ),
                now: .now
            )
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
            OnboardingStepHeader(
                eyebrow: "Welcome",
                title: "Track rainfall for one garden location.",
                subtitle: "Get reminded when it has been dry, unless enough rain is coming soon."
            )

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "cloud.sun.rain.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 12) {
                    OnboardingFeatureRow(
                        systemImage: "leaf",
                        title: "One saved garden location",
                        subtitle: "Keep the app focused on one garden in v1."
                    )
                    OnboardingFeatureRow(
                        systemImage: "bell.badge",
                        title: "Simple local reminders",
                        subtitle: "Only when fresh weather supports watering."
                    )
                    OnboardingFeatureRow(
                        systemImage: "square.grid.2x2",
                        title: "A quick widget",
                        subtitle: "See your current status without opening the app."
                    )
                }
            }
            .padding(24)
            .background(
                LinearGradient(
                    colors: [.green.opacity(0.16), .blue.opacity(0.06), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .glassEffect(.regular.tint(.green.opacity(0.08)), in: .rect(cornerRadius: 28))

            Button("Set Up Garden", action: onContinue)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.top, 4)
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
            OnboardingStepHeader(
                eyebrow: "Location",
                title: "Choose your garden location",
                subtitle: "Search by address, neighborhood, or place name, then review the closest match before continuing. Dry Spell uses one saved location in v1 and never asks for live location permission."
            )

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)

                TextField("Search for a location", text: $locationSearch.query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
            }
            .glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: .rect(cornerRadius: 18))

            if isResolvingLocation {
                ProgressView("Loading location details...")
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
                            OnboardingLocationSuggestionCard(suggestion: suggestion)
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolvingLocation)
                    }
                }

                Text("Choose the closest match, then review it before continuing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Back", action: onBack)
                .buttonStyle(.glass)
                .padding(.top, 4)
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
            OnboardingStepHeader(
                eyebrow: "Confirm",
                title: "Confirm this location",
                subtitle: "Review the selected result below before saving it as your garden location."
            )

            if let location {
                OnboardingLocationSummaryCard(location: location)
            } else {
                ContentUnavailableView(
                    "No Location Selected",
                    systemImage: "location.slash",
                    description: Text("Go back and choose a garden location first.")
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Button("Back", action: onBack)
                        .buttonStyle(.glass)

                    Button("Continue", action: onContinue)
                        .buttonStyle(.glassProminent)
                        .disabled(location == nil)
                }

                VStack(spacing: 12) {
                    Button("Continue", action: onContinue)
                        .buttonStyle(.glassProminent)
                        .disabled(location == nil)

                    Button("Back", action: onBack)
                        .buttonStyle(.glass)
                }
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
            OnboardingStepHeader(
                eyebrow: "Threshold",
                title: "Choose a dry-day threshold",
                subtitle: "Dry Spell can remind you after 3, 5, or 7 dry days. The default is 5."
            )

            VStack(alignment: .leading, spacing: 16) {
                Picker("Dry-Day Threshold", selection: $dryDayThresholdDays) {
                    ForEach(DrySpellConstants.allowedDryDayThresholds, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)

                Text(thresholdSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Button("Back", action: onBack)
                        .buttonStyle(.glass)

                    Button("Continue", action: onContinue)
                        .buttonStyle(.glassProminent)
                }

                VStack(spacing: 12) {
                    Button("Continue", action: onContinue)
                        .buttonStyle(.glassProminent)

                    Button("Back", action: onBack)
                        .buttonStyle(.glass)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thresholdSummary: String {
        switch dryDayThresholdDays {
        case 3:
            return "A 3-day threshold makes reminders more proactive after short dry stretches."
        case 7:
            return "A 7-day threshold is more conservative and waits for longer dry periods."
        default:
            return "A 5-day threshold balances recent dry weather with a conservative reminder cadence."
        }
    }
}

private struct ReminderOptInStep: View {
    let isSaving: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onEnableReminders: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(
                eyebrow: "Reminders",
                title: "Turn on reminders?",
                subtitle: "Dry Spell can send local reminders at 9:00 AM when conditions support watering. It won’t schedule reminders without fresh weather data."
            )

            VStack(alignment: .leading, spacing: 12) {
                OnboardingFeatureRow(
                    systemImage: "clock.badge.checkmark",
                    title: "9:00 AM local reminder time",
                    subtitle: "You can change this later in Settings."
                )
                OnboardingFeatureRow(
                    systemImage: "icloud.slash",
                    title: "Fresh weather required",
                    subtitle: "Dry Spell won’t create new reminders from stale or unavailable weather."
                )
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [.orange.opacity(0.12), .yellow.opacity(0.06), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .glassEffect(.regular.tint(.orange.opacity(0.06)), in: .rect(cornerRadius: 24))

            if isSaving {
                ProgressView("Saving setup...")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Button("Back", action: onBack)
                        .buttonStyle(.glass)
                        .disabled(isSaving)

                    Button("Skip for Now", action: onSkip)
                        .buttonStyle(.glass)
                        .disabled(isSaving)

                    Button("Enable Reminders", action: onEnableReminders)
                        .buttonStyle(.glassProminent)
                        .disabled(isSaving)
                }

                VStack(spacing: 12) {
                    Button("Enable Reminders", action: onEnableReminders)
                        .buttonStyle(.glassProminent)
                        .disabled(isSaving)

                    Button("Skip for Now", action: onSkip)
                        .buttonStyle(.glass)
                        .disabled(isSaving)

                    Button("Back", action: onBack)
                        .buttonStyle(.glass)
                        .disabled(isSaving)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingStepHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.largeTitle.weight(.bold))

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingFeatureRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingLocationSuggestionCard: View {
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
        .padding()
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct OnboardingLocationSummaryCard: View {
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
        .padding(20)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.12), .mint.opacity(0.06), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .glassEffect(.regular.tint(.blue.opacity(0.08)), in: .rect(cornerRadius: 24))
    }
}

#Preview {
    OnboardingView()
        .modelContainer(DrySpellModelContainer.preview)
}
