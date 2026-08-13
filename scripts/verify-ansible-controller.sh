#!/usr/bin/env bash
# LEGACY/OPTIONAL: only needed if you want to use the connection-plugin path
# (playbooks/test-ssm.yml) from a dedicated controller. The primary workflow
# (scripts/run-ansible.sh) uses SSM Run Command and needs none of this - see
# README.md "How playbooks run".
#
# Verifies that this host is correctly set up as the Ansible controller.
# Exits non-zero if any required component is missing.
set -uo pipefail

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
ok()   { echo "  OK   $*"; }
bad()  { echo "  FAIL $*" >&2; ERRORS=$((ERRORS + 1)); }

ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Single source of truth is ansible/group_vars/all.yml - never hard-code a region here.
AWS_REGION="${AWS_REGION:-$(grep -m1 '^aws_region:' "$REPO_ROOT/ansible/group_vars/all.yml" | awk '{print $2}')}"
if [ -z "$AWS_REGION" ]; then
  bad "Could not determine AWS_REGION (set the env var or check ansible/group_vars/all.yml)"
  exit 1
fi

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd found: $(command -v "$cmd")"
  else
    bad "$cmd not found on PATH"
  fi
}

log "Checking required commands..."
check_cmd git
check_cmd aws
check_cmd session-manager-plugin
check_cmd ansible
check_cmd ansible-playbook
check_cmd ansible-galaxy
check_cmd python3
python3 -m pip --version >/dev/null 2>&1 && ok "pip3 available (python3 -m pip)" || bad "pip3 (python3 -m pip) not available"

log "Checking AWS identity (EC2 instance profile, no static keys)..."
if IDENTITY="$(aws sts get-caller-identity --output json 2>&1)"; then
  ok "aws sts get-caller-identity succeeded"
  echo "$IDENTITY"
else
  bad "aws sts get-caller-identity failed: $IDENTITY"
fi

log "Checking amazon.aws collection..."
if ansible-galaxy collection list 2>/dev/null | grep -q "amazon.aws"; then
  ok "amazon.aws collection installed"
else
  bad "amazon.aws collection not installed - run: ansible-galaxy collection install -r ansible/requirements.yml"
fi

log "Checking SSM-managed instances in $AWS_REGION..."
if SSM_INSTANCES="$(aws ssm describe-instance-information --region "$AWS_REGION" --output table 2>&1)"; then
  if echo "$SSM_INSTANCES" | grep -q '"InstanceId"\|i-[0-9a-f]\{8,\}'; then
    ok "aws ssm describe-instance-information succeeded"
    echo "$SSM_INSTANCES"
  else
    bad "aws ssm describe-instance-information returned no instances in $AWS_REGION - check the region is correct"
    echo "$SSM_INSTANCES"
  fi
else
  bad "aws ssm describe-instance-information failed: $SSM_INSTANCES"
fi

echo
if [[ $ERRORS -eq 0 ]]; then
  log "All checks passed. Controller is ready."
  exit 0
else
  log "$ERRORS check(s) failed. See FAIL lines above."
  exit 1
fi
