.PHONY: bootstrap build test clean open

DERIVED_DATA ?= /tmp/TokenBarDerivedData

bootstrap:
	xcodegen generate

build: bootstrap
	xcodebuild -project TokenBar.xcodeproj -scheme TokenBar -configuration Debug -destination 'platform=macOS' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build

test: bootstrap
	xcodebuild -project TokenBar.xcodeproj -scheme TokenBar -configuration Debug -destination 'platform=macOS' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO test

clean:
	xcodebuild -project TokenBar.xcodeproj -scheme TokenBar -derivedDataPath '$(DERIVED_DATA)' clean

open: bootstrap
	open ai-menu-bar.xcworkspace
