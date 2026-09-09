# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and semantic versioning once releases begin.

## [Unreleased]

### Added

- Native macOS menu-bar application targeting macOS 15.0 and newer.
- Claude Code and Codex local transcript aggregation.
- Live Claude and Codex subscription-limit collectors.
- Provider switching, daily chart, model breakdowns, refresh, settings, and launch actions.
- XCTest coverage, XcodeGen project definition, and human/agent maintenance documentation.
- One-command terminal build and launch workflow through `make run`.
- Omarchy-style horizontal activity and model meters with explicit history-window labels.
- Global `Control-Shift-Command-R` shortcut for toggling the TokenBar panel.
- In-panel number shortcuts for direct Claude Code and Codex selection.
- Configurable icon-only, provider, session, and weekly menu-bar display styles.

### Changed

- Codex transcript totals now use event timestamps for an accurate rolling 30-day window; Claude totals continue to cover all retained local history.
- Local transcript statistics are explicitly distinguished from provider-reported limit cycles.
- Agent launch actions now live in Settings, while the usage panel uses a quieter footer and header refresh control.
- Detailed local-history totals and quota-cycle clarification now live in an on-demand information popover.
- The usage panel now expands to its content instead of placing metrics in an internal scroll view.

### Fixed

- Show Claude model-scoped weekly limits returned through the current OAuth usage payload, including fallback from a null legacy bucket.
- Read Claude Code authentication from macOS Keychain instead of assuming the Linux credential-file location.
- Explain failed and expired Claude authentication using the authoritative `claude auth status` check.
- Sequence Codex app-server initialization before account requests and enforce bounded RPC read timeouts.
- Wait for the previous development process to exit before `make run` relaunches TokenBar.
- Avoid blocking for a full buffer when Codex keeps its app-server output stream open.
