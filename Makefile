SCHEME := PiBoard
PROJECT := PiBoard.xcodeproj
DESTINATION := platform=macOS
DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/PiBoard.app
NODE_BIN := Runtime/node/bin/node

.PHONY: generate build test run clean fetch-node

fetch-node:
	scripts/fetch-node.sh

$(NODE_BIN):
	scripts/fetch-node.sh

generate: $(NODE_BIN)
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug -skipPackagePluginValidation -derivedDataPath $(DERIVED_DATA) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug -skipPackagePluginValidation -derivedDataPath $(DERIVED_DATA) test

run: build
	-osascript -e 'tell application "PiBoard" to quit' >/dev/null 2>&1
	@while pgrep -xq PiBoard; do sleep 0.2; done
	open "$(APP)"

clean:
	rm -rf $(PROJECT) build
