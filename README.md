# Dry Spell

Dry Spell is a SwiftUI iPhone and iPad app that tracks one saved garden location, shows when it last meaningfully rained, recommends whether to water, schedules conservative reminders, and publishes a passive WidgetKit widget.

## Requirements

- Xcode 26.4 or newer
- iOS 26 / iPadOS 26 simulator or device
- Apple Developer Program signing with WeatherKit enabled for your app bundle identifier
- App Groups enabled for both the app target and widget target

## Setup

1. Open `DrySpell.xcodeproj` in Xcode.
2. Set your signing team on the `DrySpellApp` and `DrySpellWidgetExtension` targets.
3. Set a unique bundle identifier for the app and widget targets that matches identifiers enabled in your Apple Developer account.
4. Confirm the WeatherKit capability is enabled on `DrySpellApp`.
5. Configure one shared App Group identifier and enable it on both the app and widget targets.
6. Build and run the `DrySpellApp` scheme.

## Notes

- The widget reads a shared snapshot from the app and does not fetch WeatherKit data directly.
- Background refresh is opportunistic and should be treated as a helpful enhancement, not a guarantee.
- If WeatherKit requests fail with JWT authorization errors, re-check the Apple Developer portal capability setup, bundle identifiers, App Group configuration, and the selected signing team in Xcode.
