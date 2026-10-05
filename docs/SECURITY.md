# Security and privacy

## Data handled

TokenBar reads local Claude Code, Codex, Gemini CLI, and Antigravity transcript metadata and token counts. Prompts and responses are not rendered or persisted. It temporarily reads Claude's CLI OAuth token from macOS Keychain (or the CLI file fallback) for an HTTPS request to Anthropic. macOS may ask the user to authorize this access. Codex credentials remain managed by the Codex CLI. When Claude's token has expired or is rejected, TokenBar runs `claude auth status` with output discarded so the CLI can renew its own login; TokenBar never performs the OAuth refresh itself and never writes credentials.

For Gemini, TokenBar reads only Gemini CLI chat files and Antigravity conversation databases. It never reads `~/.gemini/oauth_creds.json`, `~/.gemini/jetski-standalone-oauth-token`, or any other Google credential, and it makes no network request for Gemini. Antigravity databases are copied, with their WAL, into a per-scan temporary directory that is deleted right afterward. SQLite opens only the copy, because even a read-only connection can create or modify the `-shm` file beside the original database. TokenBar reads only token counts, model IDs, and timestamps from these copies.

## Reporting a vulnerability

Do not open a public issue containing credentials, transcripts, or account responses. Until a private security contact is configured, create a minimal report that contains no sensitive payload and ask the repository owner for a private channel.

## Contributor requirements

- Never log raw provider payloads or authorization headers.
- Use synthetic fixtures only.
- Redact local usernames and paths from user-facing errors.
- Keep networking pinned to documented provider hosts.
- Treat transcript and endpoint JSON as untrusted input.
- Review dependency additions for necessity; the current application has no third-party runtime dependencies.

## Persisted history

TokenBar writes normalized history to `~/Library/Application Support/TokenBar/History/`: per-day, per-model token and prompt counts, per-day session counts, and limit utilization samples with labels and reset times. It never writes prompts, responses, file paths, session identifiers, account identifiers, or credentials there. Users can delete it from Settings.

## Known constraints

App Sandbox is disabled because CLI data resides outside TokenBar's container. Distribution therefore requires Developer ID signing/notarization rather than a default sandboxed Mac App Store path unless a future explicit file-access design changes this boundary.
