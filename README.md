# Dry Spell

Dry Spell is a SwiftUI iPhone and iPad app that tracks one saved garden location, shows when it last meaningfully rained, recommends whether to water, schedules conservative reminders, and publishes a passive WidgetKit widget.

## Requirements

- Xcode 26.4 or newer
- iOS 26 / iPadOS 26 simulator or device
- Apple Developer Program signing with WeatherKit enabled for `com.justinchapdelaine.dryspell`
- App Groups enabled for:
  - `com.justinchapdelaine.dryspell`
  - `com.justinchapdelaine.dryspell.widget`

## Setup

1. Open `/Users/justin/Developer/DrySpell/DrySpell.xcodeproj` in Xcode.
2. Set your signing team on the `DrySpellApp` and `DrySpellWidgetExtension` targets.
3. Confirm the WeatherKit capability is enabled on `DrySpellApp`.
4. Confirm the App Group `group.com.justinchapdelaine.dryspell` is enabled on both the app and widget targets.
5. Build and run the `DrySpellApp` scheme.

## Notes

- The widget reads a shared snapshot from the app and does not fetch WeatherKit data directly.
- Background refresh is opportunistic and should be treated as a helpful enhancement, not a guarantee.
- If WeatherKit requests fail with JWT authorization errors, re-check the Apple Developer portal App ID capability setup and the selected signing team in Xcode.
