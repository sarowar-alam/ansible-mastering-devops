#!/usr/bin/env bash
# Run this LOCALLY (once) with an AWS profile that has IAM/S3 admin rights.
# It does NOT touch terraform-aws-vpc-ec2 - the "SSM" IAM role is looked up
# there via a data source only, so granting it extra permissions must happen
# out-of-band, here, via plain AWS CLI.
#
# What it does:
#   1. Creates a dedicated S3 bucket for Ansible's amazon.aws.aws_ssm
#      connection plugin file transfers (module code, in/out files).
#   2. Finds the IAM role behind the "SSM" instance profile.
#   3. Attaches an inline policy granting that role the SSM/EC2/S3 actions
#      the plugin and the dynamic inventory need.
#
# Usage: AWS_PROFILE=sarowar-ostad AWS_REGION=ap-south-1 ./prepare-aws-prereqs.sh
set -euo pipefail

# Git Bash on Windows mangles leading-slash args (IAM ARNs, paths) - see
# https://github.com/git-for-windows/git/issues - guard against it here.
if command -v cygpath >/dev/null 2>&1; then
  export MSYS_NO_PATHCONV=1
fi

AWS_PROFILE="${AWS_PROFILE:-sarowar-ostad}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
INSTANCE_PROFILE_NAME="${INSTANCE_PROFILE_NAME:-SSM}"
POLICY_NAME="${POLICY_NAME:-ansible-ssm-controller-policy}"

aws_cli() { aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"; }

ACCOUNT_ID="$(aws_cli sts get-caller-identity --query Account --output text)"
BUCKET_NAME="${BUCKET_NAME:-ansible-ssm-transfer-${ACCOUNT_ID}-${AWS_REGION}}"

echo "==> Account: ${ACCOUNT_ID}  Region: ${AWS_REGION}  Bucket: ${BUCKET_NAME}"

if aws_cli s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  echo "==> Bucket ${BUCKET_NAME} already exists, skipping creation"
else
  echo "==> Creating bucket ${BUCKET_NAME}"
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws_cli s3api create-bucket --bucket "$BUCKET_NAME"
  else
    aws_cli s3api create-bucket --bucket "$BUCKET_NAME" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
fi

echo "==> Blocking public access"
aws_cli s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Versioning left suspended (default/off): the aws_ssm plugin can transfer
# secrets in plaintext, and Ansible's own docs recommend no version history.
echo "==> Enabling default SSE-S3 encryption"
aws_cli s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "==> Setting 1-day lifecycle expiry on transferred objects"
aws_cli s3api put-bucket-lifecycle-configuration --bucket "$BUCKET_NAME" \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "expire-ssm-transfer-objects",
        "Status": "Enabled",
        "Filter": {},
        "Expiration": {"Days": 1},
        "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 1}
      }
    ]
  }'

echo "==> Resolving IAM role behind instance profile '${INSTANCE_PROFILE_NAME}'"
ROLE_NAME="$(aws_cli iam get-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" \
  --query 'InstanceProfile.Roles[0].RoleName' --output text)"
echo "==> Role: ${ROLE_NAME}"

POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SsmSessionForAnsibleController",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession",
        "ssm:TerminateSession",
        "ssm:ResumeSession",
        "ssm:DescribeInstanceInformation",
        "ssm:DescribeSessions",
        "ssm:GetConnectionStatus"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Ec2DescribeForDynamicInventory",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3ForAwsSsmFileTransfer",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF
)

echo "==> Attaching inline policy '${POLICY_NAME}' to role '${ROLE_NAME}'"
aws_cli iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "$POLICY_DOC"

cat <<EOF

==> Done.
    Bucket:        ${BUCKET_NAME}
    Role updated:  ${ROLE_NAME}

    Next: put "${BUCKET_NAME}" into ansible/group_vars/all.yml as
    ansible_aws_ssm_bucket_name, commit and push, then bootstrap the
    controller.
EOF
