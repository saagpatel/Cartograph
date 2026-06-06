.PHONY: generate build test clean run verify archive

ARCHIVE_PATH ?= .derivedData/archives/Cartograph.xcarchive

generate:
	xcodegen generate

build: generate
	xcodebuild -project Cartograph.xcodeproj -scheme Cartograph -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO

test: generate
	xcodebuild -project Cartograph.xcodeproj -scheme Cartograph -destination 'platform=macOS' test

run:
	./script/build_and_run.sh

verify:
	./script/build_and_run.sh --verify

archive: generate
	xcodebuild -project Cartograph.xcodeproj -scheme Cartograph -configuration Release -destination 'generic/platform=macOS' -archivePath '$(ARCHIVE_PATH)' archive

clean:
	rm -rf .build
