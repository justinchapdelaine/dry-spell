# Dry Spell — AI Coding Agent Implementation Plan (v1)

_Last validated against Apple’s current developer documentation on April 17, 2026._

## Product naming

Use this naming convention consistently throughout the project:

- **User-facing app name:** **Dry Spell**
- **Internal project / code style:** **DrySpell**
- Use **Dry Spell** for the app display name, user-visible strings, and end-user documentation.
- Use **DrySpell** for Xcode project names, target names, Swift symbols where appropriate, bundle identifiers, App Group identifiers, and internal filenames.

## 1. Purpose

Build a production-quality **iOS/iPadOS SwiftUI app** with a **WidgetKit widget** that helps a user decide whether to water their garden or yard.

The app must:

- track **one user-provided garden location**
- show **days since last meaningful rain**
- compute a **watering recommendation**
- suppress reminders if **enough rain is forecast in the next 48 hours**
- let the user manually mark **Watered**
- show status in a **simple non-configurable widget**
- use **only Apple-native frameworks** for v1

Do not build a backend. Do not use third-party dependencies unless absolutely necessary.

## 2. Required Apple stack

Use these frameworks and patterns:

- **SwiftUI App** for app lifecycle and UI
- **iOS app target** configured for iPhone and iPad
- **WeatherKit** for weather data
- **SwiftData** for app persistence
- **WidgetKit** for the widget
- **TimelineProvider** for widget updates
- **App Groups** for sharing a precomputed widget snapshot
- **UserNotifications** for local reminders
- **BackgroundTasks** for opportunistic background refresh on **iOS and iPadOS**
- **Swift Testing** for core tests

Do not replace any of the above with older or alternate patterns unless technically required.

## 3. Fixed product constraints

These are locked for v1:

- deployment target: **iOS 26.0** with **iPhone and iPad** device support
- build with **Xcode 26 or later**
- one saved garden location
- no live device location in v1
- no configurable widget in v1
- no backend
- no cloud sync
- no multi-location support
- no push notifications
- reminders are **local notifications only**
- default dry-day threshold: **5 days**
- allowed dry-day thresholds: **3, 5, 7**
- meaningful-rain display threshold: **2.5 mm**
- default weekly water target: **25.4 mm**
- forecast suppression window: **48 hours**
- default reminder delivery time: **9:00 AM local time**
- widget families: **small** and **medium**

## 4. Core product rules

### Display metric

Show:

- “Last meaningful rain: X days ago”

This is a user-facing display metric only.

### Decision metric

Use a **7-day water-deficit model** for recommendations and reminders.

Inputs:

- observed rain in trailing 7 days
- forecast rain in next 48 hours
- manual watering credit
- dry-day count
- dry-day threshold
- weekly water target

Definitions:

- `weeklyTargetMM = 25.4`
- `meaningfulRainDayThresholdMM = 2.5`
- `forecastSuppressionWindowHours = 48`

### Manual watering rule

When the user taps **Mark Watered**:

- create a manual watering event with timestamp
- apply enough watering credit to eliminate the current deficit, capped at the weekly target
- mark the recommendation as `recentlyWatered` for the rest of the day
- cancel any pending reminder immediately

### Recommendation priority

Use this exact order:

1. `setupNeeded`
2. `weatherUnavailable`
3. `recentlyWatered`
4. `rainExpected`
5. `waterSoon`
6. `okayForNow`

### Reminder eligibility

A reminder is eligible only when:

- reminders are enabled
- a saved location exists
- weather data is fresh enough
- `dryDays >= dryDayThreshold`
- deficit is greater than zero
- forecast suppression is false
- user has not marked watered today

## 5. Freshness and failure rules

### Freshness buckets

- `fresh`: updated within 6 hours
- `stale`: older than 6 hours and less than 24 hours
- `tooStale`: 24 hours or older

### Empty state

Condition:

- no saved location

Behavior:

- app shows onboarding/setup prompt
- widget shows `Set up in app`
- do not schedule reminders

### Stale state

Condition:

- snapshot age > 6h and < 24h

Behavior:

- app shows last known recommendation plus updated time
- widget shows last known status plus stale cue
- do not silently treat data as fully current

