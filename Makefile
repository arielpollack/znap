.PHONY: generate build run relaunch install test clean dmg

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
