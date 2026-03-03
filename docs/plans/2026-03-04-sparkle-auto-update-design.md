# Sparkle Auto-Update & Release Pipeline Design

## Overview

Add Sparkle 2.x auto-update mechanism to Znap, replace the existing DMG script with `create-dmg`, and create a GitHub Actions release pipeline triggered by version tags.

## Decisions

- **Sparkle via SPM** — added as Swift Package dependency in `project.yml`
- **EdDSA signing** — private key in GitHub Secrets, public key in Info.plist
- **GitHub Actions CI** — push `v*` tag triggers full build/sign/release
- **create-dmg** — replaces existing hdiutil-based script
- **Auto-check on launch** — standard Sparkle behavior, plus manual "Check for Updates" menu item
- **No notarization** — skipped for now, can be added later
- **Appcast hosted in GitHub Releases** — `appcast.xml` uploaded as release asset

## Components

### 1. Sparkle Integration (in-app)

- Add Sparkle 2.x as SPM dependency in `project.yml`
- Add `SUFeedURL` in Info.plist → `https://github.com/arielpollack/znap/releases/latest/download/appcast.xml`
- Add `SUPublicEDKey` in Info.plist with the EdDSA public key
- Initialize `SPUStandardUpdaterController` in `AppDelegate.swift`
- Add "Check for Updates..." menu item to existing menu bar menu
- Auto-check enabled by default

### 2. Build Script (create-dmg)

- Replace `scripts/create-dmg.sh` with create-dmg tool invocation
- Output: `Znap-{version}.dmg` with styled window, Applications symlink
- Used both locally (`make dmg`) and in CI

### 3. GitHub Actions Release Workflow

- **Trigger**: push tag `v*`
- **Steps**: checkout → install deps (xcodegen, create-dmg) → generate project → build release → create DMG → sign with Sparkle EdDSA → generate appcast.xml → create GitHub Release with DMG + appcast

### 4. Signing

- One-time: generate EdDSA keypair with Sparkle's `generate_keys`
- Public key: committed in Info.plist (`SUPublicEDKey`)
- Private key: `SPARKLE_EDDSA_KEY` GitHub Secret
- CI runs `sign_update` on each DMG

### 5. Versioning

- Version from git tag (strip `v` prefix)
- Build number from git describe or commit count
- Injected via xcodebuild `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
