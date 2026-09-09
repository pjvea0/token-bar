# ADR 0002: AppKit status item for global shortcut activation

- Status: Accepted
- Date: 2026-09-09

## Context

TokenBar needs a system-wide shortcut that can open its panel while another application is active. SwiftUI's public `MenuBarExtra` API exposes whether an item is inserted into the menu bar, but it does not expose a binding or action for presenting the window-style extra.

Global keyboard event monitors would retain the SwiftUI scene but require privacy-sensitive keyboard monitoring permissions. Automating a click through accessibility APIs would likewise add an unnecessary permission and a brittle dependency on menu-bar layout.

## Decision

Own the menu-bar item and transient popover in a small AppKit application delegate. Continue to render the entire panel and Settings interface in SwiftUI through `NSHostingController` and the existing Settings scene.

Register `Control-Shift-Command-R` with macOS's Carbon hot-key API. The command toggles the same popover used by a direct status-item click. Report registration failure in Settings because macOS rejects a shortcut already reserved by another process.

## Consequences

- Global activation requires no Accessibility or Input Monitoring permission.
- Menu-bar presentation lifecycle is explicit and testable independently from provider collection.
- The app retains its existing SwiftUI views and state model.
- The fixed shortcut cannot coexist with another application claiming the same combination; Settings surfaces that conflict.
- Future configurable shortcuts should replace the fixed constants behind `GlobalHotKey`, not add a second event-monitoring path.
