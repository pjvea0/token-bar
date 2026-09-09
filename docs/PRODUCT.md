# Product contract

TokenBar follows Omarchy's agents-panel information model while using familiar macOS behavior.

| Capability | TokenBar behavior |
| --- | --- |
| Provider hero and plan | Provider name, symbol, plan, and actionable auth/error state |
| Subscription switch | Native segmented control when multiple providers are enabled |
| Limits | Percentage used, progress meter, and relative reset time |
| Token history | Seven local calendar days with today at right; hover reveals detail |
| Model usage | Descending totals; hover reveals input/output/cache split |
| Refresh | Fifteen-minute background cadence plus manual action and `r` shortcut |
| Launch | Opens the selected CLI in Terminal |
| Empty state | Icon remains visible and presents onboarding (intentional macOS adaptation) |
| Partial failure | Working local data remains visible when live limits fail |

## Parity boundaries

The initial product targets Claude Code and OpenAI Codex, as requested. Omarchy's Fireworks prepaid-balance provider is not in scope. Omarchy can merge normalized snapshots from synced Linux machines; TokenBar's corresponding cross-device snapshot feature is planned but not implemented. Native macOS settings replace edits to Omarchy's shell JSON.

## Compatibility

The deployment target is macOS 15.0, so 15.7.4 is supported. CI should test the oldest supported runtime and the current macOS runtime. New SDK adoption must not silently raise `MACOSX_DEPLOYMENT_TARGET`.
