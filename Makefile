.PHONY: generate build run install test clean dmg

generate:
	xcodegen generate

build: generate
	xcodebuild -project Znap.xcodeproj -scheme Znap -configuration Release -derivedDataPath build ONLY_ACTIVE_ARCH=NO

run: generate
	xcodebuild -project Znap.xcodeproj -scheme Znap -configuration Debug -derivedDataPath build ONLY_ACTIVE_ARCH=YES
	open build/Build/Products/Debug/Znap.app

install: build
	cp -R build/Build/Products/Release/Znap.app /Applications/

test: generate
	xcodebuild -project Znap.xcodeproj -scheme ZnapTests -configuration Debug -derivedDataPath build test ONLY_ACTIVE_ARCH=YES

clean:
	rm -rf build/ *.xcodeproj

dmg: build
	bash scripts/create-dmg.sh
