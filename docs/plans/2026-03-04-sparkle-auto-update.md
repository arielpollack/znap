# Sparkle Auto-Update & Release Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Sparkle auto-update, create-dmg build script, and GitHub Actions release pipeline to Znap.

**Architecture:** Sparkle 2.x integrated via SPM through XcodeGen's `project.yml`. GitHub Actions workflow triggers on `v*` tags, builds the app, creates a DMG with create-dmg, signs it with Sparkle's EdDSA key, generates an appcast.xml, and publishes everything as a GitHub Release. The app checks for updates automatically on launch via the appcast URL.

**Tech Stack:** Sparkle 2.x (SPM), create-dmg (Homebrew), GitHub Actions, EdDSA signing

---

### Task 1: Add Sparkle SPM dependency to project.yml

**Files:**
- Modify: `project.yml`

**Step 1: Add Sparkle package and dependency to project.yml**

Add the `packages` section at the top level and the Sparkle dependency + settings to the Znap target:

```yaml
name: Znap
options:
  bundleIdPrefix: com.znap
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.7.0"
settings:
  SWIFT_VERSION: "5.9"
  CODE_SIGN_STYLE: Automatic
  DEVELOPMENT_TEAM: F92RQULD22
targets:
  Znap:
    type: application
    platform: macOS
    sources:
      - Znap/Sources
    resources:
      - Znap/Resources
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.znap.app
      CODE_SIGN_ENTITLEMENTS: Znap/Sources/Znap.entitlements
      INFOPLIST_FILE: Znap/Sources/Info.plist
      GENERATE_INFOPLIST_FILE: false
    dependencies:
      - package: Sparkle
  ZnapTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Znap/Tests
    dependencies:
      - target: Znap
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.znap.tests
      GENERATE_INFOPLIST_FILE: true
```

**Step 2: Add Sparkle keys to Info.plist**

Add `SUFeedURL` and `SUPublicEDKey` to `Znap/Sources/Info.plist`. The public key placeholder will be replaced after key generation:

```xml
	<key>SUFeedURL</key>
	<string>https://github.com/arielpollack/znap/releases/latest/download/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>PLACEHOLDER_EDDSA_PUBLIC_KEY</string>
```

Add these before the closing `</dict>`.

**Step 3: Verify the project generates and builds**

Run: `make build`
Expected: Build succeeds with Sparkle framework linked

**Step 4: Commit**

```bash
git add project.yml Znap/Sources/Info.plist
git commit -m "feat: add Sparkle 2.x SPM dependency and feed URL config"
```

---

### Task 2: Integrate Sparkle updater in AppDelegate and menu

**Files:**
- Modify: `Znap/Sources/AppDelegate.swift`
- Modify: `Znap/Sources/ZnapApp.swift`

**Step 1: Add Sparkle updater controller to AppDelegate**

At the top of `AppDelegate.swift`, add the import and updater controller:

```swift
import Sparkle
```

Add a property to `AppDelegate`:

```swift
let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
```

The `startingUpdater: true` parameter starts automatic update checks on launch.

**Step 2: Add "Check for Updates..." menu item to ZnapApp.swift**

In `ZnapApp.swift`, add a "Check for Updates..." button in the menu. Place it just before the "Quit" button section:

```swift
Button("Check for Updates...") {
    appDelegate.updaterController.checkForUpdates(nil)
}
```

Also update the version text to read from the bundle dynamically:

```swift
Text("Znap v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
    .foregroundColor(.secondary)
```

**Step 3: Build and verify**

Run: `make build`
Expected: Build succeeds, Sparkle updater is initialized

**Step 4: Commit**

```bash
git add Znap/Sources/AppDelegate.swift Znap/Sources/ZnapApp.swift
git commit -m "feat: integrate Sparkle updater with auto-check and menu item"
```

---

### Task 3: Replace DMG script with create-dmg

**Files:**
- Modify: `scripts/create-dmg.sh`
- Modify: `Makefile`

**Step 1: Rewrite scripts/create-dmg.sh**

Replace the entire file with a create-dmg based script:

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="Znap"
APP_PATH="build/Build/Products/Release/${APP_NAME}.app"

