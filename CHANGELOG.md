# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and semantic versioning once releases begin.

## [Unreleased]

### Added

- Native macOS menu-bar application targeting macOS 15.0 and newer.
- Claude Code and Codex local transcript aggregation.
- Live Claude and Codex subscription-limit collectors.
- Provider switching, daily chart, model breakdowns, refresh, settings, and launch actions.
- XCTest coverage, XcodeGen project definition, and human/agent maintenance documentation.
- One-command terminal build and launch workflow through `make run`.

### Fixed

- Read Claude Code authentication from macOS Keychain instead of assuming the Linux credential-file location.
- Explain failed and expired Claude authentication using the authoritative `claude auth status` check.
