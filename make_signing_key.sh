#!/bin/zsh
# Run once, on the Mac that makes releases: makes "RollCall Signing", RollCall's own code-signing certificate,
# and keeps it in your login keychain. build.sh then signs every version with it, so macOS sees each update as
# the same app and keeps the permissions people gave it (keychain, Calendar, Downloads) instead of asking again.
#   ./make_signing_key.sh
# It asks for your Mac password once, so codesign can use the key without asking each build.
# Keep the certificate (Keychain Access → login → My Certificates): a new one means one more round of questions
# for everyone after the next update.
set -euo pipefail
NAME="RollCall Signing"
KEYCHAIN=~/Library/Keychains/login.keychain-db

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "$NAME is already in your login keychain; nothing to do."
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$WORK/cert.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASS=$(openssl rand -hex 16)
openssl pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/id.p12" -passout "pass:$PASS"
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Enter your Mac password, so codesign can use the key without asking (nothing shows as you type):"
security set-key-partition-list -S apple-tool:,apple: -s -l "$NAME" "$KEYCHAIN" >/dev/null
echo "Made $NAME. Builds from now on are signed with it."
