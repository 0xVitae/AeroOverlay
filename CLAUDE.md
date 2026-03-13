# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build                # Debug build
swift build -c release     # Release build

# Run (requires Accessibility permission for the binary)
.build/debug/AeroOverlay &

# Kill and restart for testing changes
pkill -f AeroOverlay; .build/debug/AeroOverlay &

# Install release binary
cp .build/release/AeroOverlay ~/.local/bin/
```

No tests exist — test manually by building, launching, and double-tapping Option.

## Architecture

AeroOverlay is a single-target Swift Package (macOS 13+, Swift 5.9) with zero third-party dependencies. It's a floating HUD panel that shows AeroSpace tiling window manager workspaces.

**Entry point:** `main.swift` — creates an `AppDelegate` that manages the overlay lifecycle. The app runs as `.accessory` (no Dock icon). Toggle via double-tap Option key or SIGUSR1. PID file written to `~/.local/state/aerooverlay.pid`.

**Key components:**

- **`OverlayPanel`** — Borderless `NSPanel` (floating, joins all spaces). Handles fade-in/out animation and keyboard events (Escape to dismiss, arrows/Enter forwarded to VC).
- **`OverlayViewController`** — Builds the full UI on each `reload()`: header (title + system stats), workspace grid, footer (focused workspace + time + Claude usage bar). Grid layout mirrors keyboard positions (rows: 1-9, q-y, a-f). Only active workspaces + one next-inactive are shown.
- **`WorkspaceCell`** — Individual workspace tile. Shows workspace name, window list with app icons, notification badges, gradient borders for focused/selected/notified states. Contains terminal CWD resolution logic (`buildTerminalCwdMap`) that matches window IDs to shell processes via PID tree walking.
- **`AeroSpaceClient`** — Shells out to `/opt/homebrew/bin/aerospace` CLI with `--json` flag. Parallelizes workspace/window/monitor queries using DispatchGroup. Data types: `WorkspaceInfo`, `WindowInfo`, `MonitorInfo`.
- **`SystemStats`** — Reads CPU (Mach host_statistics), RAM (vm_statistics64), battery (IOKit) directly via system APIs.
- **`ClaudeUsage`** — Fetches Claude Code usage from API using OAuth token from macOS Keychain (`security find-generic-password`). Caches to `~/.local/state/aerooverlay-claude-usage.json`.
- **`Notifications`** — File-based IPC via `~/.local/state/aerooverlay-notifications`. External scripts write `workspace:windowID` lines; overlay reads and clears on workspace selection.
- **`WindowCapture`** — CGWindowList screenshot capture and app icon lookup (icon lookup is actively used; screenshot capture exists but isn't currently called).

## Conventions

- After every code change, rebuild and restart the app: `swift build && pkill -f AeroOverlay; .build/debug/AeroOverlay &`
- No third-party dependencies — keep it lightweight
- All UI is built programmatically with AppKit (no storyboards/xibs)
- Debug logging in WorkspaceCell writes to `~/.aerooverlay-debug.log`
