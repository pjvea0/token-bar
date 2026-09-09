# Contributing

## Local setup

Install Xcode and XcodeGen, then run `make bootstrap` and `make test`. Open `ai-menu-bar.xcworkspace` for development. Do not commit the generated `.xcodeproj` or user workspace state.

## Change workflow

Create a focused branch, make one coherent change, add tests, update relevant documentation, and run `make test`. Use Conventional Commit messages. Pull requests should explain the user-visible outcome, security/privacy impact, evidence of verification, and any provider-format assumptions.

Provider payloads must be represented by the smallest synthetic fixture that proves behavior. Never commit a real transcript, account response, username, path, email, organization ID, or token.

## Definition of done

A change is done when it builds for the macOS 15.0 deployment target, tests pass, error behavior is intentional, accessibility labels remain meaningful, docs match behavior, the changelog is updated when user-visible, and the diff contains no generated or sensitive files.
