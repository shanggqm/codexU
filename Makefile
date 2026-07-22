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
LEADERSHIP_BADGES := $(sort $(wildcard Resources/LeadershipBadges/leadership-badge-l*.png))
DEPLOYMENT_TARGET ?= 13.0
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
MACOS_SDK_MAJOR := $(shell xcrun --sdk macosx --show-sdk-version 2>/dev/null | cut -d. -f1)
SWIFTC_FEATURE_FLAGS :=

ifeq ($(shell test "$(MACOS_SDK_MAJOR)" -ge 26 2>/dev/null && echo yes),yes)
SWIFTC_FEATURE_FLAGS += -D CODEXU_HAS_LIQUID_GLASS
endif

ifeq ($(SIGN_IDENTITY),-)
CODESIGN_FLAGS := --force --deep --sign -
else
CODESIGN_FLAGS := --force --deep --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS)
endif

.PHONY: build run probe test-rate-limits test-statistics-time-zone test-token-counter test-model-usage-trend test-app-server-pipe test-task-runtime test-leadership-model test-leadership-assets test-claude-skill-paths test-codex-session-link test-performance-monitor test-phase-one-gate test-particle-animation test-palettes test-macos-compatibility memory-risk-check phase-one-check phase-one-soak install dmg dmg-arm64 dmg-intel checksum checksum-arm64 checksum-intel release release-arm64 release-intel release-all release-package release-check notarize verify clean clean-dist

build: test-leadership-assets
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp "$(APP_ICON)" "$(RESOURCES_DIR)/"
	cp Resources/*.png "$(RESOURCES_DIR)/"
	cp -R Resources/LeadershipBadges "$(RESOURCES_DIR)/LeadershipBadges"
	cp -R Resources/Palettes "$(RESOURCES_DIR)/Palettes"
	/usr/bin/xattr -dr com.apple.quarantine "$(APP_DIR)" 2>/dev/null || true
	MACOSX_DEPLOYMENT_TARGET="$(DEPLOYMENT_TARGET)" swiftc -O -parse-as-library $(SWIFTC_TARGET_FLAGS) $(SWIFTC_FEATURE_FLAGS) $(SOURCES) \
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

test-rate-limits:
	./scripts/test-rate-limits.sh

test-statistics-time-zone:
	./scripts/test-statistics-time-zone.sh

test-token-counter: build
	"$(MACOS_DIR)/$(APP_NAME)" --self-test-token-counter

test-model-usage-trend: build
	"$(MACOS_DIR)/$(APP_NAME)" --self-test-model-usage-trend

test-app-server-pipe: build
	"$(MACOS_DIR)/$(APP_NAME)" --self-test-app-server-pipe

test-task-runtime: build
	"$(MACOS_DIR)/$(APP_NAME)" --self-test-task-runtime

test-leadership-model: build
	"$(MACOS_DIR)/$(APP_NAME)" --self-test-leadership-model

test-leadership-assets:
	@test "$(words $(LEADERSHIP_BADGES))" -eq 7 || { echo "expected 7 leadership badge PNGs"; exit 1; }
	@for badge in $(LEADERSHIP_BADGES); do \
		width=$$(sips -g pixelWidth "$$badge" | awk '/pixelWidth/ { print $$2 }'); \
		height=$$(sips -g pixelHeight "$$badge" | awk '/pixelHeight/ { print $$2 }'); \
		alpha=$$(sips -g hasAlpha "$$badge" | awk '/hasAlpha/ { print $$2 }'); \
		test "$$width" -ge 1024 -a "$$height" -ge 1024 -a "$$alpha" = yes || { echo "invalid leadership badge: $$badge ($$width x $$height, alpha=$$alpha)"; exit 1; }; \
	done

test-claude-skill-paths: build
	"$(MACOS_DIR)/$(APP_NAME)" --self-test-claude-skill-paths

test-codex-session-link: build
	"$(MACOS_DIR)/$(APP_NAME)" --self-test-codex-session-link

test-performance-monitor: build
	"$(MACOS_DIR)/$(APP_NAME)" --self-test-performance-monitor

test-phase-one-gate: build
	"$(MACOS_DIR)/$(APP_NAME)" --self-test-phase-one-gate

test-macos-compatibility:
	./scripts/test-macos-compatibility.sh

test-particle-animation:
	./scripts/test-particle-animation.sh

test-palettes:
	./scripts/test-palettes.sh

memory-risk-check:
	./scripts/check-memory-risks.sh

phase-one-check: build
	./scripts/phase-one-check.sh

phase-one-soak: build
	./scripts/phase-one-soak.sh

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

release-package: memory-risk-check
	./scripts/build-release-artifacts.sh "$(VERSION)"

release-check: memory-risk-check
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
