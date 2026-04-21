import SwiftUI

struct WeatherAttributionDetails: View {
    let weatherSnapshot: WeatherSnapshot?
    let disclosureTitle: LocalizedStringKey
    var emptyText: LocalizedStringKey?

    var body: some View {
        if let weatherSnapshot, weatherSnapshot.hasDisplayableAttribution {
            WeatherAttributionDisclosure(
                weatherSnapshot: weatherSnapshot,
                disclosureTitle: disclosureTitle
            )
        } else if let emptyText {
            Text(emptyText)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WeatherAttributionDisclosure: View {
    @Environment(\.colorScheme) private var colorScheme

    let weatherSnapshot: WeatherSnapshot
    let disclosureTitle: LocalizedStringKey

    @State private var isExpanded = false

    private var content: WeatherAttributionContent {
        WeatherAttributionContentParser.parse(weatherSnapshot.attributionText)
    }

    var body: some View {
        DisclosureGroup(disclosureTitle, isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                AppleWeatherMarkView(markURL: combinedMarkURL)

                if !content.title.isEmpty {
                    Text(content.title)
                        .font(.subheadline.weight(.semibold))
                }

                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if content.sections.isEmpty, !content.fallbackText.isEmpty {
                    Text(content.fallbackText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(content.sections) { section in
                            WeatherAttributionSectionView(section: section)
                        }
                    }
                }

                if let footerText = content.footerText, !footerText.isEmpty {
                    Text(footerText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let attributionURL = URL(string: weatherSnapshot.attributionURLString) {
                    Link("Open Legal Attribution", destination: attributionURL)
                        .font(.footnote.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var combinedMarkURL: URL? {
        let urlString = colorScheme == .dark
            ? weatherSnapshot.attributionCombinedMarkDarkURLString
            : weatherSnapshot.attributionCombinedMarkLightURLString

        guard let urlString, !urlString.isEmpty else {
            return nil
        }

        return URL(string: urlString)
    }
}

private struct WeatherAttributionSectionView: View {
    let section: WeatherAttributionSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(item.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct AppleWeatherMarkView: View {
    let markURL: URL?

    var body: some View {
        Group {
            if let markURL {
                AsyncImage(url: markURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        fallbackMark
                    }
                }
            } else {
                fallbackMark
            }
        }
        .frame(maxWidth: 150, alignment: .leading)
        .frame(height: 22, alignment: .leading)
        .accessibilityLabel("Apple Weather")
    }

    private var fallbackMark: some View {
        Text("Apple Weather")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

private struct WeatherAttributionContent {
    var title = ""
    var subtitle: String?
    var sections: [WeatherAttributionSection] = []
    var footerText: String?
    var fallbackText = ""
}

private struct WeatherAttributionSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [WeatherAttributionItem]
}

private struct WeatherAttributionItem: Identifiable {
    let id = UUID()
    let text: String
}

private enum WeatherAttributionContentParser {
    static func parse(_ rawText: String) -> WeatherAttributionContent {
        let normalizedLines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !normalizedLines.isEmpty else {
            return WeatherAttributionContent()
        }

        let nonEmptyLines = normalizedLines.filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else {
            return WeatherAttributionContent(fallbackText: rawText)
        }

        var content = WeatherAttributionContent()
        var index = 0

        if let firstLine = nonEmptyLines.first {
            content.title = firstLine
            index = 1
        }

        if index < nonEmptyLines.count,
           !isBullet(nonEmptyLines[index]),
           !isSectionTitle(nonEmptyLines[index], nextLine: nonEmptyLines[safe: index + 1]) {
            content.subtitle = nonEmptyLines[index]
            index += 1
        }

        var sections: [WeatherAttributionSection] = []
        var footerLines: [String] = []

        while index < nonEmptyLines.count {
            let line = nonEmptyLines[index]

            guard !isBullet(line) else {
                content.fallbackText = rawText
                return content
            }

            guard isSectionTitle(line, nextLine: nonEmptyLines[safe: index + 1]) else {
                footerLines.append(line)
                index += 1
                continue
            }

            let title = line
            var items: [WeatherAttributionItem] = []
            index += 1

            while index < nonEmptyLines.count, isBullet(nonEmptyLines[index]) {
                items.append(WeatherAttributionItem(text: stripBulletPrefix(from: nonEmptyLines[index])))
                index += 1
            }

            sections.append(WeatherAttributionSection(title: title, items: items))
        }

        content.sections = sections

        if !footerLines.isEmpty {
            content.footerText = footerLines.joined(separator: "\n\n")
        }

        if sections.isEmpty {
            content.fallbackText = rawText
        }

        return content
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("•") || line.hasPrefix("-")
    }

    private static func isSectionTitle(_ line: String, nextLine: String?) -> Bool {
        guard !line.isEmpty, !isBullet(line), let nextLine else {
            return false
        }

        return isBullet(nextLine)
    }

    private static func stripBulletPrefix(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") {
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension WeatherSnapshot {
    var hasDisplayableAttribution: Bool {
        !attributionText.isEmpty ||
        !attributionURLString.isEmpty ||
        !(attributionCombinedMarkLightURLString ?? "").isEmpty ||
        !(attributionCombinedMarkDarkURLString ?? "").isEmpty
    }
}
