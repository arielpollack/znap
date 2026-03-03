#!/bin/bash
set -euo pipefail

echo "=== Sparkle EdDSA Key Generation ==="
echo ""
echo "This generates an EdDSA keypair for Sparkle update signing."
echo "The PRIVATE key must be stored as a GitHub Secret named SPARKLE_EDDSA_KEY."
echo "The PUBLIC key goes in Info.plist as SUPublicEDKey."
echo ""

# Download Sparkle tools
SPARKLE_VERSION="2.7.0"
SPARKLE_DIR="/tmp/sparkle"

if [ ! -f "${SPARKLE_DIR}/bin/generate_keys" ]; then
    echo "Downloading Sparkle tools..."
    curl -L -o /tmp/sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    mkdir -p "$SPARKLE_DIR"
    tar -xf /tmp/sparkle.tar.xz -C "$SPARKLE_DIR"
    rm /tmp/sparkle.tar.xz
fi

echo "Running generate_keys..."
echo ""
"${SPARKLE_DIR}/bin/generate_keys"
echo ""
echo "=== Next Steps ==="
echo "1. Copy the PRIVATE key and add it as a GitHub Secret:"
echo "   gh secret set SPARKLE_EDDSA_KEY"
echo "2. Copy the PUBLIC key and replace PLACEHOLDER_EDDSA_PUBLIC_KEY in Znap/Sources/Info.plist"
