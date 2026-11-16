PROJECT := Xeditor.xcodeproj
SCHEME  := Xeditor
DERIVED := build
DIST    := dist
VERSION := $(shell awk -F'"' '/MARKETING_VERSION:/ {print $$2; exit}' project.yml)
DMG     := $(DIST)/Xeditor-$(VERSION).dmg

.PHONY: bootstrap project build run release clean

bootstrap:
	./scripts/bootstrap.sh

project:
	xcodegen generate

build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build \
		CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

run: build
	open $(DERIVED)/Build/Products/Debug/Xeditor.app

release: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=macOS' \
		-derivedDataPath $(DERIVED) build \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
	./scripts/make-dmg.sh "$(DERIVED)/Build/Products/Release/Xeditor.app" "$(DMG)" "$(VERSION)"

clean:
	rm -rf $(DERIVED) $(PROJECT)
