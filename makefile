CODESIGN_IDENTITY ?= $(shell git -C "$(CURDIR)" config --get menu-bar.codesignIdentity 2>/dev/null || git -C "$(CURDIR)" config --get winmux.codesignIdentity 2>/dev/null || printf '%s' '-')
APP_NAME := My Menu Bar
APP_BUNDLE := .release/$(APP_NAME).app
INSTALL_PATH := /Applications/$(APP_NAME).app

.PHONY: build release install clean

build:
	swift build --product MyMenuBarApp

release:
	swift build -c release --product MyMenuBarApp
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp .build/release/MyMenuBarApp "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp resources/MyMenuBarInfo.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --deep --sign "$(CODESIGN_IDENTITY)" "$(APP_BUNDLE)"
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"

install: release
	-osascript -e 'tell application "My Menu Bar" to quit'
	@attempts=0; while pgrep -f '^$(INSTALL_PATH)/Contents/MacOS/$(APP_NAME)$$' >/dev/null && [ $$attempts -lt 200 ]; do sleep 0.05; attempts=$$((attempts + 1)); done
	@test -z "$$(pgrep -f '^$(INSTALL_PATH)/Contents/MacOS/$(APP_NAME)$$' | head -n 1)"
	rm -rf "$(INSTALL_PATH)"
	ditto "$(APP_BUNDLE)" "$(INSTALL_PATH)"
	open "$(INSTALL_PATH)"

clean:
	rm -rf .build .release MyMenuBar.xcodeproj
