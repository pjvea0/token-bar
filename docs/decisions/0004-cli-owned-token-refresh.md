# ADR 0004: CLI-owned Claude token refresh

- Status: Accepted
- Date: 2026-10-03

## Context

Claude Code stores a short-lived OAuth access token and a rotating refresh token in the `Claude Code-credentials` Keychain item. Only a running CLI renews them. People who rarely start the CLI (for example, because they use Claude Code through the desktop app) saw TokenBar report an expired sign-in and repeatedly ran `claude auth login`.

TokenBar could refresh the token itself, but refresh tokens rotate: a refresh by TokenBar would invalidate the CLI's stored token unless TokenBar also wrote the Keychain item, which violates the read-only provider-data invariant.

## Decision

When the freshest available credential is expired, or the usage endpoint answers 401, TokenBar runs `claude auth status` once (stdin closed, output discarded, 15-second limit), then rereads the credential. The CLI performs and persists any refresh. If no usable credential results, TokenBar shows an actionable status with a button that opens Claude Code in Terminal.

Credential sources are both read and the one with the latest expiry wins, so a leftover credential file cannot mask the Keychain.

## Consequences

- TokenBar never holds or rotates refresh tokens and never writes provider state.
- Recovery depends on the CLI's `auth status` command refreshing the token; if a CLI version stops doing so, the fallback message still avoids a full re-login.
- A Claude Code CLI installation remains required for live Claude limits.
