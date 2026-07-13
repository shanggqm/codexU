APP_NAME := codexU
DISPLAY_NAME := codexU
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo 0.1.0)
BUILD_DIR := build
DIST_DIR := dist
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP_DIR)/Contents/MacOS
RESOURCES_DIR := $(APP_DIR)/Contents/Resources
SOURCES := $(shell find Sources/CodexUsageWidget -name '*.swift' | sort)
APP_ICON := Resources/codexU.icns
DEPLOYMENT_TARGET ?= 14.0
HOST_ARCH := $(shell uname -m)
APPLE_SILICON_TARGET_TRIPLE ?= arm64-apple-macos$(DEPLOYMENT_TARGET)
INTEL_TARGET_TRIPLE ?= x86_64-apple-macos$(DEPLOYMENT_TARGET)
TARGET_TRIPLE ?= $(HOST_ARCH)-apple-macos$(DEPLOYMENT_TARGET)
ARCH_NAME := $(shell echo "$(TARGET_TRIPLE)" | sed -E 's/-apple-macos.*//')
DMG_NAME := $(APP_NAME)-$(VERSION)-mac-$(ARCH_NAME).dmg
DMG_PATH := $(DIST_DIR)/$(DMG_NAME)
SIGN_IDENTITY ?= -
CODESIGN_EXTRA_FLAGS ?=
SWIFTC_TARGET_FLAGS := -target $(TARGET_TRIPLE)

ifeq ($(SIGN_IDENTITY),-)
CODESIGN_FLAGS := --force --deep --sign -
else
CODESIGN_FLAGS := --force --deep --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS)
endif

.PHONY: build run probe test-statistics-time-zone install dmg dmg-arm64 dmg-intel checksum checksum-arm64 checksum-intel release release-arm64 release-intel release-all release-package release-check notarize verify clean clean-dist

build:
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp "$(APP_ICON)" "$(RESOURCES_DIR)/"
	cp Resources/*.png "$(RESOURCES_DIR)/"
	/usr/bin/xattr -dr com.apple.quarantine "$(APP_DIR)" 2>/dev/null || true
	MACOSX_DEPLOYMENT_TARGET="$(DEPLOYMENT_TARGET)" swiftc -O -parse-as-library $(SWIFTC_TARGET_FLAGS) $(SOURCES) \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		-framework Cocoa \
		-framework Carbon \
		-framework SwiftUI
	codesign $(CODESIGN_FLAGS) "$(APP_DIR)"
	codesign --verify --deep --strict "$(APP_DIR)"

run: build
	open "$(APP_DIR)"

probe: build
	"$(MACOS_DIR)/$(APP_NAME)" --dump-json

test-statistics-time-zone:
	./scripts/test-statistics-time-zone.sh

install: build
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_DIR)" "/Applications/$(APP_NAME).app"
	open "/Applications/$(APP_NAME).app"

dmg: build
	APP_NAME="$(APP_NAME)" \
	DISPLAY_NAME="$(DISPLAY_NAME)" \
	VERSION="$(VERSION)" \
	ARCH_NAME="$(ARCH_NAME)" \
	BUILD_DIR="$(BUILD_DIR)" \
	DIST_DIR="$(DIST_DIR)" \
	APP_DIR="$(APP_DIR)" \
	DMG_PATH="$(DMG_PATH)" \
	DMG_SIGN_IDENTITY="$(DMG_SIGN_IDENTITY)" \
	./scripts/package-dmg.sh

dmg-arm64:
	$(MAKE) dmg TARGET_TRIPLE="$(APPLE_SILICON_TARGET_TRIPLE)"

dmg-intel:
	$(MAKE) dmg TARGET_TRIPLE="$(INTEL_TARGET_TRIPLE)"

checksum: dmg
	shasum -a 256 "$(DMG_PATH)" > "$(DMG_PATH).sha256"
	@cat "$(DMG_PATH).sha256"

checksum-arm64:
	$(MAKE) checksum TARGET_TRIPLE="$(APPLE_SILICON_TARGET_TRIPLE)"

checksum-intel:
	$(MAKE) checksum TARGET_TRIPLE="$(INTEL_TARGET_TRIPLE)"

release: clean checksum
	@echo "Release artifact: $(DMG_PATH)"

release-arm64:
	$(MAKE) release TARGET_TRIPLE="$(APPLE_SILICON_TARGET_TRIPLE)"

release-intel:
	$(MAKE) release TARGET_TRIPLE="$(INTEL_TARGET_TRIPLE)"

release-all: clean-dist
	$(MAKE) release-arm64
	$(MAKE) release-intel

release-package:
	./scripts/build-release-artifacts.sh "$(VERSION)"

release-check:
	./scripts/check-release-ready.sh "$(VERSION)"

notarize: dmg
	APPLE_ID="$(APPLE_ID)" \
	TEAM_ID="$(TEAM_ID)" \
	NOTARY_PASSWORD="$(NOTARY_PASSWORD)" \
	DMG_PATH="$(DMG_PATH)" \
	./scripts/notarize-dmg.sh

verify: build
	file "$(MACOS_DIR)/$(APP_NAME)"
	codesign -dv --verbose=4 "$(APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)"

clean-dist:
	rm -rf "$(DIST_DIR)"
