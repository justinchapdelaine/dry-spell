# Dry Spell — Product Spec (v1)

_Last validated against Apple’s current developer documentation on April 17, 2026._

## Product naming

Use this naming convention consistently throughout the project:

- **User-facing app name:** **Dry Spell**
- **Internal project / code style:** **DrySpell**
- Use **Dry Spell** for the app display name, user-visible strings, and end-user documentation.
- Use **DrySpell** for Xcode project names, target names, Swift symbols where appropriate, bundle identifiers, App Group identifiers, and internal filenames.

## 1. Foundation

This product is defined for:

- **iOS 26**
- **iPadOS 26**
- **Xcode 26 or later**

Use Apple’s current native stack for this app:

- **SwiftUI** with an **iOS app target configured for iPhone and iPad**
- **WidgetKit** for the widget
- **WeatherKit** for weather data
- **SwiftData** for app persistence
- **UserNotifications** for local reminders
- **App Groups** for app/widget shared data
- **BackgroundTasks** on **iOS and iPadOS** for opportunistic refresh

## 2. Product summary

Dry Spell helps a person decide whether they should water their garden or yard.

The app tracks **one saved garden location**, shows **when it last meaningfully rained**, measures the **last 7 days of effective moisture**, checks whether **enough rain is forecast in the next 48 hours**, and recommends one of:

- **Water soon**
- **Rain expected**
- **Okay for now**
- **Recently watered**
- **Weather unavailable**
- **Set up your garden**

The main app performs the weather and recommendation logic. The widget stays simple and fast by reading a compact shared snapshot rather than recomputing the full recommendation model.

## 3. Goals

### Primary goals

- Show a clear, glanceable answer about watering need.
- Show **days since last meaningful rain**.
- Avoid nuisance reminders by suppressing alerts when enough rain is forecast soon.
- Work well on iPhone and iPad, with a simple widget.

### Non-goals for v1

- Multiple saved locations
- Live device location as the core location model
- Configurable widgets
- Soil-type tuning
- Irrigation hardware integration
- Server-backed push reminder logic
- Cloud sync

## 4. Locked product decisions for v1

### Platform and architecture

- Deployment targets: **iOS 26** and **iPadOS 26**
- App type: **SwiftUI iOS app supporting iPhone and iPad**
- Widget: **non-configurable**
- Persistence: **SwiftData**
- Widget sharing: **App Group shared snapshot**
- Notifications: **local notifications only**
- Weather source: **WeatherKit**
- Background refresh: **iOS/iPadOS only**, opportunistic, never correctness-critical

### User model

- One saved garden location, entered by the user
- No current-location permission required in v1
- One default watering model in v1, structured so presets can be added later

### Reminder model

- User can enable reminders
- User can choose a dry-day threshold
- Default forecast suppression window: **48 hours**
- User can mark **Watered**
- Daily repeat reminders continue only while conditions still support them

## 5. User experience

### 5.1 Onboarding

On first launch, the user sees a short setup flow:

1. Enter or search for the garden location.
2. Confirm the selected location.
3. Choose a dry-day threshold: **3, 5, or 7 days**.
4. Enable reminders or skip them.
5. Land on the main dashboard.

Suggested onboarding copy:

- “Track rainfall for one garden location.”
- “Get reminded when it has been dry, unless enough rain is coming soon.”

### 5.2 Main dashboard

The main dashboard is a single primary screen with five blocks.

#### A. Status header

Large recommendation text:

- **Water soon**
- **Rain expected**
- **Okay for now**
- **Recently watered**
- **Weather unavailable**
- **Set up your garden**

#### B. Last rain

- “Last meaningful rain: **5 days ago**”
- Secondary line with the exact date

#### C. Moisture summary

- “Rain in last 7 days: **12 mm**”
- “Rain forecast next 48h: **8 mm**”
- “Weekly target: **25.4 mm**”

#### D. Recommendation explanation

Examples:

- “Dry threshold reached and no meaningful rain is forecast.”
- “Dry threshold reached, but enough rain is forecast in the next 48 hours.”
- “You marked watered today.”

#### E. Actions

- **Mark Watered**
- **Refresh Weather**
- **Open Settings**

### 5.3 Settings

Settings contains:

- Saved location
- Dry-day threshold: **3 / 5 / 7**
- Reminders on/off
- Reminder time: default **9:00 AM local time**
- Weather attribution section
- About / privacy