### Too stale / unavailable state

Condition:

- snapshot age >= 24h
- or latest fetch failed and no fresh usable snapshot exists

Behavior:

- app shows `Weather update needed` or `Weather unavailable`
- widget shows `Weather unavailable`
- do not schedule a new reminder

### Failure rule

Never create a new watering reminder from stale or failed weather data.

## 6. Location handling

Use a **user-provided location**, not current device location.

Recommended onboarding approach:

- use **MKLocalSearchCompleter** to suggest places as the user types
- resolve the selected result to a coordinate using **MKLocalSearch**
- store latitude, longitude, display name, and timezone
- optionally reverse geocode to improve display formatting with **CLGeocoder**

Do not request location permission in v1.

## 7. Required project structure

### Project naming defaults

Unless the user later overrides identifiers, use these defaults when creating the project scaffold:

- **App display name:** `Dry Spell`
- **Project name:** `DrySpell`
- **App target:** `DrySpellApp`
- **Widget target:** `DrySpellWidgetExtension`
- **Test target:** `DrySpellTests`
- **Bundle identifier pattern:** `com.yourname.dryspell`
- **Widget bundle identifier pattern:** `com.yourname.dryspell.widget`
- **App Group identifier pattern:** `group.com.yourname.dryspell`

Create these targets:

- `DrySpellApp`
- `DrySpellWidgetExtension`
- `DrySpellTests`

Use this folder structure:

- `App/`
- `Models/`
- `Persistence/`
- `Services/Weather/`
- `Services/Recommendations/`
- `Services/Notifications/`
- `Services/BackgroundRefresh/`
- `Services/WidgetSharing/`
- `Features/Onboarding/`
- `Features/Home/`
- `Features/Settings/`
- `Widget/`
- `SharedUI/`
- `Tests/`

## 8. Required data models

Implement these SwiftData models in the main app.

### `GardenProfile`

Fields:

- `id`
- `displayName`
- `latitude`
- `longitude`
- `timeZoneIdentifier`
- `dryDayThresholdDays`
- `notificationsEnabled`
- `notificationHour`
- `createdAt`
- `updatedAt`

### `WeatherSnapshot`

Fields:

- `id`
- `fetchedAt`
- `lastMeaningfulRainDate`
- `observed7DayRainMM`
- `forecast48hRainMM`
- `effective7DayMoistureMM`
- `deficitMM`
- `dryDays`
- `recommendationRawValue`
- `isForecastSuppressed`
- `isStale`
- `attributionText`
- `attributionURLString`

### `ManualWaterEvent`

Fields:

- `id`
- `occurredAt`
- `creditedMM`
- `sourceRawValue`

### `WidgetSnapshot`

Do **not** make this a full app model. Write it as a compact encoded payload to the shared App Group container.

Fields:

- `statusTitle`
- `statusSubtitle`
- `lastMeaningfulRainDate`
- `dryDays`
- `observed7DayRainMM`
- `forecast48hRainMM`
- `updatedAt`
- `isStale`
- `isUnavailable`

## 9. Required services

Implement these services as separate types. Do not embed business logic directly in SwiftUI views.

### `LocationSearchService`

Responsibilities:

- autocomplete user text
- resolve a selected location into a coordinate and display name

### `WeatherClient`

Responsibilities:

- fetch recent daily summaries from WeatherKit
- fetch hourly forecast data from WeatherKit
- fetch WeatherKit attribution

### `RecommendationEngine`

Responsibilities:

- pure deterministic logic
- compute display values
- compute effective moisture
- compute deficit
- compute forecast suppression
- compute final recommendation
- compute explanation text

This must be a **pure Swift** type with no UI code and no direct framework side effects.

### `NotificationScheduler`

Responsibilities:

- request authorization when user enables reminders
- check current notification authorization status before scheduling
- schedule one next reminder only
- cancel reminders when ineligible

### `WidgetSnapshotStore`

Responsibilities:

- encode and write widget snapshot to App Group container
- read widget snapshot in the extension
- provide sample snapshot data for widget previews
- trigger widget timeline reloads after snapshot updates

### `BackgroundRefreshService`

Responsibilities:

- iOS/iPadOS service
- register a `BGAppRefreshTask`
- refresh weather
- recompute recommendation
- update persistence
- rewrite widget snapshot
- reschedule next reminder
- resubmit the next background refresh request

## 10. Required UI

### Onboarding flow

Implement:

1. Welcome
2. Location search
3. Confirm selected location
4. Dry-day threshold picker
5. Reminder opt-in

Do not ask for notification permission until the user explicitly turns reminders on.

### Home screen

Must show:

- large recommendation headline
- last meaningful rain
- observed 7-day rain total
- forecast next 48h rain total
- weekly target
- concise explanation
- buttons:
  - `Mark Watered`
  - `Refresh Weather`
  - `Settings`

### Settings screen

Must allow:

- change saved location
- change dry-day threshold
- enable or disable reminders
- choose reminder hour
- view weather attribution
- view app version and build

### Widget

Implement:

- small widget
- medium widget

States:

- `Set up in app`
- `Water soon`
- `Rain expected`
- `Okay for now`
- `Weather unavailable`

Map `recentlyWatered` to widget copy equivalent to **Okay for now · Watered today**.

## 11. Design constraints

Build v1 with a **clean native Apple look** using standard SwiftUI patterns and system styling.

### Design goals

- prioritize **glanceability** over density
- make the current watering recommendation the most prominent element on screen
- keep the app calm, simple, and trustworthy
- prefer clarity and legibility over decorative styling

### Visual rules

- use **system colors**, **system typography**, **system spacing**, and **standard SwiftUI controls** by default
- use **SF Symbols** where icons are needed
- use native materials and platform-default container styling where appropriate
- do not add custom gradients, branded illustration systems, or highly stylized UI in v1
- support light and dark mode automatically using system colors
- keep visual hierarchy simple: one primary headline, a small number of secondary metrics, then actions

### Layout rules

- the home screen should be a **single vertically scrolling view**
- the recommendation header should appear first and be visually dominant
- group related information into a small number of clear sections:
  1. current recommendation
  2. last rain and moisture metrics
  3. explanation
  4. actions
- avoid dense dashboards, multi-column analytical layouts, or deeply nested navigation in v1
- on iPad, keep the same information hierarchy as iPhone while allowing roomier spacing or a wider layout where it improves readability

### Interaction rules

- the primary action on the home screen is **Mark Watered**
- **Refresh Weather** and **Settings** are secondary actions
- onboarding should feel short and linear
- settings should use standard form-style layouts
- do not hide important status behind gestures, hover-only controls, or custom interactions

### Widget design rules

- the widget must be immediately readable in one glance
- prefer short status phrases such as:
  - `Water soon`
  - `Rain expected`
  - `Okay for now`
  - `Weather unavailable`
  - `Set up in app`
- do not crowd the widget with too many numbers
- the small widget should show only the most important status and one supporting detail
- the medium widget may show a few additional metrics, but must still remain glanceable

### Copy and tone

- use short, plain, friendly copy
- avoid technical weather jargon where possible
- prefer direct phrasing such as `Last meaningful rain: 5 days ago`
- keep explanation text concise and actionable

### Accessibility requirements

- support Dynamic Type where applicable on iOS
- ensure good contrast in light and dark mode
- provide accessibility labels for icons and key status elements
- do not communicate status by color alone
- make tap targets comfortably usable on touch devices

### Platform behavior

- share as much UI as practical between iPhone and iPad
- keep the same core product experience on both size classes unless an iPad adjustment improves readability
- do not add iPhone-specific or iPad-specific feature branches unless necessary for correctness

### Explicitly defer for v1

Do not spend time on:

- custom branding systems
- custom animation systems
- illustration work
- advanced transitions
- elaborate charts
- theme customization
- configurable widget styling

The goal for v1 is a polished **native Apple-first interface**, not a fully branded visual system.

## 12. Implementation order

Build in this exact order.

### Phase 1 — project setup

- create iOS SwiftUI app target configured for iPhone and iPad
- add WidgetKit extension target
- add WeatherKit capability
- add App Groups capability to app and widget
- set up notification permission flow
- on iOS, add `BGTaskSchedulerPermittedIdentifiers` and required background modes for app refresh
- set up SwiftData model container
- set up shared App Group identifier constant

