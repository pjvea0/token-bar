# ADR 0005: Local normalized usage history

- Status: Accepted
- Date: 2026-10-03

## Context

People want to look back at past usage. Provider limits are only available as current values, and Claude Code deletes old transcripts (30 days by default), so neither source alone can answer "what did my usage look like in July?".

## Decision

TokenBar persists two normalized datasets in `~/Library/Application Support/TokenBar/History/`:

- `daily.json`: per provider, per calendar day, per model token breakdowns and prompt counts, plus daily session counts. Each refresh merges fresh scans by field-wise maximum.
- `limits.jsonl`: append-only limit samples (time, provider, label, window, utilization, reset time), deduplicated to meaningful changes or hourly.

Plain JSON files are used instead of a database: the data is small, has no relational queries, and needs no dependency. Files are written atomically (daily) or appended (samples), and malformed lines are skipped.

## Consequences

- History survives transcript pruning but can only include limit samples from the time TokenBar was running.
- Maximum-merge cannot lower a day's total, so a corrected or shrunken transcript is not reflected; this is acceptable for activity statistics.
- The persisted files are a new local data store and are documented in the security policy; they never contain credentials or transcript content.
- Cross-device sync (roadmap 0.2) can reuse these normalized structures.
