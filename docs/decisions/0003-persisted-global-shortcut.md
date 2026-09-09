# ADR 0003: Persisted, recordable global shortcut

- Status: Accepted
- Date: 2026-09-09
- Extends: ADR 0002

## Context

ADR 0002 established AppKit status-item ownership and Carbon hot-key registration, initially with a fixed `Control-Shift-Command-R` combination. A fixed binding can conflict with another application or a person's established keyboard workflow.

## Decision

Represent the shortcut as one persisted value containing its physical key code, Carbon modifier mask, and human-readable key label. Provide a native recorder in Settings that accepts combinations containing at least one Command, Control, Option, or Shift modifier. Escape cancels recording, and a reset action restores `Control-Shift-Command-R`.

Changing the preference immediately unregisters the old hot key and attempts to register the new one. A registration conflict is shown in Settings; TokenBar does not silently install a different shortcut. The implementation continues to use Carbon registration and therefore does not request Accessibility or Input Monitoring permission.

## Consequences

- People can resolve conflicts and fit TokenBar into their keyboard workflow.
- Physical key codes remain stable for a chosen keyboard position; the stored display label describes what was recorded.
- An invalid or externally conflicting preference leaves mouse activation available and produces a visible Settings warning.
- Unmodified global keys cannot be recorded, preventing TokenBar from intercepting ordinary typing system-wide.
