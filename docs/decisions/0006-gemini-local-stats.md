# ADR 0006: Gemini as a local-only provider

- Status: Accepted
- Date: 2026-10-05

## Context

Users run Google's Gemini models through two agents that share `~/.gemini`: Gemini CLI and Antigravity. Gemini CLI records chats as JSON or JSONL with per-message token counts in an open-source format. Antigravity keeps each conversation in a SQLite database (`antigravity/conversations/<uuid>.db`, WAL mode) whose rows are undocumented protobuf blobs.

Neither tool offers a supported quota interface. Live quotas would require either an internal Code Assist endpoint called with Gemini CLI's OAuth token, or the private RPC of Antigravity's running language server. Either approach would mean reading Google credentials or depending on private process details, and both could break without notice.

## Decision

- Add a single `gemini` provider that merges both sources into one tab, history, and model list. Model IDs keep their sources distinguishable.
- Report local statistics only. Gemini has no limit collector, no alert rules, and no limit history chart. TokenBar never reads Google credential files.
- Read Antigravity databases from a private copy. The `.db` and `-wal` files are copied to a temporary directory, and SQLite opens only the copy. A read-only connection to the original can still create or write `-shm`, which would violate the read-only provider-data invariant.
- Decode Antigravity protobuf with a schemaless wire reader. The field map was taken from real databases using only integers and model IDs:
  - `gen_metadata.data`: field 1 → 4 is usage. Field 2 is uncached input. Field 3 is output, which always equals field 9 (thinking) plus field 10 (response). Field 5 is cached input. Field 1 → 19 is the model ID.
  - `steps.metadata`: field 1 → 1 is the creation time in seconds. Steps with `step_type` 15 match `gen_metadata` rows one-to-one, in order. When the counts differ, every generation takes the conversation's latest step time.
- Gemini CLI tokens are normalized as follows: `input − cached + tool` is input, `output + thoughts` is output, and `cached` is cache read.

## Consequences

- Gemini usage appears without any sign-in or Keychain prompt.
- An Antigravity update can renumber fields. Malformed rows are skipped. A silent remapping could misattribute counts, so the fixture tests encode the observed layout and must be updated alongside any remap.
- Each refresh copies every Antigravity conversation database. This is acceptable at current sizes; the roadmap's cache envelopes would avoid it.
