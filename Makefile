.DEFAULT_GOAL := help
.PHONY: help bootstrap build run launch stop test clean xcode

DERIVED_DATA ?= $(CURDIR)/.build/DerivedData
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug/TokenBar.app

help:
	@echo "TokenBar commands:"
	@echo "  make run    Build and launch TokenBar"
	@echo "  make test   Build and run the test suite"
	@echo "  make stop   Stop the running development app"
	@echo "  make clean  Remove local build products"
	@echo "  make xcode  Open the project in Xcode (optional)"

bootstrap:
	@command -v xcodegen >/dev/null || { echo "XcodeGen is required. Install it with: brew install xcodegen"; exit 1; }
	@xcodegen generate

build: bootstrap
	@xcodebuild -quiet -project TokenBar.xcodeproj -scheme TokenBar -configuration Debug -destination 'platform=macOS' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build
	@echo "Built $(APP_PATH)"

run: build
	@$(MAKE) --no-print-directory stop
	@open '$(APP_PATH)'
	@echo "TokenBar is running in the menu bar."

launch:
	@test -d '$(APP_PATH)' || { echo "TokenBar has not been built. Run: make run"; exit 1; }
	@open '$(APP_PATH)'

stop:
	@if pgrep -x TokenBar >/dev/null; then pkill -x TokenBar; echo "Stopped TokenBar."; fi

test: bootstrap
	@xcodebuild -quiet -project TokenBar.xcodeproj -scheme TokenBar -configuration Debug -destination 'platform=macOS' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO test

clean:
	@xcodebuild -quiet -project TokenBar.xcodeproj -scheme TokenBar -derivedDataPath '$(DERIVED_DATA)' clean

xcode: bootstrap
	@open ai-menu-bar.xcworkspace
