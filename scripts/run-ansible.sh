#!/usr/bin/env bash
# Convenience runner for the Ansible playbooks. Verifies the controller
# environment and SSM connectivity before running anything else, and never
# runs destructive operations automatically.
#
# Usage:
#   ./scripts/run-ansible.sh test
#   ./scripts/run-ansible.sh utilities
#   ./scripts/run-ansible.sh patch
#   ./scripts/run-ansible.sh docker
#   ./scripts/run-ansible.sh site
#
# Any extra arguments are passed straight through to ansible-playbook, e.g.:
#   ./scripts/run-ansible.sh patch -e reboot_if_required=true
#   ./scripts/run-ansible.sh site --tags docker --check
set -euo pipefail

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible"

ACTION="${1:-}"
shift || true

declare -A PLAYBOOKS=(
  [test]="playbooks/test-ssm.yml"
  [patch]="playbooks/patch.yml"
  [utilities]="playbooks/utilities.yml"
  [docker]="playbooks/docker.yml"
  [site]="playbooks/site.yml"
)

if [[ -z "$ACTION" || -z "${PLAYBOOKS[$ACTION]:-}" ]]; then
  echo "Usage: $0 {test|patch|utilities|docker|site} [extra ansible-playbook args]" >&2
  exit 1
fi

log "1/6 Verifying controller environment..."
"$SCRIPT_DIR/verify-ansible-controller.sh" || fail "Controller verification failed. Fix the issues above and retry."

cd "$ANSIBLE_DIR"

if [[ "$ACTION" != "test" ]]; then
  log "2/6 Running SSM connectivity test (gate before '$ACTION')..."
  ansible-playbook -i inventories/aws_ec2.yml playbooks/test-ssm.yml \
    || fail "SSM connectivity test failed - not proceeding with '$ACTION'."
else
  log "2/6 Requested action is 'test' - skipping the separate gate run."
fi

log "3/6 Running requested playbook: ${PLAYBOOKS[$ACTION]}"
ansible-playbook -i inventories/aws_ec2.yml "${PLAYBOOKS[$ACTION]}" "$@"

log "Done: $ACTION completed successfully."
