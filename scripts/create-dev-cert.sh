#!/bin/bash
# Creates a self-signed code signing certificate for Znap development.
# This allows macOS to remember screen recording permissions across rebuilds.

CERT_NAME="Znap Dev"

# Check if it already exists
if security find-certificate -c "$CERT_NAME" &>/dev/null; then
    echo "Certificate '$CERT_NAME' already exists."
    exit 0
fi

# Create a self-signed code signing certificate using a CSR-less approach
cat > /tmp/znap-cert.cfg <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
x509_extensions    = codesign
prompt             = no

[ req_dn ]
CN = $CERT_NAME

[ codesign ]
keyUsage               = digitalSignature
extendedKeyUsage       = codeSigning
EOF

# Generate key and certificate
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /tmp/znap-dev-key.pem \
    -out /tmp/znap-dev-cert.pem \
    -days 3650 \
    -config /tmp/znap-cert.cfg 2>/dev/null

# Convert to p12 (PKCS#12) for import into Keychain
openssl pkcs12 -export \
    -inkey /tmp/znap-dev-key.pem \
    -in /tmp/znap-dev-cert.pem \
    -out /tmp/znap-dev.p12 \
    -passout pass: 2>/dev/null

# Import into login keychain
security import /tmp/znap-dev.p12 \
    -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign \
    -P "" 2>/dev/null

# Trust the certificate for code signing
security add-trusted-cert -d -r trustRoot \
    -k ~/Library/Keychains/login.keychain-db \
    /tmp/znap-dev-cert.pem 2>/dev/null

# Allow codesign to use without prompt
security set-key-partition-list -S apple-tool:,apple: -s \
    -k "" ~/Library/Keychains/login.keychain-db 2>/dev/null

# Cleanup temp files
rm -f /tmp/znap-cert.cfg /tmp/znap-dev-key.pem /tmp/znap-dev-cert.pem /tmp/znap-dev.p12

# Verify
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' created and trusted for code signing."
else
    echo "Certificate created but may need manual trust in Keychain Access."
    echo "Open Keychain Access > login > Certificates > '$CERT_NAME' > Trust > Always Trust"
fi