# Get version from Info.plist inside the built app
VERSION=$(defaults read "$(pwd)/${APP_PATH}/Contents/Info" CFBundleShortVersionString)
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: ${APP_PATH} not found. Run 'make build' first."
    exit 1
fi

# Remove previous DMG if exists
rm -f "$DMG_NAME"

echo "Creating DMG for ${APP_NAME} v${VERSION}..."

create-dmg \
    --volname "${APP_NAME}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 150 185 \
    --app-drop-link 450 185 \
    --no-internet-enable \
    "$DMG_NAME" \
    "$APP_PATH"

echo "DMG created: ${DMG_NAME}"
```

**Step 2: Update Makefile dmg target**

No change needed — the Makefile already calls `bash scripts/create-dmg.sh` and depends on `build`.

**Step 3: Verify DMG creation works locally**

Run: `brew install create-dmg` (if not already installed)
Run: `make dmg`
Expected: Produces `Znap-0.1.0.dmg` with styled window and Applications link

**Step 4: Commit**

```bash
git add scripts/create-dmg.sh
git commit -m "feat: replace hdiutil DMG script with create-dmg"
```

---

### Task 4: Add GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Step 1: Create the release workflow**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build-and-release:
    runs-on: macos-15
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install dependencies
        run: |
          brew install xcodegen create-dmg

      - name: Extract version from tag
        id: version
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "Building version $VERSION"

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Build Release
        run: |
          xcodebuild -project Znap.xcodeproj \
            -scheme Znap \
            -configuration Release \
            -derivedDataPath build \
            ONLY_ACTIVE_ARCH=NO \
            MARKETING_VERSION=${{ steps.version.outputs.version }} \
            CURRENT_PROJECT_VERSION=${{ github.run_number }} \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO

      - name: Create DMG
        run: bash scripts/create-dmg.sh

      - name: Sign update with Sparkle EdDSA
        id: sign
        run: |
          DMG_NAME="Znap-${{ steps.version.outputs.version }}.dmg"
          # Download Sparkle to get sign_update tool
          SPARKLE_VERSION="2.7.0"
          curl -L -o /tmp/sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
          mkdir -p /tmp/sparkle
          tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle

          # Sign the DMG
          SIGNATURE=$(/tmp/sparkle/bin/sign_update "$DMG_NAME" --ed-key-file <(echo "${{ secrets.SPARKLE_EDDSA_KEY }}"))
          echo "signature=$SIGNATURE" >> "$GITHUB_OUTPUT"
          echo "dmg_name=$DMG_NAME" >> "$GITHUB_OUTPUT"

          # Get file size
          SIZE=$(stat -f%z "$DMG_NAME")
          echo "size=$SIZE" >> "$GITHUB_OUTPUT"

      - name: Generate appcast.xml
        run: |
          DMG_NAME="${{ steps.sign.outputs.dmg_name }}"
          VERSION="${{ steps.version.outputs.version }}"
          SIGNATURE="${{ steps.sign.outputs.signature }}"
          SIZE="${{ steps.sign.outputs.size }}"
          BUILD_NUMBER="${{ github.run_number }}"
          DOWNLOAD_URL="https://github.com/arielpollack/znap/releases/download/${GITHUB_REF_NAME}/${DMG_NAME}"

          cat > appcast.xml << APPCAST_EOF
          <?xml version="1.0" encoding="utf-8"?>
          <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <channel>
              <title>Znap Updates</title>
              <link>https://github.com/arielpollack/znap/releases</link>
              <description>Znap app updates</description>
              <language>en</language>
              <item>
                <title>Version ${VERSION}</title>
                <sparkle:version>${BUILD_NUMBER}</sparkle:version>
                <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
                <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
                <pubDate>$(date -R)</pubDate>
                <enclosure
                  url="${DOWNLOAD_URL}"
                  ${SIGNATURE}
                  length="${SIZE}"
                  type="application/octet-stream" />
              </item>
            </channel>
          </rss>
          APPCAST_EOF

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          files: |
            ${{ steps.sign.outputs.dmg_name }}
            appcast.xml
```

**Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: add GitHub Actions release workflow with Sparkle signing"
```

---

### Task 5: Add key generation helper script and setup docs

**Files:**
- Create: `scripts/generate-sparkle-key.sh`

**Step 1: Create key generation helper script**

```bash
#!/bin/bash
set -euo pipefail

