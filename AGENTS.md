# AI Contributor Contract

This file is the primary operating manual for every coding agent. Read it before changing the repository. Human-facing context lives in `README.md`; durable technical context lives under `docs/`.

## Mission and invariants

Build a quiet, reliable macOS 15+ menu-bar app that reports Claude Code and Codex usage without leaking credentials or corrupting CLI state.

Never violate these invariants:

1. Deployment target remains macOS 15.0 unless a documented decision explicitly changes it.
2. Provider files are read-only. Never modify anything under `.claude`, `.codex`, or another tool's directory.
3. Never print, persist, fixture, snapshot, or synchronize access tokens.
4. A provider limits failure must not discard usable local statistics.
5. Parsers must tolerate malformed lines and unknown fields.
6. `project.yml`, not the generated Xcode project, is the project definition.
7. The main branch must build and tests must pass at every committed handoff.

## Start-of-task protocol

1. Read `README.md`, this file, and the directly relevant document in `docs/`.
2. Inspect `git status`, recent history, and overlapping uncommitted work before editing.
3. State the intended outcome and identify the smallest owning layer.
4. For provider-format work, obtain sanitized real shapes or add minimal synthetic fixtures first.

## Architecture boundaries

- `Sources/Domain`: value types only; no disk, network, process, AppKit, or SwiftUI behavior.
- `Sources/Infrastructure`: transcript parsing, CLI/RPC, networking, caching, and future sync.
- `Sources/App`: main-actor state and orchestration.
- `Sources/UI`: rendering and user actions; no direct credential or transcript access.
- `Tests`: behavior-focused XCTest coverage with synthetic, secret-free input.

Keep provider peculiarities in collectors. UI must consume normalized `ProviderUsage`, never raw JSON.

## Verification protocol

Run `make test` for every behavioral change. Also verify:

- malformed JSONL is skipped without failing the scan;
- repeated message IDs are counted once;
- cached input is not double-counted for Codex;
- one unavailable provider does not hide another;
- no sensitive values appear in errors or logs.

If a command cannot run in the current environment, record the exact command and blocker. Never call unverified work complete.

## Git protocol

Agents own routine Git operations. Use short-lived branches for parallel work and one conceptual change per commit. Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `build:`, `chore:`).

Before committing:

1. Review `git diff --check` and the complete diff.
2. Run `make test`.
3. Update docs and `CHANGELOG.md` when behavior changes.
4. Confirm no secret, user data, generated build output, or personal Xcode state is staged.

Before merging, rebase or merge the current target branch, resolve semantically, rerun tests, and use a non-destructive merge. Never rewrite shared history, force-push, or discard user changes without explicit authorization. Delete branches only after their commits are reachable from the target.

## Multi-agent coordination

Assign each agent a bounded component and, when possible, a dedicated worktree/branch. The coordinating agent owns integration and is the only agent that merges. Before agents start, record ownership boundaries (for example collector, UI, tests, docs). Agents must not edit another agent's owned files without coordination.

Each handoff must state:

- outcome and key decisions;
- files changed;
- tests run and their results;
- commit hash;
- known risks or follow-up work.

Independent review should focus on correctness, security, concurrency, compatibility, and documentation drift—not formatting taste.

## Documentation discipline

Update documentation in the same commit as code. Add an ADR under `docs/decisions/` for decisions that constrain future design. Use status `Proposed`, `Accepted`, `Superseded`, or `Deprecated`; never rewrite accepted history except for spelling or links. Add a superseding ADR instead.

Comments should explain format quirks, security boundaries, or why behavior exists. Avoid narrating obvious Swift syntax.
