# TokenBar

TokenBar is a native macOS menu-bar dashboard for Claude Code and OpenAI Codex usage. It adapts Omarchy's agents-panel feature set to macOS conventions: a persistent menu-bar item opens a compact SwiftUI popover with subscription limits, reset times, a seven-day token chart, model totals, detailed token splits, refresh, settings, and agent launch actions.

The minimum deployment target is **macOS 15.0**, covering macOS 15.7.4 and future macOS versions through normal backward-compatible builds.

## Current capabilities

- Claude Code and Codex provider switching
- Local JSONL transcript discovery and read-only aggregation
- Input, output, cache-read, and cache-write token breakdowns
- Deduplication by message ID and session/day totals
- Seven-day token chart and all-model ranking
- Claude session/weekly limits via the authenticated Claude Code account
- Codex plan/session/weekly limits via the public Codex app-server protocol
- Automatic refresh every 15 minutes and manual refresh
- Clear partial-failure states: local stats survive a limits failure
- Native Settings window and one-click agent launch in Terminal
- Menu-bar-only app (`LSUIElement`) with no Dock icon

TokenBar intentionally keeps its icon visible before first usage so macOS users retain an onboarding and settings entry point. Omarchy hides its widget until usage exists; this is the one deliberate platform-paradigm difference.

## Build and run

Requirements: macOS 15+, Xcode 16+ (Xcode 26 is supported), and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen # one-time dependency
make run
```

`make run` generates the Xcode project, builds the app into `.build/DerivedData`, stops an older development instance, and launches the newly built app. Look for the sparkle icon and usage label in the menu bar; TokenBar does not appear in the Dock.

Useful terminal commands:

```sh
make          # show available commands
make run      # rebuild and relaunch
make stop     # quit the development instance
make test
make clean
```

Opening Xcode is optional. Run `make xcode` only when you want to use its editor or debugger.

The generated `TokenBar.xcodeproj` is intentionally ignored. `project.yml` is the reviewable source of truth, which prevents opaque project-file merge conflicts.

## Data and privacy

TokenBar is local-first and does not operate a server. It reads `~/.claude/projects/**/*.jsonl` and `~/.codex/sessions/**/*.jsonl`. For live limits it:

- reads the Claude Code OAuth token from macOS Keychain (with `~/.claude/.credentials.json` as a compatibility fallback) and sends it only to Anthropic's own usage endpoint;
- starts `codex app-server` locally and calls its account/rate-limit RPC.

Tokens are held only in memory and are never logged, copied, synchronized, or written by TokenBar. The app is not sandboxed because a sandboxed app cannot discover these CLI-owned files. See [Security](docs/SECURITY.md).

## Project navigation

- [Architecture](docs/ARCHITECTURE.md) — boundaries, data flow, and extension points
- [Product contract](docs/PRODUCT.md) — feature parity and macOS adaptations
- [Contributing](CONTRIBUTING.md) — development and Git workflow
- [Agent guide](AGENTS.md) — mandatory operating contract for AI contributors
- [Roadmap](docs/ROADMAP.md) — prioritized work that remains
- [Decisions](docs/decisions/0001-native-swiftui-and-xcodegen.md) — durable architecture rationale

## Status

This is a functional foundation, not yet a signed release. Transcript and private subscription endpoint formats can change independently; collectors are isolated and fixture-tested so those changes remain small. See the roadmap before claiming production readiness.

## Attribution and naming

The interaction and information design is inspired by Omarchy's agents panel. This implementation is original Swift code and does not bundle Omarchy source or assets. TokenBar is an independent project and is not affiliated with Omarchy, Anthropic, or OpenAI.

No open-source license has been selected. Until the repository owner adds one, all rights are reserved.
