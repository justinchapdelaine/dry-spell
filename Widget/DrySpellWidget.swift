import SwiftUI
import WidgetKit
import OSLog

struct WidgetSnapshotPayload: Codable, Equatable {
    let statusTitle: String
    let statusSubtitle: String
    let lastMeaningfulRainDate: Date?
    let dryDays: Int
    let observed7DayRainMM: Double
    let forecast48hRainMM: Double
    let updatedAt: Date
    let isStale: Bool
    let isUnavailable: Bool

    static let preview = WidgetSnapshotPayload(
        statusTitle: "Water soon",
        statusSubtitle: "Dry for 5 days",
        lastMeaningfulRainDate: Calendar.current.date(byAdding: .day, value: -5, to: .now),
        dryDays: 5,
        observed7DayRainMM: 8.2,
        forecast48hRainMM: 1.1,
        updatedAt: .now,
        isStale: false,
        isUnavailable: false
    )

    static func setupNeeded(now: Date = .now) -> WidgetSnapshotPayload {
        WidgetSnapshotPayload(
            statusTitle: "Set up your garden",
            statusSubtitle: "Add your garden location to get started.",
            lastMeaningfulRainDate: nil,
            dryDays: 0,
            observed7DayRainMM: 0,
            forecast48hRainMM: 0,
            updatedAt: now,
            isStale: false,
            isUnavailable: false
        )
    }

    static func unavailable(now: Date = .now) -> WidgetSnapshotPayload {
        WidgetSnapshotPayload(
            statusTitle: "Weather unavailable",
            statusSubtitle: "Open Dry Spell for the latest weather.",
            lastMeaningfulRainDate: nil,
            dryDays: 0,
            observed7DayRainMM: 0,
            forecast48hRainMM: 0,
            updatedAt: now,
            isStale: false,
            isUnavailable: true
        )
    }
}

private struct WidgetSnapshotReader {
    private static let logger = Logger(
        subsystem: "com.justinchapdelaine.dryspell",
        category: "Widget"
    )
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func read(now: Date = .now) -> WidgetSnapshotReadResult {
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: DrySpellConstants.appGroupIdentifier
            )
        else {
            Self.logger.error("Widget App Group container is unavailable while reading snapshot")
            return .unavailable(WidgetSnapshotPayload.unavailable(now: now))
        }

        let fileURL = containerURL.appending(
            path: DrySpellConstants.widgetSnapshotFilename,
            directoryHint: .notDirectory
        )

        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return .setupNeeded(WidgetSnapshotPayload.setupNeeded(now: now))
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return .snapshot(try decoder.decode(WidgetSnapshotPayload.self, from: data))
        } catch {
            Self.logger.error("Failed to read or decode widget snapshot: \(error.localizedDescription, privacy: .public)")
            return .unavailable(WidgetSnapshotPayload.unavailable(now: now))
        }
    }
}

private enum WidgetSnapshotReadResult {
    case snapshot(WidgetSnapshotPayload)
    case setupNeeded(WidgetSnapshotPayload)
    case unavailable(WidgetSnapshotPayload)

    var payload: WidgetSnapshotPayload {
        switch self {
        case .snapshot(let payload), .setupNeeded(let payload), .unavailable(let payload):
            return payload
        }
    }
}

private struct WidgetDisplayState {
    let title: String
    let subtitle: String
    let lastMeaningfulRainDate: Date?
    let dryDays: Int
    let observed7DayRainMM: Double
    let forecast48hRainMM: Double
    let updatedAt: Date
    let isStale: Bool
    let isUnavailable: Bool

    init(snapshot: WidgetSnapshotPayload, now: Date) {
        let age = now.timeIntervalSince(snapshot.updatedAt)
        let isAgedUnavailable = age >= 24 * 60 * 60
        let isAgedStale = age > 6 * 60 * 60 && !isAgedUnavailable

        self.title = isAgedUnavailable ? "Weather unavailable" : snapshot.statusTitle
        self.subtitle = isAgedUnavailable ? "Open Dry Spell for the latest weather." : snapshot.statusSubtitle
        self.lastMeaningfulRainDate = snapshot.lastMeaningfulRainDate
        self.dryDays = snapshot.dryDays
        self.observed7DayRainMM = snapshot.observed7DayRainMM
        self.forecast48hRainMM = snapshot.forecast48hRainMM
        self.updatedAt = snapshot.updatedAt
        self.isStale = snapshot.isStale || isAgedStale
        self.isUnavailable = snapshot.isUnavailable || isAgedUnavailable
    }

    var staleText: String {
        "Updated \(updatedAt.formatted(.relative(presentation: .named)))"
    }

    var lastRainText: String {
        guard let lastMeaningfulRainDate else {
            return "No recent rain"
        }

        return lastMeaningfulRainDate.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct DrySpellWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshotPayload
}

struct DrySpellWidgetTimelineProvider: TimelineProvider {
    private let snapshotReader = WidgetSnapshotReader()

    func placeholder(in context: Context) -> DrySpellWidgetEntry {
        DrySpellWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (DrySpellWidgetEntry) -> Void) {
        let now = Date()
        let snapshot = context.isPreview ? .preview : snapshotReader.read(now: now).payload
        completion(DrySpellWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DrySpellWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = snapshotReader.read(now: now).payload
        let entry = DrySpellWidgetEntry(date: now, snapshot: snapshot)
        let nextUpdate = nextRefreshDate(for: snapshot, now: now)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func nextRefreshDate(for snapshot: WidgetSnapshotPayload, now: Date) -> Date {
        let sixHourBoundary = snapshot.updatedAt.addingTimeInterval(6 * 60 * 60)
        let dayBoundary = snapshot.updatedAt.addingTimeInterval(24 * 60 * 60)

        if now < sixHourBoundary {
            return sixHourBoundary
        }

        if now < dayBoundary {
            return dayBoundary
        }

        return now.addingTimeInterval(60 * 60)
    }
}

struct DrySpellWidgetEntryView: View {
    let entry: DrySpellWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var display: WidgetDisplayState {
        WidgetDisplayState(snapshot: entry.snapshot, now: entry.date)
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumWidget
            default:
                smallWidget
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display.title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)

            Text(display.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            if display.isStale && !display.isUnavailable {
                Text(display.staleText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if display.dryDays > 0 && !display.isUnavailable {
                Text("Dry for \(display.dryDays) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(display.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                Text(display.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                widgetMetric(title: "Last rain", value: display.lastRainText)
                widgetMetric(title: "7-day rain", value: mmText(display.observed7DayRainMM))
                widgetMetric(title: "48h forecast", value: mmText(display.forecast48hRainMM))
            }

            Spacer(minLength: 0)

            Text(display.isUnavailable ? "Open Dry Spell for the latest weather." : display.staleText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private func widgetMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mmText(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) mm"
    }
}

struct DrySpellWidget: Widget {
    let kind = "DrySpellWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DrySpellWidgetTimelineProvider()) { entry in
            DrySpellWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Dry Spell")
        .description("See whether it's time to water at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    DrySpellWidget()
} timeline: {
    DrySpellWidgetEntry(date: .now, snapshot: .preview)
    DrySpellWidgetEntry(date: .now, snapshot: .setupNeeded())
    DrySpellWidgetEntry(date: .now, snapshot: .unavailable())
}

#Preview(as: .systemMedium) {
    DrySpellWidget()
} timeline: {
    DrySpellWidgetEntry(date: .now, snapshot: .preview)
}
