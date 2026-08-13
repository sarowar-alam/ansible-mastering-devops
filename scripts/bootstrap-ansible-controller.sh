#!/usr/bin/env bash
# LEGACY/OPTIONAL: only needed if you want to use the connection-plugin path
# (playbooks/test-ssm.yml) from a dedicated controller. The primary workflow
# (scripts/run-ansible.sh) uses SSM Run Command and needs none of this - see
# README.md "How playbooks run".
#
# Converts a clean Ubuntu 26.04 EC2 instance (dev-public-01) into an Ansible
# controller: basic utilities, AWS CLI v2, the SSM Session Manager plugin,
# and Ansible (in a dedicated venv) with the required collections.
#
# Idempotent: safe to run multiple times. Uses the EC2 IAM instance profile
# for AWS auth - never writes static AWS credentials anywhere.
set -euo pipefail

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

if [[ $EUID -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
  command -v sudo >/dev/null 2>&1 || fail "This script needs root or sudo privileges."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible"
VENV_DIR="/opt/ansible-venv"
ARCH="$(uname -m)"

log "Repository root: $REPO_ROOT"
log "Ansible directory: $ANSIBLE_DIR"
[[ -f "$ANSIBLE_DIR/requirements.yml" ]] || fail "Expected $ANSIBLE_DIR/requirements.yml - run this script from a clone of the repository."

# --- 1. Basic utilities -----------------------------------------------------
log "Updating apt package index..."
$SUDO apt-get update -y

log "Installing basic utilities..."
$SUDO apt-get install -y \
  git curl wget unzip zip jq tree vim nano htop tmux \
  ca-certificates gnupg lsb-release software-properties-common \
  apt-transport-https python3 python3-pip python3-venv \
  || fail "Failed to install basic utilities."

# --- 2. AWS CLI v2 -----------------------------------------------------------
if command -v aws >/dev/null 2>&1 && aws --version 2>&1 | grep -q "aws-cli/2"; then
  log "AWS CLI v2 already installed: $(aws --version 2>&1)"
else
  log "Installing AWS CLI v2 (arch: $ARCH)..."
  case "$ARCH" in
    x86_64)  AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
    aarch64) AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
    *) fail "Unsupported architecture for AWS CLI install: $ARCH" ;;
  esac

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' RETURN
  curl -fsSL "$AWSCLI_URL" -o "$TMP_DIR/awscliv2.zip" || fail "Failed to download AWS CLI v2."
  unzip -q "$TMP_DIR/awscliv2.zip" -d "$TMP_DIR"
  if command -v aws >/dev/null 2>&1; then
    $SUDO "$TMP_DIR/aws/install" --update
  else
    $SUDO "$TMP_DIR/aws/install"
  fi
  rm -rf "$TMP_DIR"
  trap - RETURN
fi
aws --version || fail "aws --version failed after installation."

# --- 3. AWS Session Manager plugin -------------------------------------------
if command -v session-manager-plugin >/dev/null 2>&1; then
  log "Session Manager plugin already installed: $(session-manager-plugin --version 2>&1)"
else
  log "Installing AWS Session Manager plugin (arch: $ARCH)..."
  case "$ARCH" in
    x86_64)  SSM_PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" ;;
    aarch64) SSM_PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb" ;;
    *) fail "Unsupported architecture for Session Manager plugin install: $ARCH" ;;
  esac

  TMP_DEB="$(mktemp --suffix=.deb)"
  curl -fsSL "$SSM_PLUGIN_URL" -o "$TMP_DEB" || fail "Failed to download the Session Manager plugin."
  $SUDO dpkg -i "$TMP_DEB" || fail "Failed to install the Session Manager plugin package."
  rm -f "$TMP_DEB"
fi
session-manager-plugin --version || fail "session-manager-plugin --version failed after installation."

# --- 4. Ansible (dedicated venv, not the (often old) Ubuntu apt package) ----
if [[ ! -d "$VENV_DIR" ]]; then
  log "Creating Python virtual environment at $VENV_DIR..."
  $SUDO python3 -m venv "$VENV_DIR" || fail "Failed to create venv at $VENV_DIR."
fi

log "Upgrading pip and installing ansible-core, boto3, botocore into $VENV_DIR..."
$SUDO "$VENV_DIR/bin/pip" install --upgrade pip >/dev/null
$SUDO "$VENV_DIR/bin/pip" install --upgrade "ansible-core>=2.16" boto3 botocore \
  || fail "Failed to install ansible-core/boto3/botocore."

log "Making ansible commands available on PATH for all users..."
for bin in ansible ansible-playbook ansible-galaxy ansible-inventory ansible-doc ansible-config; do
  $SUDO ln -sf "$VENV_DIR/bin/$bin" "/usr/local/bin/$bin"
done

# Let the ubuntu user's own pip installs (if any) and the venv coexist cleanly.
if id ubuntu >/dev/null 2>&1; then
  $SUDO chown -R ubuntu:ubuntu "$VENV_DIR" 2>/dev/null || true
fi

ansible --version || fail "ansible --version failed after installation."
ansible-playbook --version || fail "ansible-playbook --version failed after installation."

# --- 5. Required Ansible collections ----------------------------------------
log "Installing Ansible collections from $ANSIBLE_DIR/requirements.yml..."
ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml" \
  || fail "Failed to install Ansible collections."
ansible-galaxy collection list | grep -q "amazon.aws" \
  || fail "amazon.aws collection not found after installation."

# --- 6. Verify AWS identity via the EC2 instance profile (no static keys) --
log "Verifying AWS identity via the EC2 instance profile..."
aws sts get-caller-identity || fail "aws sts get-caller-identity failed - check the EC2 instance profile."

log "Bootstrap complete. This host is ready to act as the Ansible controller."
log "Next: ./scripts/verify-ansible-controller.sh"
