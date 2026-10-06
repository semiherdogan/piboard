SCHEME := PiBoard
PROJECT := PiBoard.xcodeproj
DESTINATION := platform=macOS
DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/PiBoard.app

.PHONY: generate build test run clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug -skipPackagePluginValidation -derivedDataPath $(DERIVED_DATA) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug -skipPackagePluginValidation -derivedDataPath $(DERIVED_DATA) test

run: build
	open "$(APP)"

clean:
	rm -rf $(PROJECT) build
