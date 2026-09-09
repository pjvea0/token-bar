# Architecture

## System shape

```text
CLI-owned data             Provider adapters                Normalized state          Native UI
~/.claude/projects  ─┐     TranscriptScanner ─┐
~/.codex/sessions   ─┴──▶  LimitCollectors   ─┴──▶ UsageService ─▶ UsageStore ─▶ Status item + popover
Anthropic endpoint  ─────▶ Claude adapter
codex app-server    ─────▶ Codex adapter
```

The central design rule is normalization before presentation. Every provider produces `ProviderUsage`; views do not know JSON paths, OAuth headers, or RPC methods.

## Layers

`Domain` contains `Sendable`, `Codable` value types. `Infrastructure` owns blocking and asynchronous I/O behind the `UsageService` actor. `App` owns main-actor observable state, refresh scheduling, the AppKit status item, and global shortcut registration. `UI` renders normalized state and emits intent.

The status item uses an `NSPopover` whose content is the existing SwiftUI `UsagePanel`. AppKit owns this thin shell because SwiftUI's public `MenuBarExtra` API can control insertion but cannot programmatically present its window. The Carbon hot-key API provides system-wide activation without keyboard monitoring or Accessibility permission.

An AppKit local event monitor handles unmodified `1` and `2` only while the popover is visible. It never observes events delivered to other applications. Menu-bar display style is a persisted presentation preference in `UsageStore`; labels are derived from each refreshed normalized limit rather than cached separately.

## Collection semantics

Transcript files are newline-delimited JSON and treated as an append-only, externally controlled format. Scans skip malformed and irrelevant lines. Claude messages deduplicate by message ID. Codex token snapshots use `last_token_usage`, not cumulative session usage; cached input is subtracted from input before categories are summed.

Calendar-day aggregation uses the user's current calendar and timezone. The seven-day series always contains seven buckets, including zero-use days. Claude model and summary totals cover every retained local transcript event. Codex totals use each event's timestamp to enforce a rolling 30-day window; file modification dates do not determine inclusion. Future-dated events are excluded. These local history windows are independent of provider-reported quota cycles.

## Concurrency

`UsageStore` is isolated to the main actor. `UsageService` is an actor so filesystem scans and provider requests cannot overlap internally. Provider result types cross that boundary as `Sendable` values. A refresh guard prevents duplicate user/timer requests.

## Security boundary

The app is deliberately unsandboxed to read CLI-owned files. Credential access is narrow: Claude's access token is read from the `Claude Code-credentials` macOS Keychain item (or the CLI file fallback), decoded in the collector, used in one HTTPS authorization header, and discarded. Codex authentication remains inside the Codex child process. Errors exposed to UI must never include request headers or raw responses.

## Extension points

Add a provider by extending `ProviderID`, writing a scanner/limits adapter, composing it in `UsageService`, and adding sanitized fixtures. Cross-device sync should serialize normalized snapshots only—never credentials or source transcripts—and must distinguish device-local statistics from account-global limits.
