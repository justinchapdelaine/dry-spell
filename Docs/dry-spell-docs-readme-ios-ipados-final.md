# Dry Spell — Docs README

This folder contains the source-of-truth planning and handoff documents for the **Dry Spell** app.

Current platform scope: **iOS/iPadOS only**.

## Files in this folder

- `dry-spell-agent-instruction-ios-ipados-final.md`
- `dry-spell-agent-implementation-plan-ios-ipados-final.md`
- `dry-spell-spec-v1-ios-ipados-final.md`
- `dry-spell-agent-handoff-prompt-ios-ipados-final.md`

## Document priority

When using these files with a coding agent, use them in this order:

1. **Coding agent instruction**  
   `dry-spell-agent-instruction-ios-ipados-final.md`
2. **Agent implementation plan**  
   `dry-spell-agent-implementation-plan-ios-ipados-final.md`
3. **Product spec**  
   `dry-spell-spec-v1-ios-ipados-final.md`

If there is any conflict between documents, follow the **higher-priority document**.

## What each file is for

### 1. Coding agent instruction
This file tells the coding agent **how to behave**.

It defines:
- how to use the documents
- implementation rules
- decision rules for ambiguity
- output expectations
- the first task to begin with

### 2. Agent implementation plan
This file tells the coding agent **what to build and in what order**.

It defines:
- architecture
- build phases
- engineering constraints
- required frameworks
- test requirements
- definition of done

### 3. Product spec
This file gives the coding agent **product intent and behavior context**.

It defines:
- user experience goals
- recommendation logic
- reminder behavior
- widget behavior
- rationale behind product decisions

### 4. Agent handoff prompt
This file is the **chat prompt wrapper** used when starting a coding-agent session.

It tells the agent:
- which files to read
- what priority order to use
- how to begin implementation

## Naming convention

Use these naming rules consistently:

- **Dry Spell** = user-facing app name
- **DrySpell** = internal project, code, module, bundle, and target naming style

Examples:
- App Store / app display name: `Dry Spell`
- Xcode project name: `DrySpell`
- Bundle ID style: `com.yourname.dryspell`
- Widget bundle ID style: `com.yourname.dryspell.widget`
- App Group style: `group.com.yourname.dryspell`

## Recommended repo layout

```text
Docs/
  dry-spell-agent-instruction-ios-ipados-final.md
  dry-spell-agent-implementation-plan-ios-ipados-final.md
  dry-spell-spec-v1-ios-ipados-final.md
  dry-spell-agent-handoff-prompt-ios-ipados-final.md
  dry-spell-docs-readme-ios-ipados-final.md
```

## Recommended way to use these docs

1. Put all files in the repo under `Docs/`
2. Commit them so the coding agent can read them from the repository
3. Open the coding agent in the repo
4. Paste the contents of `dry-spell-agent-handoff-prompt-ios-ipados-final.md` into the chat
5. Tell the agent to read the three core docs in the priority order listed above
6. Have the agent begin with **Phase 1 only**

## Suggested message to the coding agent

```text
Please read these files first:

- Docs/dry-spell-agent-instruction-ios-ipados-final.md
- Docs/dry-spell-agent-implementation-plan-ios-ipados-final.md
- Docs/dry-spell-spec-v1-ios-ipados-final.md

Use them in that priority order.

Then follow the handoff prompt in:
- Docs/dry-spell-agent-handoff-prompt-ios-ipados-final.md
```

## Notes

- The **coding agent instruction** is the behavioral guide.
- The **implementation plan** is the operational build brief.
- The **product spec** is supporting context.
- The **handoff prompt** is usually pasted into the coding-agent chat box.

This README is here so the document hierarchy is clear even outside the chat prompt.
