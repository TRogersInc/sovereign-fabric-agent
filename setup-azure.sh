#!/bin/bash
# agent/setup-azure.sh
# Sovereign Shift - Azure Zero-Touch Onboarding

set -e

echo "========================================================="
echo "🛡️ Initializing Sovereign Shift Azure Handshake..."
echo "========================================================="

if [ -z "$EXTERNAL_ID" ]; then
    echo "❌ ERROR: Security token (EXTERNAL_ID) missing. Aborting."
    exit 1
fi

APP_NAME="SovereignShift-Discovery-${EXTERNAL_ID:0:8}"
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "👤 Provisioning Azure App Registration & Service Principal..."
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)

# Wait a moment for Azure AD replication
sleep 15 

echo "🔐 Assigning Read-Only and Billing Roles..."
az role assignment create --assignee "$APP_ID" --role "Reader" --scope "/subscriptions/$SUB_ID" >/dev/null
az role assignment create --assignee "$APP_ID" --role "Billing Reader" --scope "/subscriptions/$SUB_ID" >/dev/null

echo "🔐 Configuring Federated Identity (OIDC)..."
cat > fed-cred.json <<EOF
{
  "name": "sovereign-shift-fed",
  "issuer": "https://api.yourfabric.ai",
  "subject": "$EXTERNAL_ID",
  "description": "Sovereign Shift Zero-Trust Auth",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF

az ad app federated-credential create --id "$OBJECT_ID" --parameters @fed-cred.json >/dev/null
rm fed-cred.json

echo "📡 Transmitting Handshake to Command Center..."
curl -X POST "https://api.yourfabric.ai/v1/webhooks/azure-connect" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${EXTERNAL_ID}" \
     -d '{
           "tenant_id": "'"${TENANT_ID}"'",
           "subscription_id": "'"${SUB_ID}"'",
           "client_id": "'"${APP_ID}"'"
         }'

echo ""
echo "✅ Azure Connection Established Successfully."
echo "You may now close this terminal and return to your Dashboard."
