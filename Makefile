SCHEME := PiBoard
PROJECT := PiBoard.xcodeproj
DESTINATION := platform=macOS
DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/PiBoard.app
NODE_BIN := Runtime/node/bin/node
# make ui-test ONLY=MonkeyTests/testClaudeCodeActivityThroughTitleAndHooks runs one UI test.
UI_TEST_TARGET := PiBoardUITests$(if $(ONLY),/$(ONLY),)

BUNDLED_NODE := $(APP)/Contents/Resources/node/bin/node
APPICON_SOURCE := Design/appicon-1024-source.png
APPICON_SET := PiBoard/Resources/Assets.xcassets/AppIcon.appiconset
APPICON_PREVIEW := Design/appicon-preview.png

SCREENSHOT_RESULT := build/screenshots.xcresult
SCREENSHOT_DIR := docs/images

.PHONY: generate build test ui-test screenshots run clean fetch-node verify-bundle appicon release-dry-run

fetch-node:
	scripts/fetch-node.sh

$(NODE_BIN):
	scripts/fetch-node.sh

appicon:
	swift scripts/make-appicon.swift $(APPICON_SOURCE) $(APPICON_SET) --preview $(APPICON_PREVIEW)

generate: $(NODE_BIN)
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug -skipPackagePluginValidation -derivedDataPath $(DERIVED_DATA) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug -skipPackagePluginValidation -derivedDataPath $(DERIVED_DATA) -only-testing:PiBoardTests test

ui-test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug -skipPackagePluginValidation -derivedDataPath $(DERIVED_DATA) -only-testing:$(UI_TEST_TARGET) test

# README images from demo data and a scripted agent; TEST_RUNNER_ passes the variable to the UI test.
screenshots: generate
	rm -rf $(SCREENSHOT_RESULT)
	@git_path="$$(xcrun --find git)" && test -n "$$git_path" || { echo "git not found by xcrun" >&2; exit 1; }
	TEST_RUNNER_PIBOARD_README_SCREENSHOTS=1 TEST_RUNNER_PIBOARD_GIT="$$(xcrun --find git)" xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug -skipPackagePluginValidation -derivedDataPath $(DERIVED_DATA) -only-testing:PiBoardUITests/MonkeyTests/testReadmeScreenshots -resultBundlePath $(SCREENSHOT_RESULT) test
	scripts/export-screenshots.sh $(SCREENSHOT_RESULT) $(SCREENSHOT_DIR)

# Proves the bundled node runs from the built app with an empty environment.
verify-bundle:
	"$(BUNDLED_NODE)" --version
	env -i HOME="$$HOME" PATH=/usr/bin:/bin "$(BUNDLED_NODE)" -e 'console.log(process.versions.node)'

run: build
	-osascript -e 'tell application "PiBoard" to quit' >/dev/null 2>&1
	@for i in $$(seq 1 15); do pgrep -xq PiBoard || break; sleep 0.2; done
	-pkill -x PiBoard >/dev/null 2>&1
	@while pgrep -xq PiBoard; do sleep 0.2; done
	open "$(APP)"

# Local ad-hoc release; the appcast step is skipped unless SPARKLE_PRIVATE_KEY is set.
release-dry-run:
	SIGNING_MODE=adhoc VERSION=0.0.0 BUILD_NUMBER=1 CHANNEL=beta OUTPUT_DIR=build/release scripts/release.sh

clean:
	rm -rf $(PROJECT) build
