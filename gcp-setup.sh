#!/bin/bash
# agent/setup.sh
# Autonomous Cloud Fabric - GCP Zero-Touch Onboarding

set -e # Exit immediately if a command exits with a non-zero status.

echo "========================================================="
echo "🛡️ Initializing Sovereign Cloud Discovery Handshake..."
echo "========================================================="

# The EXTERNAL_ID is passed securely via the Cloud Shell URL environment variables
if [ -z "$EXTERNAL_ID" ]; then
    echo "❌ ERROR: Security token (EXTERNAL_ID) missing. Aborting."
    exit 1
fi

# 1. Prompt for Target Project
read -p "Enter the GCP Project ID to Audit: " PROJECT_ID
gcloud config set project $PROJECT_ID

echo "🔄 Enabling required Google Cloud APIs..."
gcloud services enable cloudresourcemanager.googleapis.com compute.googleapis.com cloudbilling.googleapis.com iamcredentials.googleapis.com --quiet

# 2. Create the Discovery Service Account
SA_NAME="fabric-discovery"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "👤 Provisioning Read-Only Discovery Identity..."
gcloud iam service-accounts create $SA_NAME \
    --display-name="Autonomous Fabric Discovery Agent" \
    --quiet || true # Ignore if already exists

# 3. Bind strict, read-only roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/viewer" --quiet
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/billing.viewer" --quiet

# 4. Establish Workload Identity Federation (No JSON Keys)
POOL_NAME="fabric-auth-pool"
PROVIDER_NAME="fabric-oidc-provider"

echo "🔐 Configuring Zero-Trust Workload Identity Federation..."
gcloud iam workload-identity-pools create $POOL_NAME \
    --location="global" \
    --display-name="Fabric Authentication Pool" \
    --quiet || true

gcloud iam workload-identity-pools providers create-oidc $PROVIDER_NAME \
    --location="global" \
    --workload-identity-pool=$POOL_NAME \
    --display-name="Fabric OIDC Provider" \
    --issuer-uri="http://localhost:8000" \
    --attribute-mapping="google.subject=assertion.sub" \
    --quiet || true

# 5. Bind the WIF Provider to the Service Account using the EXTERNAL_ID
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
WIF_SUBJECT="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/subject/${EXTERNAL_ID}"

gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
    --role="roles/iam.workloadIdentityUser" \
    --member="${WIF_SUBJECT}" \
    --quiet

# 6. Execute the Callback Webhook to the Backend
echo "📡 Transmitting Handshake to Command Center..."
curl -X POST "http://localhost:8000/api/v1/webhooks/gcp-connect" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${EXTERNAL_ID}" \
     -d '{
           "project_id": "'"${PROJECT_ID}"'",
           "project_number": "'"${PROJECT_NUMBER}"'",
           "service_account": "'"${SA_EMAIL}"'",
           "pool_name": "'"${POOL_NAME}"'",
           "provider_name": "'"${PROVIDER_NAME}"'"
         }'

echo ""
echo "✅ Connection Established Successfully."
echo "You may now close this terminal and return to your Fabric Dashboard."
