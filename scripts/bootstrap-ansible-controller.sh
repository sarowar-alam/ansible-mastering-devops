#!/usr/bin/env bash
# Run this ON the public EC2 instance (dev-public-01), after `git clone`,
# from the repo root: bash scripts/bootstrap-ansible-controller.sh
#
# Turns the instance into an Ansible controller that manages all 3 EC2
# nodes purely over AWS Systems Manager Session Manager (amazon.aws.aws_ssm
# connection plugin) - no SSH keys, no inbound security-group rules needed.
# Idempotent: safe to re-run.
set -euo pipefail

echo "==> Updating apt cache and installing base packages"
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-venv git unzip curl

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) AWSCLI_ARCH="x86_64"; SSM_PLUGIN_ARCH="ubuntu_64bit" ;;
  aarch64) AWSCLI_ARCH="aarch64"; SSM_PLUGIN_ARCH="ubuntu_arm64" ;;
  *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

if ! command -v aws >/dev/null 2>&1; then
  echo "==> Installing AWS CLI v2"
  TMPDIR="$(mktemp -d)"
  curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWSCLI_ARCH}.zip" -o "${TMPDIR}/awscliv2.zip"
  unzip -q "${TMPDIR}/awscliv2.zip" -d "${TMPDIR}"
  sudo "${TMPDIR}/aws/install"
  rm -rf "${TMPDIR}"
else
  echo "==> AWS CLI already present: $(aws --version)"
fi

if [ ! -x /usr/local/bin/session-manager-plugin ]; then
  echo "==> Installing session-manager-plugin"
  TMPDIR="$(mktemp -d)"
  curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${SSM_PLUGIN_ARCH}/session-manager-plugin.deb" \
    -o "${TMPDIR}/session-manager-plugin.deb"
  sudo dpkg -i "${TMPDIR}/session-manager-plugin.deb"
  rm -rf "${TMPDIR}"
else
  echo "==> session-manager-plugin already present"
fi

echo "==> Installing pipx + Ansible for the current user"
python3 -m pip install --user --break-system-packages pipx 2>/dev/null \
  || python3 -m pip install --user pipx
python3 -m pipx ensurepath
export PATH="${HOME}/.local/bin:${PATH}"

if ! pipx list --short 2>/dev/null | grep -q '^ansible '; then
  pipx install --include-deps ansible
else
  echo "==> ansible already installed via pipx"
fi

echo "==> Injecting boto3/botocore into the ansible pipx venv"
pipx inject ansible boto3 botocore

echo "==> Installing required Ansible collections"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"${HOME}/.local/bin/ansible-galaxy" collection install -r "${REPO_ROOT}/ansible/requirements.yml"

cat <<'EOF'

==> Controller bootstrap complete. Re-login or `source ~/.profile` (or open
    a new shell) so PATH picks up ~/.local/bin, then:

    aws sts get-caller-identity
    cd ansible-mastering-devops/ansible
    ansible-inventory -i inventories/aws_ec2.yml --graph
    ansible all -i inventories/aws_ec2.yml -m ping
    ansible-playbook -i inventories/aws_ec2.yml playbooks/site.yml
EOF
