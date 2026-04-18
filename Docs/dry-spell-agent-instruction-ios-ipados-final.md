# Dry Spell — Coding Agent Instruction

_Last validated against Apple’s current developer documentation on April 17, 2026._

## Product naming

Use this naming convention consistently throughout the project:

- **User-facing app name:** **Dry Spell**
- **Internal project / code style:** **DrySpell**
- Use **Dry Spell** for the app display name, user-visible strings, and end-user documentation.
- Use **DrySpell** for Xcode project names, target names, Swift symbols where appropriate, bundle identifiers, App Group identifiers, and internal filenames.

You are implementing **Dry Spell v1**, a production-quality **iOS/iPadOS SwiftUI app** with a **WidgetKit widget**.

## Documents to use

You have been provided two documents:

1. **Agent implementation plan**
2. **Product spec**

Use them with this priority:

- The **agent implementation plan** is the **primary source of truth** for implementation order, architecture, constraints, file structure, engineering rules, and acceptance criteria.
- The **product spec** is **supporting context** for product intent, user experience goals, recommendation behavior, and rationale.
- If the two documents conflict, **follow the agent implementation plan**.
- Do not invent requirements that are not supported by either document unless they are required for correctness or by Apple’s current platform APIs.

## Core objective

Build the app according to the provided plan using Apple’s current native frameworks and recommended patterns.

The app must:

- track one saved garden location
- show when it last meaningfully rained
- compute a watering recommendation
- suppress reminders when enough rain is forecast in the next 48 hours
- allow the user to mark **Watered**
- expose a simple non-configurable widget
- use only Apple-native frameworks for v1

## Platform and framework requirements

Use the Apple-native stack defined in the implementation plan. Do not substitute older or alternate patterns unless required for correctness.

Required stack:

- SwiftUI App
- iOS app target configured for iPhone and iPad
- WeatherKit
- SwiftData
- WidgetKit
- App Groups
- UserNotifications
- BackgroundTasks where applicable
- Swift Testing

Do not add:

- third-party dependencies unless absolutely necessary
- a backend
- CloudKit or iCloud sync in v1
- configurable widgets in v1
- multi-location support in v1
- live location permission in v1

## Naming rule

- Use **Dry Spell** for the app display name, user-visible strings, and end-user-facing documentation.
- Use **DrySpell** for Xcode project names, target names, bundle identifiers, App Group identifiers, and internal code or file naming where appropriate.

## Working rules

Follow these rules while implementing:

- Treat the **agent implementation plan** as the operational build brief.
- Keep business logic out of SwiftUI views.
- Keep the recommendation engine pure and deterministic.
- Keep the widget passive: it should render a precomputed shared snapshot, not recompute the full app logic.
- Keep reminders conservative: never create a new watering reminder from stale or unavailable weather data.
- Respect the exact recommendation priority, freshness rules, reminder rules, and state behavior described in the plan.
- Preserve the clean native Apple-first design constraints in the plan.
- Use system controls, system colors, system typography, and standard SwiftUI layout patterns unless the plan explicitly says otherwise.

## Build process expectations

Implement in the phase order given in the agent implementation plan.

At the end of each phase:

- ensure the project still builds
- keep changes scoped to that phase
- avoid mixing unrelated refactors
- verify the implemented phase matches the plan before continuing

Do not jump ahead to polish work before core logic is correct.

## Decision rule for ambiguity

When something is ambiguous:

- first consult the **agent implementation plan**
- then consult the **product spec** for intent
- prefer the simplest implementation that satisfies both
- avoid adding speculative features

When a detail is missing but necessary for completion:

- make the smallest reasonable Apple-native choice
- keep the implementation easy to revise later
- document the assumption briefly in code comments or a short note only if necessary

## Output expectations

Produce:

- working code
- small, reviewable commits grouped by phase
- minimal comments, only where the logic is non-obvious
- tests for the core logic described in the plan
- a short README with setup and run notes
- a KNOWN_ISSUES file only if something cannot be completed cleanly

## Quality bar

The implementation is not complete until it satisfies the plan’s definition of done, including:

- correct WeatherKit integration
- correct recommendation logic
- correct stale and unavailable handling
- correct reminder scheduling behavior
- correct widget behavior
- required WeatherKit attribution
- passing core tests

## First task

Start with the first phase only.

Create the Xcode SwiftUI app skeleton for Dry Spell v1, configured for iPhone and iPad, add the widget target, set the iOS deployment target to 26.0 and support iPhone and iPad, add the required capabilities, set up SwiftData, create the folder structure and empty model and service files, and stop.
