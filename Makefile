.PHONY: generate build test clean run verify archive export-app-store export-developer-id

ARCHIVE_PATH ?= .derivedData/archives/Cartograph.xcarchive
APP_STORE_EXPORT_PATH ?= .derivedData/exports/app-store-connect
DEVELOPER_ID_EXPORT_PATH ?= .derivedData/exports/developer-id
APP_STORE_EXPORT_OPTIONS ?= Config/ExportOptions/AppStoreConnect.plist
DEVELOPER_ID_EXPORT_OPTIONS ?= Config/ExportOptions/DeveloperID.plist

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

export-app-store: archive
	xcodebuild -exportArchive -archivePath '$(ARCHIVE_PATH)' -exportPath '$(APP_STORE_EXPORT_PATH)' -exportOptionsPlist '$(APP_STORE_EXPORT_OPTIONS)' -allowProvisioningUpdates

export-developer-id: archive
	xcodebuild -exportArchive -archivePath '$(ARCHIVE_PATH)' -exportPath '$(DEVELOPER_ID_EXPORT_PATH)' -exportOptionsPlist '$(DEVELOPER_ID_EXPORT_OPTIONS)' -allowProvisioningUpdates

clean:
	rm -rf .build
