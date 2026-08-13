#!/usr/bin/env bash
# Run this ON the controller (public instance) after bootstrap, from the
# repo root: bash scripts/verify-ansible-controller.sh
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${REPO_ROOT}/ansible/inventories/aws_ec2.yml"

echo "==> Caller identity (confirms the instance's IAM role/creds)"
aws sts get-caller-identity

echo
echo "==> SSM-managed instances visible to this controller"
aws ssm describe-instance-information --output table

echo
echo "==> Ansible dynamic inventory graph"
ansible-inventory -i "$INVENTORY" --graph

echo
echo "==> Pinging all hosts over amazon.aws.aws_ssm"
ansible all -i "$INVENTORY" -m ping
