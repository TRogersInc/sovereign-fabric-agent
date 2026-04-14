#!/bin/bash
# agent/setup-do.sh
# Sovereign Shift - DigitalOcean Onboarding

set -e

echo "========================================================="
echo "🛡️ Initializing Sovereign Shift DigitalOcean Handshake..."
echo "========================================================="

if [ -z "$EXTERNAL_ID" ]; then
    echo "❌ ERROR: Security token (EXTERNAL_ID) missing. Aborting."
    exit 1
fi

echo "DigitalOcean requires a Read-Only API Token to establish a connection."
echo "Please generate one at: https://cloud.digitalocean.com/account/api/tokens"
echo ""
read -s -p "Enter your DO Read-Only API Token: " DO_TOKEN
echo ""

echo "🔄 Validating API Token..."
DO_ACCOUNT_RESPONSE=$(curl -s -X GET "https://api.digitalocean.com/v2/account" \
    -H "Authorization: Bearer $DO_TOKEN")

# Check if the token is valid by looking for the account email
DO_EMAIL=$(echo $DO_ACCOUNT_RESPONSE | grep -o '"email":"[^"]*' | cut -d'"' -f4)

if [ -z "$DO_EMAIL" ]; then
    echo "❌ ERROR: Invalid DigitalOcean Token or connection failed."
    exit 1
fi

echo "✅ Token validated for account: $DO_EMAIL"

echo "📡 Transmitting Handshake to Command Center..."
curl -X POST "https://api.yourfabric.ai/v1/webhooks/do-connect" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${EXTERNAL_ID}" \
     -d '{
           "do_account_email": "'"${DO_EMAIL}"'",
           "do_api_token": "'"${DO_TOKEN}"'"
         }'

echo ""
echo "✅ DigitalOcean Connection Established Successfully."
echo "You may now close this terminal and return to your Dashboard."