### 5.4 Widget

The widget is intentionally simple and reads a precomputed shared snapshot.

Supported families for v1:

- **Small**
- **Medium**

Small widget examples:

- “Dry 5 days · Water soon”
- “Dry 5 days · Rain expected”
- “Okay for now · Watered today”
- “Weather unavailable”
- “Set up in app”

Medium widget can also show:

- last meaningful rain date
- 7-day rain total
- 48-hour forecast rain
- updated time

## 6. Recommendation model

### 6.1 Key definitions

#### Weekly water target

For v1, use a single baseline target of **25.4 mm (1 inch) of water per 7 days**.

This is a sensible default for a mixed garden/yard reminder app, while leaving room for later presets such as lawn, vegetables, flowers, or custom.

#### Meaningful rain day

A “meaningful rain day” is the most recent day where observed precipitation is at least:

- **2.5 mm (0.1 inch)**

This threshold is for the **last-rain display**, not the entire watering decision.

#### Dry-day threshold

User-selectable:

- **3 days**
- **5 days**
- **7 days**

Default:

- **5 days**

#### Forecast suppression window

- **48 hours**

#### Freshness thresholds

- **Fresh:** updated within 6 hours
- **Stale:** more than 6 hours old, but less than 24 hours old
- **Too stale for decisions:** 24 hours old or more

### 6.2 Two-model approach

The app uses two different concepts.

#### A. Display metric

**Days since last meaningful rain**

This is for human readability:

- “Last meaningful rain: 5 days ago”

#### B. Decision metric

**7-day water deficit with forecast suppression**

This decides whether to notify:

- observed rain in the trailing 7 days
- plus manual watering credit
- compared against the weekly water target
- then checked against forecast rain in the next 48 hours

### 6.3 Calculation inputs

- `weeklyTargetMM = 25.4`
- `observed7DayRainMM`
- `forecast48hRainMM`
- `manualWaterCreditMM`
- `dryDays`
- `dryDayThreshold`

### 6.4 Manual watering behavior

When the user taps **Mark Watered**:

- create a manual watering event timestamp
- add a watering credit equal to the current remaining deficit
- cap the resulting effective moisture so it does not exceed the weekly target
- immediately clear any pending reminder
- show **Recently watered** for the rest of that day

This keeps the model simple without pretending to know the exact liters or gallons the user applied.

### 6.5 Effective moisture and deficit

`effective7DayMoistureMM = min(weeklyTargetMM, observed7DayRainMM + manualWaterCreditMM)`

`deficitMM = max(0, weeklyTargetMM - effective7DayMoistureMM)`

### 6.6 Forecast suppression

`forecastSuppressed = forecast48hRainMM >= deficitMM`

Only evaluate this when `deficitMM > 0`.

### 6.7 Recommendation priority

Use this order:

1. **Set up your garden**  
   No saved location yet.
2. **Weather unavailable**  
   No usable weather snapshot, or data older than 24 hours.
3. **Recently watered**  
   User marked watered today.
4. **Rain expected**  
   Dry threshold reached, deficit exists, and the 48-hour forecast covers the deficit.
5. **Water soon**  
   Dry threshold reached, deficit exists, and the forecast does not cover it.
6. **Okay for now**  
   All other valid cases.

## 7. Weather data plan

Use these WeatherKit inputs.

### Historical / recent

Use **daily summaries for the past 30 days** to determine:

- the last meaningful rain day
- recent observed precipitation
- long dry periods that need to be carried forward in local persistence

### Forecast

Use the **hourly forecast** to sum precipitation expected in the next 48 hours.

Use the **daily forecast** only as a display fallback if needed.

Do **not** depend on minute-by-minute forecast for v1.

### Long dry spells

Because WeatherKit daily summaries only cover the recent 30-day window, the app should persist the most recent meaningful-rain date locally and keep carrying it forward if newer fetches still show no qualifying rain.

## 8. Notifications

Use **local notifications**.

### Reminder trigger conditions

A reminder is eligible only when all are true:

- reminders are enabled
- location is set
- weather data is fresh enough
- `dryDays >= dryDayThreshold`
- `deficitMM > 0`
- `forecastSuppressed == false`
- user has not marked watered today

### Reminder cadence

- Preferred delivery time: **9:00 AM local time**
- Best-effort daily repeat while conditions remain true

### Conservative scheduling rule

