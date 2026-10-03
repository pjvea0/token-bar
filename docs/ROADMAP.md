# Roadmap

## Release 0.1 — hardened local beta

- Add cooperative cancellation around a running Codex child process.
- Add cache envelopes so large histories are rescanned only when sources change.
- Add fixtures for Codex RPC error responses.
- Add accessibility and UI tests, application icon, signing, notarization, and release automation.

## Release 0.2 — Omarchy parity

- Export/import normalized history and, credential-free device snapshots from a user-selected sync folder.
- Merge active dates by union, machine-local tokens by sum, and account-level limits without summing.
- Support user-selected transcript roots in addition to `CLAUDE_CONFIG_DIR` and `CODEX_HOME`.
- Scan archived Codex sessions and compatible Pi/OpenCode sessions without double-counting.
- Launch-at-login using ServiceManagement.

## Later

- Optional additional provider adapters through the same normalized contract.
- Signed Sparkle or App Store-independent update channel, subject to distribution decision.
