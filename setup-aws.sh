#!/bin/bash
# agent/setup-aws.sh
# Sovereign Shift - AWS Zero-Touch Onboarding

set -e

echo "========================================================="
echo "🛡️ Initializing Sovereign Shift AWS Handshake..."
echo "========================================================="

if [ -z "$EXTERNAL_ID" ]; then
    echo "❌ ERROR: Security token (EXTERNAL_ID) missing. Aborting."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_URL="https://api.yourfabric.ai"
ROLE_NAME="SovereignShiftDiscoveryRole"

echo "🔐 Configuring AWS OIDC Identity Provider..."
# AWS requires a thumbprint for OIDC. This is a standard dummy/root thumbprint often used, 
# though AWS recently started trusting root CAs automatically.
THUMBPRINT="a031c46782e6e6c662c2c87c76da9aa62ccabd8e" 

# Check if provider exists, create if it doesn't
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/api.yourfabric.ai"
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
    aws iam create-open-id-connect-provider \
        --url "$OIDC_URL" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "$THUMBPRINT" >/dev/null
fi

echo "👤 Provisioning Discovery IAM Role..."
# Create the Trust Policy allowing your backend to assume this role if the sub matches EXTERNAL_ID
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "$PROVIDER_ARN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "api.yourfabric.ai:sub": "$EXTERNAL_ID"
        }
      }
    }
  ]
}
EOF

# Create Role and attach policies
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json >/dev/null 2>&1 || true
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
rm trust-policy.json

echo "📡 Transmitting Handshake to Command Center..."
curl -X POST "https://api.yourfabric.ai/v1/webhooks/aws-connect" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${EXTERNAL_ID}" \
     -d '{
           "account_id": "'"${ACCOUNT_ID}"'",
           "role_arn": "'"${ROLE_ARN}"'",
           "provider_arn": "'"${PROVIDER_ARN}"'"
         }'

echo ""
echo "✅ AWS Connection Established Successfully."
echo "You may now close this terminal and return to your Dashboard."