To avoid stale or incorrect nagging:

- schedule **at most one upcoming reminder** at a time
- reschedule whenever the app refreshes weather or the user acts
- cancel immediately when:
  - user marks watered
  - meaningful rain occurs
  - forecast suppression becomes active
  - reminders are turned off
  - weather becomes too stale to trust

### Background refresh

On **iOS and iPadOS**, use background app refresh opportunistically to refresh weather and reschedule the next reminder.

Do not rely on exact timing.

Treat background refresh as a helpful enhancement, not a guarantee.

## 9. Empty, stale, and failure states

### 9.1 Empty state

Condition:

- no saved location

Behavior:

- app shows setup prompt
- widget shows “Set up in app”
- no reminders scheduled

### 9.2 Stale state

Condition:

- weather snapshot older than 6 hours but less than 24 hours

Behavior:

- show last known recommendation
- show updated time
- allow reading, but communicate that the data is not fresh

Examples:

- “Rain expected · Updated 8h ago”
- “Water soon · Updated 10h ago”

### 9.3 Too stale for decision-making

Condition:

- weather snapshot 24 hours old or older

Behavior:

- app shows **Weather update needed**
- widget shows **Weather unavailable**
- no new reminder is scheduled

### 9.4 Fetch failure

Condition:

- WeatherKit request fails

Behavior:

- retain the last successful snapshot for display
- mark state as stale or unavailable based on age
- do not create a new reminder from failed refresh
- retry on the next normal refresh opportunity

## 10. Data model

Use **SwiftData** in the main app.

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
- `recommendation`
- `isForecastSuppressed`
- `isStale`
- `attributionText`
- `attributionURL`

### `ManualWaterEvent`

Fields:

- `id`
- `occurredAt`
- `creditedMM`
- `source`

### `SharedWidgetSnapshot`

Store this in the **App Group container** as a small encoded payload, not as the full app state.

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

## 11. Project structure

### Targets

- `DrySpellApp` — iOS app target for iPhone and iPad
- `DrySpellWidgetExtension` — WidgetKit extension

### Suggested folders

- `App/`
- `Features/Home/`
- `Features/Onboarding/`
- `Features/Settings/`
- `Models/`
- `Services/Weather/`
- `Services/Recommendations/`
- `Services/Notifications/`
- `Services/BackgroundRefresh/`
- `Services/WidgetSharing/`
- `Persistence/`
- `Widget/`
- `SharedUI/`

### Key services

- `LocationSearchService`
- `WeatherClient`
- `RecommendationEngine`
- `NotificationScheduler`
- `BackgroundRefreshService`
- `WidgetSnapshotStore`
- `AttributionProvider`

## 12. Widget implementation notes

The widget must not perform the app’s full weather-analysis logic. It should read the latest shared snapshot and render it.

### Widget timeline strategy

- create timeline entries every few hours
- reload timelines after the app writes a new shared snapshot
- do not treat the widget as real-time

### Widget state mapping

- **Setup needed** — “Set up in app”
- **Water soon** — “Dry 5 days · Water soon”
- **Rain expected** — “Dry 5 days · Rain expected”
- **Recently watered** — “Okay for now · Watered today”
- **Okay for now** — “Okay for now”
- **Stale** — “Updated 9h ago”
- **Unavailable** — “Weather unavailable”

## 13. Permissions, privacy, and attribution

### Permissions

- No location permission in v1
- Notification permission only if the user enables reminders

### Privacy stance

- One user-provided location
- No account system in v1
- No cloud sync required in v1

### Weather attribution

WeatherKit attribution is required and must be shown in the app anywhere Apple’s weather data is displayed in a way that requires attribution.

## 14. Future-ready but not in v1

These are intentionally deferred:

- multiple saved gardens
- configurable widgets via App Intents
- current-location setup
- soil type and sun exposure inputs
- crop-specific presets
- iCloud sync across devices
- watch app
- server-backed smarter reminders

## 15. Final v1 summary

Build this app as a **SwiftUI iOS/iPadOS app** with a **simple WidgetKit widget**, **WeatherKit-backed rain and forecast analysis**, **SwiftData persistence**, **local notifications**, and a **shared App Group snapshot**.

The UI should center on **days since meaningful rain**, but the recommendation engine should use a **7-day water-deficit model plus 48-hour forecast suppression** so reminders stay practical rather than naive.
