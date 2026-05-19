# Shade build system. Targets:
#   make            build/Shade.app (default)
#   make run        build + relaunch
#   make dmg        build/Shade.dmg with drag-to-Applications shortcut
#   make icon       regenerate Resources/AppIcon.icns from AppIcon.png
#   make clean      remove build/
#
# Variables:
#   CONFIG=release|debug             swift build configuration (default: release)
#   DEVELOPER_ID="Developer ID …"    sign for distribution; otherwise ad-hoc

CONFIG ?= release
APP_NAME := Shade

# Version stamping. CI builds tagged commits and gets a clean "0.1.3"; local
# dev builds on top of a tag get the descriptive "0.1.3-2-gabc123-dirty"
# string, which is more useful than a stale "0.1.0" in About / Diagnostics
# / bug reports. The `-` and hash characters in dev builds are non-standard
# for CFBundleShortVersionString but accepted by macOS for ad-hoc bundles.
VERSION ?= $(shell git describe --tags --dirty 2>/dev/null | sed 's/^v//')
ifeq ($(VERSION),)
VERSION := dev
endif
BUILD ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
APP_DIR := build/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS)/MacOS
RESOURCES_DIR := $(CONTENTS)/Resources
DMG_PATH := build/$(APP_NAME).dmg
STAGE_DIR := build/dmg-stage

ICON_SRC := Resources/AppIcon.png
ICON_OUT := Resources/AppIcon.icns
ICON_SPECS := \
    16:icon_16x16.png \
    32:icon_16x16@2x.png \
    32:icon_32x32.png \
    64:icon_32x32@2x.png \
    128:icon_128x128.png \
    256:icon_128x128@2x.png \
    256:icon_256x256.png \
    512:icon_256x256@2x.png \
    512:icon_512x512.png \
    1024:icon_512x512@2x.png

.DEFAULT_GOAL := build
.PHONY: build run dmg icon clean

build: $(ICON_OUT)
	@echo "→ swift build -c $(CONFIG)"
	@swift build -c $(CONFIG)
	@BIN_PATH="$$(swift build -c $(CONFIG) --show-bin-path)"; \
	EXECUTABLE="$${BIN_PATH}/$(APP_NAME)"; \
	if [ ! -x "$${EXECUTABLE}" ]; then \
	    echo "error: executable not found at $${EXECUTABLE}" >&2; \
	    exit 1; \
	fi; \
	echo "→ bundling $(APP_DIR)"; \
	rm -rf "$(APP_DIR)"; \
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"; \
	cp "$${EXECUTABLE}" "$(MACOS_DIR)/$(APP_NAME)"; \
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"; \
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(CONTENTS)/Info.plist"; \
	plutil -replace CFBundleVersion -string "$(BUILD)" "$(CONTENTS)/Info.plist"; \
	if [ -f "$(ICON_OUT)" ]; then cp "$(ICON_OUT)" "$(RESOURCES_DIR)/AppIcon.icns"; fi; \
	if [ -f Resources/MenubarIcon.png ]; then cp Resources/MenubarIcon.png "$(RESOURCES_DIR)/MenubarIcon.png"; fi; \
	if [ -d integrations ]; then cp -R integrations "$(RESOURCES_DIR)/integrations"; fi; \
	SIGN_IDENTITY="$${DEVELOPER_ID:--}"; \
	if [ "$${SIGN_IDENTITY}" = "-" ]; then \
	    echo "→ ad-hoc signing"; \
	    codesign --force --sign - "$(APP_DIR)" >/dev/null; \
	else \
	    echo "→ signing with $${SIGN_IDENTITY}"; \
	    codesign --force --options runtime --timestamp --sign "$${SIGN_IDENTITY}" "$(APP_DIR)"; \
	fi; \
	echo "✓ built $(APP_DIR)"

$(ICON_OUT): $(ICON_SRC)
	@echo "→ generating $@"
	@ICONSET="$$(mktemp -d)/AppIcon.iconset"; \
	mkdir -p "$${ICONSET}"; \
	for spec in $(ICON_SPECS); do \
	    SIZE=$${spec%%:*}; \
	    NAME=$${spec#*:}; \
	    sips -z $${SIZE} $${SIZE} "$(ICON_SRC)" --out "$${ICONSET}/$${NAME}" >/dev/null; \
	done; \
	mkdir -p Resources; \
	iconutil -c icns "$${ICONSET}" -o "$(ICON_OUT)"; \
	echo "✓ wrote $(ICON_OUT)"

icon: $(ICON_OUT)

run: build
	@pkill -x $(APP_NAME) >/dev/null 2>&1 || true
	@echo "→ launching $(APP_DIR)"
	@open "$(APP_DIR)"

dmg: build
	@rm -rf "$(STAGE_DIR)" "$(DMG_PATH)"
	@mkdir -p "$(STAGE_DIR)"
	@cp -R "$(APP_DIR)" "$(STAGE_DIR)/$(APP_NAME).app"
	@ln -s /Applications "$(STAGE_DIR)/Applications"
	@hdiutil create \
	    -volname "$(APP_NAME)" \
	    -srcfolder "$(STAGE_DIR)" \
	    -ov \
	    -format UDZO \
	    "$(DMG_PATH)" >/dev/null
	@rm -rf "$(STAGE_DIR)"
	@echo "✓ built $(DMG_PATH)"

clean:
	@rm -rf build
	@echo "✓ cleaned build/"
