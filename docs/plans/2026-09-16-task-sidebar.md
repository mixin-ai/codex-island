# Codex Task Sidebar Implementation Plan

**Goal:** Keep usage on the left and show up to three local Codex tasks, including their execution state, on the right of the notch.

**Architecture:** A read-only SQLite query supplies task identities, names, and rollout paths. A background scanner reads lifecycle events from those rollouts and publishes a maximum of three tasks, prioritizing running tasks. The compact notch and expanded Usage page share the same task list. A separate glow preference disables every decorative outer glow.

**Tech Stack:** Swift, SwiftUI, Combine, SQLite3, Foundation.

## Design decisions

- Prefer an always-visible three-row sidebar over a rotating single task or an expanded-only list, so concurrent tasks can be checked at a glance.
- Use explicit `task_started`, `task_complete`, and `turn_aborted` events. A missing or stale reading is unknown, never a successful completion.
- Show running tasks first, then recently ended tasks. Exclude archived tasks and subagents. Use the short thread name when available.
- Read only metadata and lifecycle records locally; no prompts, responses, credentials, or task data are uploaded.
- Keep the physical camera area clear and keep the compact panel's height to 52 points. Truncate titles visually and expose the full name via hover and accessibility.
- Keep the existing app identity and preferences. Back up the installed application before replacement. Disable automatic update checks for this local build so an upstream update does not remove the requested customization.

## Implementation

1. Add `Sources/Tasks/CodexTaskReader.swift` with lifecycle parsing, read-only task discovery, unchanged-file caching, and running-first selection.
2. Add `Sources/Tasks/CodexTaskStore.swift` to refresh local metadata every three seconds away from the main thread.
3. Add `Sources/Views/CodexTaskList.swift`; integrate it into `IslandRootView.swift`, `UsageView.swift`, and `PanelHeader.swift`. Extend `IslandModel.swift` to reserve room beside the notch.
4. Add task-sidebar and outer-glow preferences to `SettingsView.swift` and a shared appearance store. Stop the sweep, colored shadow, and frosted halo when glow is disabled.
5. Add a fixture-based test executable covering lifecycle changes, interrupted/restarted turns, partial records, stale/missing files, sorting, maximum count, and the read-only database query. Run it plus existing relevant layout and usage tests.
6. Build the application, verify its signature and arm64 architecture, save a reversible copy of the original, install the local build, and inspect the actual task list and glow using the macOS UI.

## Acceptance

- At most three task names appear on the right; the current active task is marked 执行中.
- A completed turn becomes 已结束 after the next local refresh; interrupted work is 已中断.
- Left-side usage and existing display preferences continue to work.
- With 外圈流光 off there is no outer sweep or colored halo, including on hover and refresh.
- A missing database or incomplete rollout produces a neutral state instead of invented completion.
