# TokenBar

TokenBar is a native macOS menu-bar dashboard for Claude Code and OpenAI Codex. It shows live subscription limits alongside local token activity in an Omarchy-inspired interface designed for macOS.

TokenBar runs on **macOS 15.0 and newer**, including macOS 15.7.4. It is a menu-bar-only app: there is no Dock icon and Xcode does not need to be opened.

> [!NOTE]
> TokenBar is currently an unsigned source release. Each user builds it locally with the terminal workflow below; there is not yet a notarized downloadable app.

## Quick start

### Requirements

| Requirement | Notes |
| --- | --- |
| macOS 15 or newer | macOS 15.7.4 is supported |
| Xcode 16 or newer | Install the full Xcode application, not only Command Line Tools |
| [Homebrew](https://brew.sh) | Used by the quick-start command to install XcodeGen |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Generates the local Xcode project from `project.yml` |
| Claude Code or Codex | At least one supported CLI should be installed and signed in |

Clone or download the repository, then run from a terminal:

```sh
cd ai-mac-menu
brew install xcodegen
make run
```

If your checkout uses a different directory name, `cd` into that directory instead.

`make run` performs the complete workflow: it generates `TokenBar.xcodeproj`, builds into `.build/DerivedData`, stops an older development instance, and launches the new build. Look for the sparkle icon in the menu bar.

Opening Xcode is optional. The first Claude refresh may display a macOS prompt for access to the `Claude Code-credentials` Keychain item; approve it so TokenBar can request live limits.

## Controls

| Action | Control |
| --- | --- |
| Open or close TokenBar globally | `Control-Shift-Command-R` |
| Select Claude Code while open | `1` |
| Select Codex while open | `2` |
| Refresh while open | `R` or the refresh button |
| Open Settings | Gear button |
| Show aggregate details | Information button |
| Quit | Power button |

The global shortcut uses macOS hot-key registration and does not require Accessibility or Input Monitoring permission. Settings reports if another application has already reserved it.

## Menu-bar display styles

Settings → Menu Bar provides four persistent styles:

| Style | Example | Behavior |
| --- | --- | --- |
| Icon only | sparkle icon | Uses the least menu-bar space |
| Provider | `Cl` or `Cx` | Default; shows the selected provider without a percentage |
| Session usage | `Cl 18%` | Shows the refreshed session limit |
| Weekly usage | `Cx 42%` | Shows the refreshed weekly limit |

If a selected live limit is unavailable, TokenBar falls back to the provider abbreviation rather than displaying stale or invented data.

## What the numbers mean

Provider limits and local transcript totals are separate datasets:

| Display | Source and time window |
| --- | --- |
| Session and weekly limits | Authoritative provider-reported allowance usage and reset times |
| Tokens by day | Local transcript tokens for the last seven calendar days |
| Claude tokens by model | All retained local Claude transcript history |
| Codex tokens by model | A timestamp-accurate rolling 30 days of local Codex history |

Local totals combine input, output, cache-read, and cache-write tokens. They are useful activity statistics, but they are not a conversion of the provider's quota percentage. Hover over a model row for the category breakdown, or open the information popover for exact totals, prompts, sessions, and active days.

## Authentication

TokenBar uses the existing CLI sign-ins; it does not provide a separate account flow.

For Claude Code, confirm the CLI is authenticated:

```sh
claude auth status
```

If necessary, run `claude auth login`. For Codex, run `codex login` if the app reports that live limits are unavailable. Starting either CLI from Settings opens it in Terminal.

## Terminal commands

```sh
make          # list available commands
make run      # generate, build, stop the old instance, and relaunch
make launch   # launch the most recently built app without rebuilding
make stop     # quit the development instance
make test     # generate the project and run the full test suite
make clean    # clean local Xcode build products
make xcode    # open the generated workspace, only if desired
```

The generated `TokenBar.xcodeproj` is intentionally ignored. `project.yml` is the reviewable source of truth, avoiding generated project-file conflicts.

## Troubleshooting

### The build cannot find Xcode

Verify the selected developer directory:

```sh
xcodebuild -version
xcode-select -p
```

If the path points only to Command Line Tools, select the installed Xcode application:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### The app launches but has no Dock icon

That is intentional. TokenBar uses `LSUIElement` and lives only in the menu bar. If the menu bar is crowded, macOS may hide status items; look for the sparkle icon after temporarily closing other menu-bar apps.

### Claude says it is waiting for authentication

Run `claude auth status`, then `claude auth login` if needed. Relaunch with `make run` after completing authentication, and approve any Keychain access prompt.

### Codex limits are unavailable

Run `codex login`, verify the Codex CLI itself works, and then refresh TokenBar. Local transcript statistics remain visible when the live limit request fails.

### A limit row is missing

Limit rows are not hidden based on utilization. TokenBar displays every recognized limit returned for the account, including Claude model-scoped limits. A missing row means the provider did not return that allowance or its response format changed; please report a sanitized description without posting account responses or credentials.

## Data and privacy

TokenBar is local-first and has no server. It reads token metadata from:

- `~/.claude/projects/**/*.jsonl`
- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/archived_sessions/**/*.jsonl`

For live limits, TokenBar reads Claude Code's OAuth credential from macOS Keychain, with the CLI credential file as a compatibility fallback, and sends it only to Anthropic's usage endpoint. Codex credentials stay inside the locally launched `codex app-server` process.

TokenBar does not render or persist prompt and response content. Credentials, raw provider responses, and transcript contents are never logged, copied, synchronized, or stored by TokenBar. App Sandbox is disabled solely because the app must read CLI-owned files outside its container. See the [security policy](docs/SECURITY.md) for the complete boundary.

## Development

Run `make test` before every commit. CI repeats the suite on macOS 15 from the generated project definition. Provider-format tests use small synthetic fixtures; real transcripts, credentials, usernames, emails, and account responses must never be committed.

Documentation for maintainers and coding agents:

- [Architecture](docs/ARCHITECTURE.md) — system boundaries and collection semantics
- [Product contract](docs/PRODUCT.md) — user-visible behavior and parity decisions
- [Contributing](CONTRIBUTING.md) — development and Git workflow
- [Agent guide](AGENTS.md) — mandatory operating contract for AI contributors
- [Security](docs/SECURITY.md) — credential and transcript safety requirements
- [Roadmap](docs/ROADMAP.md) — release hardening and future work
- [Architecture decisions](docs/decisions/) — durable technical decisions
- [Changelog](CHANGELOG.md) — unreleased changes

## Project status

TokenBar is a functional local beta, not yet a signed or notarized release. Transcript formats and provider limit interfaces can change independently; collectors are isolated and fixture-tested to keep compatibility updates focused. Signing, notarization, release automation, UI tests, and an application icon remain on the roadmap.

## License

No open-source license has been selected. Until the repository owner adds one, all rights are reserved. Others may inspect the shared repository, but broader permission to copy, modify, or redistribute it has not been granted.

## Attribution

The interaction and information design is inspired by Omarchy's agents panel. This implementation is original Swift code and does not bundle Omarchy source or assets. TokenBar is independent and is not affiliated with Omarchy, Anthropic, or OpenAI.
