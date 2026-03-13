# Contributing to AeroOverlay

Thanks for your interest in contributing! Here's how to get started.

## Setup

1. Clone the repo
2. Run `swift build` to compile
3. Grant Accessibility permissions to `.build/debug/AeroOverlay` in System Settings

## Development

```bash
swift build            # Debug build
swift build -c release # Release build
```

After building, restart the app to test changes:

```bash
pkill -f AeroOverlay; .build/debug/AeroOverlay &
```

## Pull Requests

- Keep PRs focused on a single change
- Test on your machine before submitting
- Describe what changed and why

## Reporting Issues

- Include your macOS version and AeroSpace version
- Screenshots help for UI issues
- Steps to reproduce are appreciated

## Code Style

- Follow existing conventions in the codebase
- No third-party dependencies — keep it lightweight
