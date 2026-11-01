#!/bin/bash
#
# Create a stable, machine-local code-signing identity for development builds.
#
# Apple records Accessibility permission against an app's signing requirement. An
# ad-hoc signature changes whenever the binary changes, making the Privacy &
# Security switch look enabled while the rebuilt app is not trusted. This identity
# stays in the user's login keychain and prevents that mismatch.

set -euo pipefail

IDENTITY_NAME="macKey Local Development"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
WORK_DIR="$(mktemp -d)"
CERTIFICATE="$WORK_DIR/mackey-local-cert.pem"
PRIVATE_KEY="$WORK_DIR/mackey-local-key.pem"
ARCHIVE="$WORK_DIR/mackey-local-identity.p12"
ARCHIVE_PASSWORD="mackey-local-signing"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$IDENTITY_NAME"; then
    echo "A stable local signing identity already exists: $IDENTITY_NAME"
    exit 0
fi

echo "==> Creating local signing identity"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -keyout "$PRIVATE_KEY" \
    -out "$CERTIFICATE" \
    -addext "keyUsage = critical, digitalSignature" \
    -addext "extendedKeyUsage = codeSigning" \
    -subj "/CN=$IDENTITY_NAME/OU=macKey/O=Local Development/C=US"

# Keychain's PKCS#12 importer does not accept OpenSSL 3's default PBES2 archive
# on every supported macOS release. The archive is only an in-memory transfer to
# this login keychain, so use the broadly compatible legacy encoding.
openssl pkcs12 -export -legacy \
    -inkey "$PRIVATE_KEY" \
    -in "$CERTIFICATE" \
    -out "$ARCHIVE" \
    -passout "pass:$ARCHIVE_PASSWORD"

# Trust is limited to this login keychain and lets codesign use the self-signed
# certificate. No certificate or private key leaves this Mac.
security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$CERTIFICATE"
security import "$ARCHIVE" -k "$KEYCHAIN" -P "$ARCHIVE_PASSWORD" -T /usr/bin/codesign

if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$IDENTITY_NAME"; then
    echo "The identity was created but is not available to codesign." >&2
    exit 1
fi

echo "==> Ready: $IDENTITY_NAME"
echo "Build and install macKey again, then grant Accessibility once."
