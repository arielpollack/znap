.PHONY: generate build run relaunch install test clean dmg release-key release

generate:
	xcodegen generate

build: generate
	xcodebuild -project Znap.xcodeproj -scheme Znap -configuration Release -derivedDataPath build ONLY_ACTIVE_ARCH=NO

run: build
	-@killall Znap 2>/dev/null; true
	@sleep 0.5
	open build/Build/Products/Release/Znap.app

relaunch:
	-@killall Znap 2>/dev/null; true
	@sleep 0.5
	open build/Build/Products/Release/Znap.app

install: build
	cp -R build/Build/Products/Release/Znap.app /Applications/

test: generate
	xcodebuild -project Znap.xcodeproj -scheme ZnapTests -configuration Debug -derivedDataPath build test ONLY_ACTIVE_ARCH=YES

clean:
	rm -rf build/ *.xcodeproj

dmg: build
	bash scripts/create-dmg.sh

release-key:
	bash scripts/generate-sparkle-key.sh

release:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make release VERSION=1.0.0"; exit 1; fi
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	git push origin "v$(VERSION)"
	@echo "Release v$(VERSION) triggered. Check GitHub Actions for progress."
