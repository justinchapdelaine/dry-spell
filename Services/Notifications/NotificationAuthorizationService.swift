import Foundation
import UserNotifications

struct ScheduledNotificationRequest: Sendable {
    let identifier: String
    let title: String
    let body: String
    let dateComponents: DateComponents
}

protocol UserNotificationCenterClient: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: ScheduledNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
}

struct SystemUserNotificationCenterClient: UserNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func add(_ request: ScheduledNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: request.dateComponents,
            repeats: false
        )
        let notificationRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(notificationRequest) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

struct NotificationAuthorizationService {
    private let centerClient: UserNotificationCenterClient

    init(centerClient: UserNotificationCenterClient = SystemUserNotificationCenterClient()) {
        self.centerClient = centerClient
    }

    func requestAuthorization() async throws -> Bool {
        try await centerClient.requestAuthorization(options: [.alert, .badge, .sound])
    }
}

struct NotificationScheduler {
    private let centerClient: UserNotificationCenterClient
    private let recommendationEngine: RecommendationEngine

    init(
        centerClient: UserNotificationCenterClient = SystemUserNotificationCenterClient(),
        recommendationEngine: RecommendationEngine = RecommendationEngine()
    ) {
        self.centerClient = centerClient
        self.recommendationEngine = recommendationEngine
    }

    func syncReminder(
        gardenProfile: GardenProfile?,
        weatherSnapshot: WeatherSnapshot?,
        manualWaterEvents: [ManualWaterEvent],
        now: Date = .now
    ) async throws {
        await cancelReminder()

        guard let gardenProfile, gardenProfile.notificationsEnabled else {
            return
        }

        let authorizationStatus = await centerClient.authorizationStatus()

        guard authorizationStatus.allowsScheduling else {
            return
        }

        let calendar = calendar(for: gardenProfile.timeZoneIdentifier)
        let recommendation = recommendationEngine.evaluate(
            gardenProfile: gardenProfile,
            weatherSnapshot: weatherSnapshot,
            manualWaterEvents: manualWaterEvents,
            now: now,
            calendar: calendar
        )

        guard recommendation.status == .waterSoon,
              recommendation.freshness == .fresh,
              !recommendation.isUnavailable else {
            return
        }

        try await centerClient.add(
            ScheduledNotificationRequest(
                identifier: DrySpellConstants.wateringReminderIdentifier,
                title: "Water soon",
                body: "\(gardenProfile.displayName) has been dry for \(weatherSnapshot?.dryDays ?? 0) days. Dry Spell recommends watering today.",
                dateComponents: nextReminderDateComponents(
                    notificationHour: gardenProfile.notificationHour,
                    timeZoneIdentifier: gardenProfile.timeZoneIdentifier,
                    now: now
                )
            )
        )
    }

    func cancelReminder() async {
        await centerClient.removePendingNotificationRequests(
            withIdentifiers: [DrySpellConstants.wateringReminderIdentifier]
        )
    }

    func nextReminderDateComponents(
        notificationHour: Int,
        timeZoneIdentifier: String,
        now: Date
    ) -> DateComponents {
        let calendar = calendar(for: timeZoneIdentifier)
        let reminderHour = min(max(notificationHour, 0), 23)
        let todayReminderDate = calendar.date(
            bySettingHour: reminderHour,
            minute: 0,
            second: 0,
            of: now
        ) ?? now
        let reminderDate: Date

        if todayReminderDate > now {
            reminderDate = todayReminderDate
        } else {
            reminderDate = calendar.date(byAdding: .day, value: 1, to: todayReminderDate) ?? todayReminderDate
        }

        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        components.timeZone = calendar.timeZone
        return components
    }

    private func calendar(for timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }
}

private extension UNAuthorizationStatus {
    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}
