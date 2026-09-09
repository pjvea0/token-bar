# ADR 0001: Native SwiftUI and XcodeGen

- Status: Accepted
- Date: 2026-09-08

## Context

TokenBar must feel native on macOS, support macOS 15.7.4 and future systems, remain dependency-light, and be straightforward for AI contributors to modify without fragile project-file conflicts.

## Decision

Use Swift 6, SwiftUI `MenuBarExtra`, an actor-isolated collection layer, and AppKit only for macOS-specific integration. Define the Xcode project in `project.yml` and regenerate it with XcodeGen. Keep the deployment target at macOS 15.0.

## Consequences

The application is small, native, and has no runtime package dependencies. Reviewers can inspect project configuration as YAML. Contributors need XcodeGen locally. Swift strict concurrency is a required design constraint, and UI behavior unavailable through SwiftUI may need narrow AppKit bridges later.
