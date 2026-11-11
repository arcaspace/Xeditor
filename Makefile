PROJECT := Xeditor.xcodeproj
SCHEME  := Xeditor
DERIVED := build

.PHONY: bootstrap project build run clean

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

clean:
	rm -rf $(DERIVED) $(PROJECT)
