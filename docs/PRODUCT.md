# Product contract

TokenBar follows Omarchy's agents-panel information model while using familiar macOS behavior.

| Capability | TokenBar behavior |
| --- | --- |
| Provider hero and plan | Provider name, symbol, plan, and actionable auth/error state |
| Subscription switch | Native segmented control when multiple providers are enabled |
| Keyboard provider switch | While the panel is open, `1` selects Claude Code and `2` selects Codex |
| Limits | Percentage used, progress meter, and relative reset time |
| Token history | Seven local calendar days as relative horizontal meters; hover reveals detail |
| Model usage | Descending relative meters; Claude covers all retained local history and Codex covers a timestamp-accurate rolling 30 days |
| Panel sizing | Expands to fit its usage content without an internal scrolling region |
| Refresh | Fifteen-minute background cadence plus manual action and `r` shortcut |
| Global shortcut | A persistent, user-recordable shortcut toggles the panel globally without Accessibility permission; `Control-Shift-Command-R` is the default |
| Menu-bar readout | Persistent choice of icon only (default), provider abbreviation, session usage, or weekly usage; unavailable limits fall back to the provider abbreviation |
| Usage history | Separate window from the panel's clock button (or `h`); provider and range (7D/30D/90D/1Y/custom) selection with back/forward stepping; limit % line chart with alert threshold rules; stacked tokens-by-day chart with per-day model breakdown; Settings can clear history |
| Limit notifications | Per provider × window (session, weekly) rules with up to three thresholds each; off by default; each threshold alerts once per quota window; checked on refresh |
| Appearance | Follows the macOS color scheme by default, with persistent Light and Dark overrides |
| Launch | Settings provides explicit Terminal launch actions for each CLI, keeping the usage panel focused on monitoring |
| Empty state | Icon remains visible and presents onboarding (intentional macOS adaptation) |
| Partial failure | Working local data remains visible when live limits fail |

## Parity boundaries

The initial product targets Claude Code and OpenAI Codex, as requested. Omarchy's Fireworks prepaid-balance provider is not in scope. Omarchy can merge normalized snapshots from synced Linux machines; TokenBar's corresponding cross-device snapshot feature is planned but not implemented. Native macOS settings replace edits to Omarchy's shell JSON.

Provider-reported limits and local transcript statistics are deliberately separate. A session or weekly percentage describes the provider's current quota window; token history is not presented as a conversion of that percentage. Every history section labels its own time scope.

## Compatibility

The deployment target is macOS 15.0, so 15.7.4 is supported. CI should test the oldest supported runtime and the current macOS runtime. New SDK adoption must not silently raise `MACOSX_DEPLOYMENT_TARGET`.
