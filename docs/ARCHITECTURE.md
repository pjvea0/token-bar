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

The status item uses an `NSPopover` whose content is the existing SwiftUI `UsagePanel`. AppKit owns this thin shell because SwiftUI's public `MenuBarExtra` API can control insertion but cannot programmatically present its window. The Carbon hot-key API provides system-wide activation without keyboard monitoring or Accessibility permission. The selected physical key code, Carbon modifier mask, and display label are persisted as one `GlobalShortcut` value; changing it tears down the previous registration before installing the replacement.

An AppKit local event monitor handles unmodified `1` and `2` only while the popover is visible. It never observes events delivered to other applications. Menu-bar display style is a persisted presentation preference in `UsageStore`; fresh installations default to icon-only, and labels are derived from each refreshed normalized limit rather than cached separately.

Appearance is also a persisted `UsageStore` preference. The application delegate is the single appearance authority: it applies the selected `NSAppearance` to the application, hosted content, and realized popover window. It reapplies that value immediately before and after presentation because `NSPopover` creates or reuses its window lazily. A nil appearance preserves normal macOS System behavior. Views inherit this effective appearance rather than forcing an independent SwiftUI color scheme, preventing mismatched text and surfaces.

Limit notifications are evaluated by the pure `LimitAlertEvaluator` after each refresh. A fired key combines provider, limit label, threshold, and the reset time rounded to ten minutes, so each threshold alerts once per quota cycle; keys whose reset has passed are pruned, and limits without a reset time re-arm when usage falls below the threshold. Rules and fired keys persist in `UserDefaults`. `UsageNotifier` wraps `UNUserNotificationCenter` and requests permission only when a rule is first enabled. The Makefile ad-hoc signs builds because macOS refuses notifications from bundles without a valid signature.

## Collection semantics

Transcript files are newline-delimited JSON and treated as an append-only, externally controlled format. Scans skip malformed and irrelevant lines. Claude messages deduplicate by message ID. Codex token snapshots use `last_token_usage`, not cumulative session usage; cached input is subtracted from input before categories are summed.

Calendar-day aggregation uses the user's current calendar and timezone. The seven-day series always contains seven buckets, including zero-use days. Claude model and summary totals cover every retained local transcript event. Codex totals use each event's timestamp to enforce a rolling 30-day window; file modification dates do not determine inclusion. Future-dated events are excluded. These local history windows are independent of provider-reported quota cycles.

Claude limit collection accepts both the legacy flat session/weekly buckets and current model-scoped entries in the OAuth usage payload. A null model-specific flat bucket does not mask the general weekly fallback. Percentage normalization is chosen across the whole payload so every returned limit uses one scale.

## Usage history

`HistoryStore`, owned by the `UsageService` actor, records two credential-free datasets under Application Support (ADR 0005). `TranscriptScanner.scanWithHistory` returns per-day, per-model totals for every retained event, ignoring the Codex 30-day summary window, and each refresh merges them into `daily.json` by field-wise maximum. Because a day's transcript totals only grow until the CLI prunes files, the maximum preserves archived days without double-counting rescans. Limit observations are appended to `limits.jsonl` only when utilization moves by half a percentage point, the reset cycle changes, or an hour passes. Day keys use the current calendar and timezone; queries return one entry per day in the range, including zero-use days. Malformed log lines are skipped.

## Concurrency

`UsageStore` is isolated to the main actor. `UsageService` is an actor so filesystem scans and provider requests cannot overlap internally. Provider result types cross that boundary as `Sendable` values. A refresh guard prevents duplicate user/timer requests.

## Security boundary

The app is deliberately unsandboxed to read CLI-owned files. Credential access is narrow: Claude's access token is read from the `Claude Code-credentials` macOS Keychain item (or the CLI file fallback), decoded in the collector, used in one HTTPS authorization header, and discarded. When both sources exist the credential with the later expiry wins. Expired or rejected tokens are renewed by running the CLI's non-inference `auth status` command, never by TokenBar refreshing OAuth itself (ADR 0004). Codex authentication remains inside the Codex child process. Errors exposed to UI must never include request headers or raw responses.

## Extension points

Add a provider by extending `ProviderID`, writing a scanner/limits adapter, composing it in `UsageService`, and adding sanitized fixtures. Cross-device sync should serialize normalized snapshots only—never credentials or source transcripts—and must distinguish device-local statistics from account-global limits.
