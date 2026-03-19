#!/usr/bin/env bash
###############################################################################
# HelixBeat – Bootstrap Script
# Creates the Terraform remote state infrastructure (S3 + DynamoDB) that
# must exist BEFORE running terraform init in any environment.
#
# Usage:
#   ./scripts/bootstrap.sh <environment> <country> <aws_region>
#
# Examples:
#   ./scripts/bootstrap.sh dev  us us-east-1
#   ./scripts/bootstrap.sh dev  in ap-south-1
#   ./scripts/bootstrap.sh staging us us-east-1
#   ./scripts/bootstrap.sh staging in ap-south-1
#
# Future countries (just pass the right region):
#   ./scripts/bootstrap.sh dev  om me-central-1
#   ./scripts/bootstrap.sh dev  my ap-southeast-5
#   ./scripts/bootstrap.sh dev  lk ap-south-1
#   ./scripts/bootstrap.sh dev  id ap-southeast-3
###############################################################################

set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment> <country> <aws_region>}"
COUNTRY="${2:?Usage: $0 <environment> <country> <aws_region>}"
AWS_REGION="${3:?Usage: $0 <environment> <country> <aws_region>}"
ACCOUNT_ID=$(AWS_PROFILE=helixbeat aws sts get-caller-identity --query Account --output text)

STATE_BUCKET="helixbeat-tfstate-${ENVIRONMENT}-${COUNTRY}"
LOCK_TABLE="helixbeat-tfstate-lock-${ENVIRONMENT}-${COUNTRY}"

echo "==================================================================="
echo " HelixBeat Bootstrap"
echo " Environment : ${ENVIRONMENT}"
echo " Country     : ${COUNTRY}"
echo " Account     : ${ACCOUNT_ID}"
echo " Region      : ${AWS_REGION}"
echo " S3 Bucket   : ${STATE_BUCKET}"
echo " DynamoDB    : ${LOCK_TABLE}"
echo "==================================================================="

AWS="AWS_PROFILE=helixbeat aws --region ${AWS_REGION}"

# ── S3 State Bucket ──────────────────────────────────────────────────────────
echo ""
echo "[1/4] Creating Terraform state S3 bucket..."

if AWS_PROFILE=helixbeat aws s3api head-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}" 2>/dev/null; then
  echo "  ✓ Bucket ${STATE_BUCKET} already exists"
else
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    AWS_PROFILE=helixbeat aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${AWS_REGION}"
  else
    AWS_PROFILE=helixbeat aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
  echo "  ✓ Bucket ${STATE_BUCKET} created"
fi

AWS_PROFILE=helixbeat aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled \
  --region "${AWS_REGION}"
echo "  ✓ Versioning enabled"

AWS_PROFILE=helixbeat aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --region "${AWS_REGION}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
      "BucketKeyEnabled": true
    }]
  }'
echo "  ✓ Encryption enabled"

AWS_PROFILE=helixbeat aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --region "${AWS_REGION}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "  ✓ Public access blocked"

AWS_PROFILE=helixbeat aws s3api put-bucket-policy \
  --bucket "${STATE_BUCKET}" \
  --region "${AWS_REGION}" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"DenyNonHTTPS\",
      \"Effect\": \"Deny\",
      \"Principal\": \"*\",
      \"Action\": \"s3:*\",
      \"Resource\": [
        \"arn:aws:s3:::${STATE_BUCKET}\",
        \"arn:aws:s3:::${STATE_BUCKET}/*\"
      ],
      \"Condition\": { \"Bool\": { \"aws:SecureTransport\": \"false\" } }
    }]
  }"
echo "  ✓ HTTPS-only bucket policy applied"

# ── DynamoDB Lock Table ───────────────────────────────────────────────────────
echo ""
echo "[2/4] Creating DynamoDB state-lock table..."

if AWS_PROFILE=helixbeat aws dynamodb describe-table \
    --table-name "${LOCK_TABLE}" \
    --region "${AWS_REGION}" 2>/dev/null | grep -q TableName; then
  echo "  ✓ Table ${LOCK_TABLE} already exists"
else
  AWS_PROFILE=helixbeat aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" \
    --sse-specification Enabled=true \
    --tags \
      Key=Project,Value=helixbeat \
      Key=Environment,Value="${ENVIRONMENT}" \
      Key=Country,Value="${COUNTRY}" \
      Key=ManagedBy,Value=bootstrap
  echo "  ✓ Table ${LOCK_TABLE} created"
fi

# ── Enable GuardDuty ─────────────────────────────────────────────────────────
echo ""
echo "[3/4] Enabling GuardDuty in ${AWS_REGION}..."
DETECTOR_ID=$(AWS_PROFILE=helixbeat aws guardduty list-detectors \
  --region "${AWS_REGION}" \
  --query 'DetectorIds[0]' \
  --output text)

if [ "${DETECTOR_ID}" != "None" ] && [ -n "${DETECTOR_ID}" ]; then
  echo "  ✓ GuardDuty already enabled (Detector: ${DETECTOR_ID})"
else
  DETECTOR_ID=$(AWS_PROFILE=helixbeat aws guardduty create-detector \
    --enable \
    --region "${AWS_REGION}" \
    --query 'DetectorId' \
    --output text)
  echo "  ✓ GuardDuty enabled (Detector: ${DETECTOR_ID})"
fi

# ── Verify prerequisites ──────────────────────────────────────────────────────
echo ""
echo "[4/4] Verifying tool prerequisites..."

MISSING_TOOLS=false
check_tool() {
  local tool="$1"
  if command -v "${tool}" &>/dev/null; then
    echo "  ✓ ${tool}"
  else
    echo "  ✗ ${tool} – not found (install before running terraform)"
    MISSING_TOOLS=true
  fi
}

check_tool terraform
check_tool kubectl
check_tool helm
check_tool aws

if [ "${MISSING_TOOLS}" = "true" ]; then
  echo ""
  echo "  ⚠ Some tools are missing. Install them first."
fi

echo ""
echo "==================================================================="
echo " Bootstrap complete! Next steps:"
echo ""
echo "  cd terraform/environments/${ENVIRONMENT}-${COUNTRY}"
echo "  terraform init"
echo "  terraform validate"
echo "  terraform plan -out=${ENVIRONMENT}-${COUNTRY}.tfplan"
echo "  terraform apply ${ENVIRONMENT}-${COUNTRY}.tfplan"
echo ""
echo " After apply, deploy monitoring:"
echo "  ./scripts/deploy-monitoring.sh ${ENVIRONMENT} ${COUNTRY} ${AWS_REGION}"
echo "==================================================================="
