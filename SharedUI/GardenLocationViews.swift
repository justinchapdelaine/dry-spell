import SwiftUI

struct GardenLocationSuggestionRow: View {
    enum Style {
        case plain
        case card
    }

    let suggestion: LocationSuggestion
    var style: Style = .plain

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
        .modifier(GardenLocationSuggestionRowStyle(style: style))
        .contentShape(Rectangle())
    }
}

struct GardenLocationSummaryCard: View {
    enum Style {
        case settings
        case onboarding
    }

    let location: ResolvedGardenLocation
    var style: Style = .onboarding
    var timeZoneNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Selected Result", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            LabeledContent("Location", value: location.displayName)

            if let timeZoneNote {
                Text(timeZoneNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(GardenLocationSummaryCardStyle(style: style))
    }
}

private struct GardenLocationSuggestionRowStyle: ViewModifier {
    let style: GardenLocationSuggestionRow.Style

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .plain:
            content
        case .card:
            content
                .padding()
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
    }
}

private struct GardenLocationSummaryCardStyle: ViewModifier {
    let style: GardenLocationSummaryCard.Style

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .settings:
            content
                .padding(16)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        case .onboarding:
            content
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
}
