#!/usr/bin/env bash
# Runs Ansible playbooks against the private servers via AWS Systems
# Manager Run Command (the AWS-owned AWS-ApplyAnsiblePlaybooks document).
#
# Why: the amazon.aws.aws_ssm Ansible *connection plugin* cannot do
# become/sudo at all (open upstream bug: ansible-collections/amazon.aws#2640),
# and SSM Session Manager's "Run As" feature can't substitute for it either
# (the SSM Agent hard-rejects runAsDefaultUser: root). AWS-ApplyAnsiblePlaybooks
# sidesteps this entirely: it pulls this repo's ansible/ folder from GitHub
# onto the target and runs `ansible-playbook -i "localhost," -c local`
# LOCALLY, as root (Run Command's aws:runShellScript step always runs as
# root on Linux) - no connection plugin, no become, ever.
#
# Because this is a plain AWS API call (ssm:SendCommand), it can be run from
# ANYWHERE with the sarowar-ostad AWS CLI profile (or instance role)
# configured - your laptop, CI, or the controller. No SSH, no VPC-internal
# network path required.
#
# Usage:
#   ./scripts/run-ansible.sh test
#   ./scripts/run-ansible.sh utilities
#   ./scripts/run-ansible.sh patch
#   ./scripts/run-ansible.sh docker
#   ./scripts/run-ansible.sh site
#
# Extra args are passed through as Ansible `-e key=value` extra vars, e.g.:
#   ./scripts/run-ansible.sh patch reboot_if_required=true
set -euo pipefail

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Single source of truth is ansible/group_vars/all.yml - never hard-code
# region/project/environment here.
AWS_REGION="${AWS_REGION:-$(grep -m1 '^aws_region:' "$REPO_ROOT/ansible/group_vars/all.yml" | awk '{print $2}')}"
PROJECT_NAME="${PROJECT_NAME:-$(grep -m1 '^project_name:' "$REPO_ROOT/ansible/group_vars/all.yml" | awk '{print $2}')}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-$(grep -m1 '^environment_name:' "$REPO_ROOT/ansible/group_vars/all.yml" | awk '{print $2}')}"

GITHUB_OWNER="${GITHUB_OWNER:-sarowar-alam}"
GITHUB_REPO="${GITHUB_REPO:-ansible-mastering-devops}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

AWS_PROFILE_ARGS=()
if [[ -n "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE_ARGS=(--profile "$AWS_PROFILE")
fi
AWS_ARGS=(--region "$AWS_REGION" "${AWS_PROFILE_ARGS[@]}")

ACTION="${1:-}"
shift || true
EXTRA_VARS="SSM=True $*"

declare -A PLAYBOOKS=(
  [test]="playbooks/test-ssm.yml"
  [patch]="playbooks/patch.yml"
  [utilities]="playbooks/utilities.yml"
  [docker]="playbooks/docker.yml"
  [site]="playbooks/site.yml"
)

if [[ -z "$ACTION" || -z "${PLAYBOOKS[$ACTION]:-}" ]]; then
  echo "Usage: $0 {test|patch|utilities|docker|site} [key=value ...]" >&2
  exit 1
fi
if [[ -z "$AWS_REGION" ]]; then
  fail "Could not determine AWS_REGION (set the env var or check ansible/group_vars/all.yml)"
fi

log "1/4 Resolving running private-server instance IDs (tags Project=$PROJECT_NAME, Environment=$ENVIRONMENT_NAME, Role=private)..."
INSTANCE_IDS="$(aws ec2 describe-instances "${AWS_ARGS[@]}" \
  --filters "Name=tag:Project,Values=$PROJECT_NAME" \
            "Name=tag:Environment,Values=$ENVIRONMENT_NAME" \
            "Name=tag:Role,Values=private" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)"

if [[ -z "$INSTANCE_IDS" ]]; then
  fail "No running private-server instances found in $AWS_REGION with the expected tags."
fi
log "Targets: $INSTANCE_IDS"

# Passed inline (not via file://) - on Git Bash, a mktemp path like /tmp/xxx
# is an MSYS-only path that the native aws.exe cannot resolve, so a file://
# reference to it fails with "No such file or directory".
PARAMS_JSON=$(cat <<EOF
{
  "SourceType": ["GitHub"],
  "SourceInfo": ["{\"owner\":\"$GITHUB_OWNER\",\"repository\":\"$GITHUB_REPO\",\"path\":\"ansible\",\"getOptions\":\"branch:$GITHUB_BRANCH\"}"],
  "InstallDependencies": ["True"],
  "PlaybookFile": ["${PLAYBOOKS[$ACTION]}"],
  "ExtraVariables": ["$EXTRA_VARS"],
  "Verbose": ["-v"]
}
EOF
)

TARGETS_ARG="Key=InstanceIds,Values=$(echo "$INSTANCE_IDS" | tr '\t' ',' | tr ' ' ',')"

log "2/4 Sending AWS-ApplyAnsiblePlaybooks command (playbook: ${PLAYBOOKS[$ACTION]})..."
COMMAND_ID="$(aws ssm send-command "${AWS_ARGS[@]}" \
  --document-name AWS-ApplyAnsiblePlaybooks \
  --targets "$TARGETS_ARG" \
  --parameters "$PARAMS_JSON" \
  --query 'Command.CommandId' --output text)"
log "CommandId: $COMMAND_ID"

log "3/4 Waiting for completion on each target..."
OVERALL_STATUS=0
for id in $INSTANCE_IDS; do
  aws ssm wait command-executed "${AWS_ARGS[@]}" --command-id "$COMMAND_ID" --instance-id "$id" 2>/dev/null || true

  INVOCATION="$(aws ssm get-command-invocation "${AWS_ARGS[@]}" --command-id "$COMMAND_ID" --instance-id "$id")"
  STATUS="$(echo "$INVOCATION" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Status"])' 2>/dev/null || echo "Unknown")"

  echo "----- $id: $STATUS -----"
  echo "$INVOCATION" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("StandardOutputContent",""))' 2>/dev/null || echo "$INVOCATION"
  if [[ "$STATUS" != "Success" ]]; then
    echo "----- $id: stderr -----" >&2
    echo "$INVOCATION" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("StandardErrorContent",""))' 2>/dev/null >&2 || true
    OVERALL_STATUS=1
  fi
done

log "4/4 Done: $ACTION finished with $( [[ $OVERALL_STATUS -eq 0 ]] && echo "SUCCESS" || echo "FAILURES" )."
exit $OVERALL_STATUS