### Phase 2 — models and persistence

- implement all model types
- seed empty app state
- persist and load `GardenProfile`
- persist and load `WeatherSnapshot`
- persist `ManualWaterEvent`
- implement `WidgetSnapshot` encoding and decoding

### Phase 3 — location onboarding

- implement location search UI
- implement place selection
- store selected coordinate and timezone
- complete onboarding flow
- handle no-results and invalid-location states

### Phase 4 — weather integration

- implement WeatherKit fetches
- compute:
  - last meaningful rain date
  - observed 7-day rain total
  - dry days
  - forecast 48-hour rain total
- fetch attribution metadata
- store a fresh `WeatherSnapshot`

### Phase 5 — recommendation engine

- implement pure logic engine
- map snapshot and manual water events into recommendation
- generate user-facing explanation text
- handle stale, unavailable, and setup states exactly as specified

### Phase 6 — home and settings UI

- render recommendation
- render metrics
- render actions
- render stale and unavailable labels
- add `Mark Watered`
- add manual refresh
- add settings editing

### Phase 7 — reminders

- request notification authorization only when enabled
- check authorization status
- schedule one next local reminder
- cancel reminders on ineligibility
- reschedule after refresh, settings change, or manual watering

### Phase 8 — widget

- read compact snapshot from App Group
- implement small and medium layouts
- implement placeholder and preview data
- implement timeline entries
- reload widget timelines after app snapshot writes

### Phase 9 — background refresh and polish

- on iOS, register background refresh task
- on iOS, submit one refresh request at a time
- refresh weather and reschedule outputs
- polish accessibility
- polish empty, stale, and failure copy
- verify attribution display

## 13. Non-negotiable engineering rules

- Do not put business logic in views.
- Do not let the widget recompute full weather logic.
- Do not use live location permission in v1.
- Do not add a backend.
- Do not add CloudKit or iCloud sync in v1.
- Do not use Core Data unless SwiftData becomes impossible.
- Do not use a configurable widget in v1.
- Do not schedule many future reminders; keep exactly one pending reminder.
- Do not send reminders when weather is stale or unavailable.
- Do not ship without WeatherKit attribution.

## 14. Testing requirements

Use **Swift Testing** for new tests. At minimum, write tests for:

### `RecommendationEngine`

- setup needed
- unavailable state
- stale state
- exactly at dry threshold
- below dry threshold
- positive deficit with no forecast coverage
- positive deficit with enough forecast coverage
- recently watered today
- rain resets dry streak
- long dry spell with persisted last-rain date

### `NotificationScheduler`

- schedules when eligible
- does not schedule when stale
- does not schedule when forecast suppressed
- cancels after manual watering
- cancels after disabling reminders

### `WeatherClient`

- maps daily summaries correctly
- sums 7-day observed rain correctly
- sums 48-hour hourly forecast correctly

### `WidgetSnapshotStore`

- writes and reads snapshot correctly
- maps recommendation state to widget copy correctly

## 15. Definition of done

The app is done for v1 only when all of these are true:

- builds and runs on iOS 26 and iPadOS 26
- user can set exactly one location
- app fetches WeatherKit data successfully
- app computes the recommendation correctly
- user can mark `Watered`
- user can enable or disable reminders
- reminders schedule only when eligible
- widget displays latest shared status
- stale and unavailable states behave exactly as specified
- no reminder is created from stale or failed data
- WeatherKit attribution is visible where required
- tests cover core logic and pass

## 16. Agent output expectations

While implementing, produce:

- working code
- minimal comments only where logic is non-obvious
- small commits by phase
- a short `README.md` with setup steps
- a `KNOWN_ISSUES.md` only if something cannot be completed cleanly

If there is a conflict between convenience and the spec, follow the spec.

## 17. Recommended first prompt to give the coding agent

Start by asking it to do only this:

> Create the Xcode SwiftUI app skeleton for Dry Spell v1, configured for iPhone and iPad, add the widget target, set the iOS deployment target to 26.0 and support iPhone and iPad, add WeatherKit and App Groups capabilities, set up SwiftData, create the folder structure and empty model and service files, and stop.
