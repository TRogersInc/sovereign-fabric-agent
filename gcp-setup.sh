#!/bin/bash
# agent/setup.sh
# Sovereign Shift - GCP Zero-Touch Onboarding (FinOps Edition)

set -e # Exit immediately if a command exits with a non-zero status.

echo "========================================================="
echo "🛡️ Initializing Sovereign Shift Discovery Handshake..."
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
# Note: cloudbilling.googleapis.com is the correct API name for Billing
gcloud services enable \
    cloudresourcemanager.googleapis.com \
    compute.googleapis.com \
    cloudbilling.googleapis.com \
    iamcredentials.googleapis.com \
    bigquery.googleapis.com \
    --quiet

# 2. Create the Discovery Service Account
SA_NAME="fabric-discovery"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "👤 Provisioning Discovery Identity..."
gcloud iam service-accounts create $SA_NAME \
    --display-name="Sovereign Shift Discovery Agent" \
    --quiet || true # Ignore if already exists

# ==========================================
# ⏳ THE FIX: Wait for IAM Propagation
# ==========================================
echo "⏳ Waiting 15 seconds for Google Cloud IAM propagation..."
sleep 15

# 3. Bind strict, read-only infrastructure roles
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:${SA_EMAIL}" --role="roles/viewer" --quiet
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:${SA_EMAIL}" --role="roles/billing.viewer" --quiet

# ==========================================
# 📊 NEW: FINOPS & BIGQUERY TELEMETRY SETUP
# ==========================================
DATASET_NAME="sovereign_finops_export"

echo "📊 Provisioning BigQuery Dataset for Financial Telemetry..."
# Create the dataset if it doesn't exist. Using US multi-region as a default.
bq mk --location=US -d \
    --description "Billing Export for Sovereign Shift FinOps Engine" \
    ${PROJECT_ID}:${DATASET_NAME} || true

echo "🔐 Granting Financial Data Access..."
# Allow the agent to run queries and read the billing data
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/bigquery.dataViewer" --quiet
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/bigquery.jobUser" --quiet

# ==========================================
# 🔐 WORKLOAD IDENTITY FEDERATION
# ==========================================
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

# Bind the WIF Provider to the Service Account using the EXTERNAL_ID
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
WIF_SUBJECT="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/subject/${EXTERNAL_ID}"

gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
    --role="roles/iam.workloadIdentityUser" \
    --member="${WIF_SUBJECT}" \
    --quiet

# ==========================================
# 📡 THE CALLBACK
# ==========================================
echo "📡 Transmitting Handshake to Command Center..."
curl -X POST "http://localhost:8000/api/v1/webhooks/gcp-connect" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${EXTERNAL_ID}" \
     -d '{
           "project_id": "'"${PROJECT_ID}"'",
           "project_number": "'"${PROJECT_NUMBER}"'",
           "service_account": "'"${SA_EMAIL}"'",
           "pool_name": "'"${POOL_NAME}"'",
           "provider_name": "'"${PROVIDER_NAME}"'",
           "bigquery_dataset": "'"${PROJECT_ID}:${DATASET_NAME}"'"
         }'

echo ""
echo "✅ Connection Established Successfully."
echo "⚠️ FINAL STEP REQUIRED: Please go to GCP Console -> Billing -> Billing Export and link your active Billing Account to the new '${DATASET_NAME}' dataset."
echo "You may now close this terminal and return to your Dashboard."
