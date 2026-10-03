# Security and privacy

## Data handled

TokenBar reads local Claude Code and Codex transcript metadata and token counts. Prompts and responses are not rendered or persisted. It temporarily reads Claude's CLI OAuth token from macOS Keychain (or the CLI file fallback) for an HTTPS request to Anthropic. macOS may ask the user to authorize this access. Codex credentials remain managed by the Codex CLI. When Claude's token has expired or is rejected, TokenBar runs `claude auth status` with output discarded so the CLI can renew its own login; TokenBar never performs the OAuth refresh itself and never writes credentials.

## Reporting a vulnerability

Do not open a public issue containing credentials, transcripts, or account responses. Until a private security contact is configured, create a minimal report that contains no sensitive payload and ask the repository owner for a private channel.

## Contributor requirements

- Never log raw provider payloads or authorization headers.
- Use synthetic fixtures only.
- Redact local usernames and paths from user-facing errors.
- Keep networking pinned to documented provider hosts.
- Treat transcript and endpoint JSON as untrusted input.
- Review dependency additions for necessity; the current application has no third-party runtime dependencies.

## Known constraints

App Sandbox is disabled because CLI data resides outside TokenBar's container. Distribution therefore requires Developer ID signing/notarization rather than a default sandboxed Mac App Store path unless a future explicit file-access design changes this boundary.
