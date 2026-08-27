#!/usr/bin/env bash
set -e

# Decode keystore from base64
echo "$KEYSTORE_BASE64" | base64 --decode > android/grocery-erp-keystore.jks

# Create key.properties
cat > android/key.properties <<EOF
storePassword=$KEYSTORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=grocery-erp-keystore.jks
EOF

echo "Keystore and key.properties created successfully"
ls -la android/grocery-erp-keystore.jks android/key.properties