echo "=== Sparkle EdDSA Key Generation ==="
echo ""
echo "This generates an EdDSA keypair for Sparkle update signing."
echo "The PRIVATE key must be stored as a GitHub Secret named SPARKLE_EDDSA_KEY."
echo "The PUBLIC key goes in Info.plist as SUPublicEDKey."
echo ""

# Build the project first to get Sparkle tools
if [ ! -d "build/Build/Products/Release" ]; then
    echo "Building project to get Sparkle tools..."
    make build
fi

# Find generate_keys in the Sparkle build artifacts
GENERATE_KEYS=$(find build -name "generate_keys" -type f 2>/dev/null | head -1)

if [ -z "$GENERATE_KEYS" ]; then
    echo "Error: generate_keys not found. Downloading Sparkle tools..."
    SPARKLE_VERSION="2.7.0"
    curl -L -o /tmp/sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    mkdir -p /tmp/sparkle
    tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle
    GENERATE_KEYS="/tmp/sparkle/bin/generate_keys"
fi

echo "Running generate_keys..."
echo ""
"$GENERATE_KEYS"
echo ""
echo "=== Next Steps ==="
echo "1. Copy the PRIVATE key and add it as a GitHub Secret:"
echo "   gh secret set SPARKLE_EDDSA_KEY"
echo "2. Copy the PUBLIC key and replace PLACEHOLDER_EDDSA_PUBLIC_KEY in Znap/Sources/Info.plist"
```

**Step 2: Make it executable and commit**

```bash
chmod +x scripts/generate-sparkle-key.sh
git add scripts/generate-sparkle-key.sh
git commit -m "feat: add Sparkle EdDSA key generation helper script"
```

---

### Task 6: Update Makefile with release helpers

**Files:**
- Modify: `Makefile`

**Step 1: Add release-related targets to Makefile**

Add these targets after the existing `dmg` target:

```makefile
release-key:
	bash scripts/generate-sparkle-key.sh

release:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make release VERSION=1.0.0"; exit 1; fi
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	git push origin "v$(VERSION)"
	@echo "Release v$(VERSION) triggered. Check GitHub Actions for progress."
```

Update `.PHONY` to include the new targets:

```makefile
.PHONY: generate build run relaunch install test clean dmg release-key release
```

**Step 2: Commit**

```bash
git add Makefile
git commit -m "feat: add release and release-key Makefile targets"
```

---

### Task 7: Add network entitlement for Sparkle

**Files:**
- Modify: `Znap/Sources/Znap.entitlements`

**Step 1: Add outgoing network entitlement**

Sparkle needs to make outgoing HTTPS requests to check the appcast feed. Add the network client entitlement:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
```

Note: Since sandbox is disabled, the network entitlement isn't strictly required, but it's good practice for when sandboxing is enabled later.

**Step 2: Build and verify**

Run: `make build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Znap/Sources/Znap.entitlements
git commit -m "feat: add network client entitlement for Sparkle updates"
```

---

### Summary of files changed

| File | Action | Purpose |
|------|--------|---------|
| `project.yml` | Modify | Add Sparkle SPM dependency |
| `Znap/Sources/Info.plist` | Modify | Add SUFeedURL, SUPublicEDKey |
| `Znap/Sources/AppDelegate.swift` | Modify | Initialize Sparkle updater |
| `Znap/Sources/ZnapApp.swift` | Modify | Add "Check for Updates..." menu item |
| `scripts/create-dmg.sh` | Modify | Replace with create-dmg tool |
| `.github/workflows/release.yml` | Create | CI release pipeline |
| `scripts/generate-sparkle-key.sh` | Create | EdDSA key generation helper |
| `Makefile` | Modify | Add release targets |
| `Znap/Sources/Znap.entitlements` | Modify | Add network entitlement |

### Post-implementation setup

1. Run `bash scripts/generate-sparkle-key.sh` to generate EdDSA keypair
2. Store private key: `gh secret set SPARKLE_EDDSA_KEY`
3. Replace `PLACEHOLDER_EDDSA_PUBLIC_KEY` in Info.plist with the public key
4. First release: `make release VERSION=0.2.0`
