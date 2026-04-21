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
        .navigationBarTitleDisplayMode(.inline)
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            if step != .welcome {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", action: goBack)
                        .disabled(isResolvingLocation || isSaving)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionBar
        }
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
            WelcomeStep()

        case .locationSearch:
            LocationSearchStep(
                locationSearch: locationSearch,
                isResolvingLocation: isResolvingLocation,
                onSelectSuggestion: resolveSuggestion
            )

        case .dryDayThreshold:
            DryDayThresholdStep(dryDayThresholdDays: $dryDayThresholdDays)

        case .reminderOptIn:
            ReminderOptInStep()
        }
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        switch step {
        case .welcome:
            OnboardingActionBar(
                primaryTitle: "Set Up My Garden",
                primaryAction: {
                    step = .locationSearch
                }
            )

        case .locationSearch:
            EmptyView()

        case .dryDayThreshold:
            OnboardingActionBar(
                primaryTitle: "Continue",
                primaryAction: {
                    step = .reminderOptIn
                }
            )

        case .reminderOptIn:
            OnboardingActionBar(
                primaryTitle: "Turn On Reminders",
                primaryAction: {
                    Task {
                        await requestRemindersAndFinish()
                    }
                },
                secondaryTitle: "Not Now",
                secondaryAction: {
                    Task {
                        await finishOnboarding(notificationsEnabled: false)
                    }
                },
                isLoading: isSaving,
                primaryDisabled: isSaving,
                secondaryDisabled: isSaving
            )
        }
    }

    private func goBack() {
        guard !isSaving, !isResolvingLocation else {
            return
        }

        switch step {
        case .welcome:
            return
        case .locationSearch:
            step = .welcome
        case .dryDayThreshold:
            step = .locationSearch
        case .reminderOptIn:
            step = .dryDayThreshold
        }
    }

    private func resolveSuggestion(_ suggestion: LocationSuggestion) {
        Task {
            isResolvingLocation = true
            defer { isResolvingLocation = false }

            do {
                selectedLocation = try await locationSearch.resolveSuggestion(suggestion)
                step = .dryDayThreshold
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
                    title: "Reminders Are Off",
                    message: "Reminders couldn't be turned on right now. You can finish setup now and enable them later in Settings."
                )
            }
        } catch {
            activeAlert = OnboardingAlert(
                title: "Reminders Unavailable",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func finishOnboarding(notificationsEnabled: Bool) async {
        guard let selectedLocation else {
            activeAlert = OnboardingAlert(
                title: "Garden Location Needed",
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
                title: "Couldn't Finish Setup",
                message: error.localizedDescription
            )
        }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case locationSearch
    case dryDayThreshold
    case reminderOptIn
}

private struct OnboardingAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(
                eyebrow: "Welcome",
                title: "Know when your garden needs water.",
                subtitle: "Dry Spell checks recent rain and the forecast for your saved garden."
            )

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "cloud.sun.rain.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 12) {
                    OnboardingFeatureRow(
                        systemImage: "leaf",
                        title: "One saved garden",
                        subtitle: "Track a single garden with one saved location."
                    )
                    OnboardingFeatureRow(
                        systemImage: "bell.badge",
                        title: "Weather-based reminders",
                        subtitle: "Only when current conditions still point to watering."
                    )
                    OnboardingFeatureRow(
                        systemImage: "square.grid.2x2",
                        title: "A quick widget",
                        subtitle: "See today's status from your Home Screen."
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LocationSearchStep: View {
    @ObservedObject var locationSearch: LocationSearchService

    let isResolvingLocation: Bool
    let onSelectSuggestion: (LocationSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(
                eyebrow: "Location",
                title: "Choose your garden location",
                subtitle: "Search for a place or address, then pick the best match. Dry Spell doesn't use live location."
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
                            GardenLocationSuggestionRow(
                                suggestion: suggestion,
                                style: .card
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolvingLocation)
                    }
                }

                Text("Pick the closest match to keep going.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DryDayThresholdStep: View {
    @Binding var dryDayThresholdDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(
                eyebrow: "Threshold",
                title: "When should Dry Spell check in?",
                subtitle: "Pick how many dry days should pass before we suggest watering."
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thresholdSummary: String {
        DrySpellConstants.dryDayThresholdSummary(for: dryDayThresholdDays)
    }
}

private struct ReminderOptInStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(
                eyebrow: "Reminders",
                title: "Turn on reminders?",
                subtitle: "Get a 9:00 AM reminder your time when it still looks like your garden needs water. Change it anytime in Settings."
            )

            VStack(alignment: .leading, spacing: 12) {
                OnboardingFeatureRow(
                    systemImage: "clock.badge.checkmark",
                    title: "Default time: 9:00 AM your time",
                    subtitle: "You can change the time later in Settings."
                )
                OnboardingFeatureRow(
                    systemImage: "icloud.slash",
                    title: "Only when weather is fresh",
                    subtitle: "No reminder if weather data is stale or unavailable."
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
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingActionBar: View {
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?
    let isLoading: Bool
    let primaryDisabled: Bool
    let secondaryDisabled: Bool

    init(
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        isLoading: Bool = false,
        primaryDisabled: Bool = false,
        secondaryDisabled: Bool = false
    ) {
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.isLoading = isLoading
        self.primaryDisabled = primaryDisabled
        self.secondaryDisabled = secondaryDisabled
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 12) {
                Button(action: primaryAction) {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }

                        Text(primaryTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(primaryDisabled)

                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.plain)
                        .font(.body.weight(.semibold))
                        .disabled(secondaryDisabled)
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(.bar)
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

#Preview {
    OnboardingView()
        .modelContainer(DrySpellModelContainer.preview)
}
