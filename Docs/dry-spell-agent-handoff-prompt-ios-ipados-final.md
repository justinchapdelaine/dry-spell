# Dry Spell — Agent Handoff Prompt

_Last validated against Apple’s current developer documentation on April 17, 2026._
## Product naming

Use this naming convention consistently throughout the project:

- **User-facing app name:** **Dry Spell**
- **Internal project / code style:** **DrySpell**
- Use **Dry Spell** for the app display name, user-visible strings, and end-user documentation.
- Use **DrySpell** for Xcode project names, target names, Swift symbols where appropriate, bundle identifiers, App Group identifiers, and internal filenames.


You are building **Dry Spell v1**, a production-quality **iOS/iPadOS SwiftUI app** with a **WidgetKit widget**.

You have been given **three markdown documents**:

1. **Coding agent instruction**
2. **Agent implementation plan**
3. **Product spec**

## Document priority

Use the documents in this exact order of authority:

1. **Coding agent instruction** — highest priority for how to work, how to interpret the docs, and what to do first.
2. **Agent implementation plan** — primary source of truth for architecture, implementation phases, constraints, engineering rules, file structure, and definition of done.
3. **Product spec** — supporting context for product intent, UX goals, recommendation behavior, rationale, and copy direction.

If any documents conflict:
- first follow the **coding agent instruction**
- then follow the **agent implementation plan**
- use the **product spec** only as supporting context

Do not invent new features or architecture outside those documents unless required for correctness by Apple’s current APIs.

## Mission

Build the app according to the provided documents using **Apple-native frameworks and current Apple-recommended patterns**.

The app must:
- track **one saved garden location**
- show **when it last meaningfully rained**
- compute a **watering recommendation**
- suppress reminders when **enough rain is forecast in the next 48 hours**
- allow the user to mark **Watered**
- expose a **simple non-configurable widget**
- use **only Apple-native frameworks** for v1

## Required stack

Use the Apple-native stack defined in the documents:
- **SwiftUI App**
- **iOS app target** configured for iPhone and iPad
- **WeatherKit**
- **SwiftData**
- **WidgetKit**
- **App Groups**
- **UserNotifications**
- **BackgroundTasks** where applicable
- **Swift Testing**

Do not add:
- third-party dependencies unless absolutely necessary
- a backend
- CloudKit or iCloud sync in v1
- configurable widgets in v1
- multi-location support in v1
- live location permission in v1

## Naming rule

- Use **Dry Spell** for the app display name, user-visible strings, marketing-style copy, and end-user-facing documentation.
- Use **DrySpell** for Xcode project names, target names, bundle identifiers, App Group identifiers, filenames when appropriate, and internal code naming.

## Working rules

- Keep business logic out of SwiftUI views.
- Keep the recommendation engine pure and deterministic.
- Keep the widget passive: it should render a precomputed shared snapshot instead of recomputing the full app logic.
- Keep reminders conservative: never create a new watering reminder from stale or unavailable weather data.
- Respect the exact recommendation priority, freshness rules, reminder rules, and state behavior in the documents.
- Preserve the native Apple-first design constraints from the implementation plan.
- Use system controls, system colors, system typography, and standard SwiftUI layout patterns unless the documents explicitly say otherwise.
- Prefer the smallest correct implementation that satisfies the documents.

## How to execute

Follow the **implementation phases in order** from the agent implementation plan.

At the end of each phase:
- ensure the project builds
- keep changes scoped to that phase
- avoid unrelated refactors
- verify the implemented work matches the documents before continuing

Do not jump ahead to polish before the core logic is correct.

## Handling ambiguity

When a detail is ambiguous:
- consult the **coding agent instruction** first
- then the **agent implementation plan**
- then the **product spec** for intent
- choose the simplest Apple-native implementation that satisfies all three

When a necessary detail is missing:
- make the smallest reasonable assumption
- keep the implementation easy to revise later
- document the assumption briefly only if needed

## Output expectations

Produce:
- working code
- small, reviewable commits grouped by phase
- minimal comments, only where logic is non-obvious
- tests for the core logic described in the implementation plan
- a short `README.md` with setup/run notes
- a `KNOWN_ISSUES.md` only if something cannot be completed cleanly

## Quality bar

The implementation is not complete until it satisfies the implementation plan’s definition of done, including:
- correct WeatherKit integration
- correct recommendation logic
- correct stale/unavailable handling
- correct reminder scheduling behavior
- correct widget behavior
- required WeatherKit attribution
- passing core tests

## First task

Start with **Phase 1 only**.

Create the Xcode SwiftUI app skeleton for Dry Spell v1, configured for iPhone and iPad, add the widget target, set the iOS deployment target to 26.0 and support iPhone and iPad, add the required capabilities, set up SwiftData, create the folder structure and empty model/service files, and stop.
