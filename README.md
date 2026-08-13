# ansible-mastering-devops

Infrastructure (Terraform) + configuration management (Ansible) for a small
AWS lab: a VPC with one public and two private EC2 instances, configured
entirely through **AWS Systems Manager (SSM)** - no SSH keys, no bastion.

> ## How playbooks run (read this first)
> `patch.yml`, `utilities.yml`, `docker.yml`, and `site.yml` run via **AWS
> Systems Manager Run Command** (the AWS-owned `AWS-ApplyAnsiblePlaybooks`
> document, triggered by `scripts/run-ansible.sh`). This pulls this repo's
> `ansible/` folder straight from GitHub onto each private instance and runs
> `ansible-playbook -i "localhost," -c local` **locally, as root**.
>
> **Why not the `amazon.aws.aws_ssm` connection plugin (controller ->
> targets)?** It cannot do `become`/sudo at all - this is an open, unfixed
> upstream bug ([amazon.aws#2640](https://github.com/ansible-collections/amazon.aws/issues/2640)).
> Session Manager's "Run As" feature can't substitute for it either - the
> SSM Agent hard-rejects `runAsDefaultUser: root` ("invalid uid and gid").
> Run Command sidesteps the problem entirely instead of working around it:
> there's no connection plugin and no `become` in the loop, so it's
> unaffected by that bug.
>
> **Where to run `scripts/run-ansible.sh` from:** anywhere with the
> `sarowar-ostad` AWS CLI profile configured (your laptop, CI, or the
> `dev-public-01` controller) - it's a plain `ssm:SendCommand` API call, not
> a VPC-internal connection. The `dev-public-01` "controller" and the
> `amazon.aws.aws_ssm` connection plugin still exist, but only for the
> optional read-only smoke test (`scripts/run-ansible.sh test` /
> `playbooks/test-ssm.yml`) - see [Legacy: connection-plugin path](#legacy-connection-plugin-path-optional)
> below.

> ## ⚠ Optional: IAM required for the legacy connection-plugin smoke test
> The existing `SSM` IAM role/instance profile (used by all 3 EC2 instances)
> was inspected and **does not have the S3 permissions required by the
> `amazon.aws.aws_ssm` connection plugin**. Its only S3 access is a
> narrowly-scoped inline policy (`terraform-iam-policy`) limited to the
> `terraform-state-bmi-ostaddevops` bucket, which is unrelated Terraform
> state for other projects and must not be reused for Ansible file transfer.
>
> **Also confirmed via live testing:** the `SSM` role only lets an instance
> *be managed* (via `AmazonSSMManagedInstanceCore`) - it needs additional
> `ssm:DescribeInstanceInformation`, `ssm:StartSession`, `ssm:TerminateSession`,
> `ssm:ResumeSession`, `ssm:DescribeSessions`, `ssm:GetConnectionStatus`
> permissions for the controller to manage the private instances. Without
> these, `scripts/verify-ansible-controller.sh` fails with `AccessDeniedException`.
>
> **Nothing was modified.** This repo never creates/edits IAM. To unblock
> `amazon.aws.aws_ssm`, you (or whoever owns IAM) need to:
> 1. Create (or choose) a dedicated S3 bucket for Ansible SSM file transfer,
>    e.g. `my-org-ansible-ssm-transfer`.
> 2. Attach a policy to the `SSM` role granting it both the S3 access and
>    the SSM control-plane actions above - see
>    [Required IAM permissions](#required-iam-permissions-for-ansible-ssm) below.
> 3. Set that bucket name in `ansible/group_vars/private_servers.yml`
>    (`ansible_aws_ssm_bucket_name`), replacing the `CHANGE-ME-...` placeholder.

## Architecture

```
Terraform
   |
   v
AWS Infrastructure (VPC, subnets, IGW, NAT, EC2, SSM instance profile)
   |
   v
Anywhere with AWS CLI (laptop, CI, or dev-public-01) -- aws ssm send-command
   |
   v
AWS Systems Manager Run Command (AWS-ApplyAnsiblePlaybooks)
   |
   v
Private EC2s (dev-private-01, dev-private-02) -- pulls ansible/ from GitHub,
runs `ansible-playbook -i "localhost," -c local` locally, as root
```

```
        Your laptop / CI / dev-public-01
        (aws ssm send-command, any of these)
                     |
                     | AWS API (ssm:SendCommand)
                     v
        +--------------------------------+
        |     AWS Systems Manager        |
        |   AWS-ApplyAnsiblePlaybooks    |
        +----------------+---------------+
                          |
                 downloads ansible/ from
                 GitHub, runs locally as root
                          |
                 +--------+---------+
                 |                  |
                 v                  v
        +----------------+   +----------------+
        | dev-private-01 |   | dev-private-02 |
        | Ubuntu 26.04   |   | Ubuntu 26.04   |
        | Private subnet |   | Private subnet |
        | SSM managed    |   | SSM managed    |
        +----------------+   +----------------+
```

Terraform owns infrastructure (VPC/subnets/routing/NAT/EC2/security
group/IAM instance profile attachment). Ansible owns operating-system
configuration (packages, patching, Docker, utilities) on top of it. The two
are not mixed.

## Repository structure

```
ansible-mastering-devops/
├── terraform-aws-vpc-ec2/    # AWS infrastructure (see its own README.md)
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml
│   ├── inventories/aws_ec2.yml   # dynamic AWS EC2 inventory (legacy path only)
│   ├── group_vars/{all,private_servers}.yml
│   ├── playbooks/{test-ssm,patch,utilities,docker,site}.yml   # hosts: all - run locally as root via Run Command
│   └── roles/{common,patch,docker}/
├── scripts/
│   ├── bootstrap-ansible-controller.sh   # legacy, optional
│   ├── verify-ansible-controller.sh      # legacy, optional
│   └── run-ansible.sh                    # primary: triggers SSM Run Command
├── README.md
└── .gitignore
```

## Prerequisites

- The Terraform infrastructure in `terraform-aws-vpc-ec2/` already applied
  (VPC, 3 EC2 instances, `SSM` instance profile attached).
- AWS CLI v2 configured with the `sarowar-ostad` profile wherever you'll run
  `scripts/run-ansible.sh` (your workstation, CI, or `dev-public-01`) - it
  only needs `ssm:SendCommand`, `ssm:GetCommandInvocation`,
  `ssm:ListCommandInvocations`, `ec2:DescribeInstances`.
- The private instances need outbound internet access (already provided by
  the NAT Gateway) to fetch this repo from GitHub and `pip install ansible`.

## Initial setup

```powershell
git clone https://github.com/sarowar-alam/ansible-mastering-devops.git
cd ansible-mastering-devops

cd terraform-aws-vpc-ec2
terraform init
terraform plan
terraform apply   # review the plan first - not run automatically by this repo
```

## Full workflow

```
Terraform creates infrastructure
        |
Private EC2s come up, SSM-managed, outbound internet via NAT
        |
scripts/run-ansible.sh test        # Run Command smoke test
        |
scripts/run-ansible.sh utilities
scripts/run-ansible.sh patch
scripts/run-ansible.sh docker
        |
scripts/run-ansible.sh site
```

Each step: `scripts/run-ansible.sh <action>` calls `aws ssm send-command`
with the `AWS-ApplyAnsiblePlaybooks` document, targeting the private
instances by tag. That document downloads `ansible/` from this repo's
`main` branch straight onto each target and runs
`ansible-playbook -i "localhost," -c local playbooks/<action>.yml` **as
root** (Run Command always runs as root on Linux) - no SSH, no connection
plugin, no `become`.

## Running playbooks

```bash
cd ansible-mastering-devops
./scripts/run-ansible.sh test        # smoke test
./scripts/run-ansible.sh utilities
./scripts/run-ansible.sh patch
./scripts/run-ansible.sh patch reboot_if_required=true   # extra vars: key=value ...
./scripts/run-ansible.sh docker
./scripts/run-ansible.sh site
```

This can be run from your workstation, CI, or `dev-public-01` - anywhere
with the `sarowar-ostad` AWS CLI profile. Output (stdout/stderr per
instance) is printed after each run completes; `aws ssm list-commands` /
the Systems Manager console (Run Command history) also show full history.

## Legacy: connection-plugin path (optional)

This repo originally drove Ansible from a dedicated controller EC2
(`dev-public-01`) using the `amazon.aws.aws_ssm` **connection plugin**
(controller -> target, over an interactive SSM session). That path is kept
only for the read-only `test-ssm.yml` smoke test - it **cannot** run
`patch.yml`/`utilities.yml`/`docker.yml`/`site.yml` because the plugin does
not support `become`/sudo at all (see the box at the top). If you want to
use it anyway:

Get the public instance ID and connect to it over SSM (no SSH key needed):

```powershell
terraform output public_instance_id
aws ssm start-session --target <instance-id> --profile sarowar-ostad --region ap-south-1
```

Once connected to `dev-public-01` via SSM Session Manager:

```bash
# Git isn't preinstalled on the base Ubuntu image - install it first
sudo apt-get update && sudo apt-get install -y git

git clone https://github.com/sarowar-alam/ansible-mastering-devops.git
cd ansible-mastering-devops

./scripts/bootstrap-ansible-controller.sh   # idempotent - safe to re-run
./scripts/verify-ansible-controller.sh
```

`bootstrap-ansible-controller.sh` installs: basic utilities, AWS CLI v2,
the Session Manager plugin, Ansible (`ansible-core` in `/opt/ansible-venv`,
symlinked onto `PATH`), and the `amazon.aws` collection - all using the EC2
IAM instance profile for AWS auth (no static keys are ever written).

Drive Ansible directly from `ansible/` (connection-plugin path):

```bash
cd ansible
ansible-inventory -i inventories/aws_ec2.yml --graph
ansible-playbook -i inventories/aws_ec2.yml playbooks/test-ssm.yml
ansible-playbook -i inventories/aws_ec2.yml playbooks/site.yml --tags docker
ansible-playbook -i inventories/aws_ec2.yml playbooks/patch.yml -e reboot_if_required=true
```

## Troubleshooting

- **`[ERROR]: Could not load 'yaml' callback plugin.`** - `ansible.cfg`'s
  `stdout_callback` was originally set to `yaml`, which requires the
  `community.general` collection (not a dependency of this repo). Already
  fixed in `ansible/ansible.cfg` (`stdout_callback = ansible.builtin.default`).
  If you still see this, `git pull` to get the latest `ansible.cfg`.
- **`AccessDeniedException` on `ssm:DescribeInstanceInformation` /
  `ssm:StartSession`** - the `SSM` role is missing the SSM control-plane
  permissions. See [Required IAM permissions](#required-iam-permissions-for-ansible-ssm).
- **`Failed to get bucket region: ... (404) ... HeadBucket ... Not Found`**
  when running the legacy `test-ssm.yml` over the connection plugin -
  `ansible_aws_ssm_bucket_name` in `ansible/group_vars/private_servers.yml`
  is still the `CHANGE-ME-...` placeholder, or the bucket doesn't
  exist/isn't permitted yet. See the IAM box at the top.
- **Run Command invocation status `TimedOut`** - the target is likely still
  running `pip3 install ansible --upgrade` (`InstallDependencies: True`
  in `scripts/run-ansible.sh`); this can take a while on a `t3.micro`. Check
  `aws ssm get-command-invocation` output, or increase `TimeoutSeconds` in
  the `--parameters` payload built by the script.
- **`invalid uid and gid`** - this is the SSM Agent hard-rejecting a Session
  Manager "Run As" document with `runAsDefaultUser: root` (UID 0). This
  repo doesn't use that approach for exactly this reason (see the box at
  the top) - if you see this, something is still referencing the old,
  abandoned `ansible_aws_ssm_document` setting.
- **A config/script edit made with `sed`/manual patching on the controller
  doesn't seem to apply** - check for CRLF line endings
  (`cat -A file | head`, look for `^M` at line ends). This repo enforces LF
  via `.gitattributes`; if you're on an older clone made before that was
  added, `git pull` and re-clone/`git checkout -- .` to get clean LF files.

## How Ansible reaches the private servers

- **Primary path (patch/utilities/docker/site):** `scripts/run-ansible.sh`
  resolves the running `dev-private-*` instance IDs via `aws ec2
  describe-instances` (tags `Project`/`Environment`/`Role=private`), then
  calls `aws ssm send-command` with the `AWS-ApplyAnsiblePlaybooks`
  document. That document downloads `ansible/` from this repo's `main`
  branch onto each target and runs the requested playbook **locally, as
  root**, via `ansible-playbook -i "localhost," -c local`. No connection
  plugin, no `become`, no SSH keys, no inbound rules, no public IPs.
- **Legacy path (`test-ssm.yml` only):** `ansible/inventories/aws_ec2.yml`
  (`amazon.aws.aws_ec2` dynamic inventory) discovers instances tagged
  `Project=terraform-aws-infrastructure`, `Environment=dev` and groups them
  by the Terraform `Role` tag: `Role=private` → group `private_servers`,
  `Role=public` → group `controller`. Connection is
  `ansible_connection: amazon.aws.aws_ssm` (set in
  `ansible/group_vars/private_servers.yml`), using
  `ansible_aws_ssm_instance_id` (composed per-host by the inventory plugin)
  plus `ansible_aws_ssm_region` and `ansible_aws_ssm_bucket_name`. This path
  cannot run `become` (see the box at the top) so it's only used for the
  read-only smoke test, run from `dev-public-01`.

## Required IAM permissions

**For the primary Run Command path**, whoever runs `scripts/run-ansible.sh`
(your own IAM identity/profile, e.g. `sarowar-ostad`) needs:
`ssm:SendCommand`, `ssm:GetCommandInvocation`, `ssm:ListCommandInvocations`,
`ssm:ListCommands`, `ec2:DescribeInstances`. No new instance-role
permissions are required - `AWS-ApplyAnsiblePlaybooks` only needs outbound
internet (already provided by the NAT Gateway) to reach GitHub and PyPI.

**For the legacy connection-plugin path** (`test-ssm.yml` only), the
`amazon.aws.aws_ssm` connection plugin needs two things the `SSM` instance
role doesn't have by default: S3 access for module transfer, and SSM
control-plane permissions to manage other instances
(`AmazonSSMManagedInstanceCore` alone only lets an instance *be managed*,
not manage others). Attach a policy like this, scoped to your chosen bucket
(replace `YOUR-BUCKET`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR-BUCKET",
        "arn:aws:s3:::YOUR-BUCKET/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeInstanceInformation",
        "ssm:StartSession",
        "ssm:TerminateSession",
        "ssm:ResumeSession",
        "ssm:DescribeSessions",
        "ssm:GetConnectionStatus"
      ],
      "Resource": "*"
    }
  ]
}
```

This repository does **not** create the bucket or attach this policy - see
the IAM box at the top. Set the bucket name in
`ansible/group_vars/private_servers.yml` (`ansible_aws_ssm_bucket_name`)
once it exists and is permitted.

## Security considerations

- No SSH keys anywhere; all management is via SSM Session Manager.
- No inbound `0.0.0.0/0` SSH rule (unchanged from the existing Terraform
  security group - not modified by this work).
- Private instances have no public IP (unchanged).
- The controller authenticates to AWS purely via its EC2 instance profile;
  no `~/.aws/credentials` with static keys is ever created.
- `roles/docker` can add the `ubuntu` user to the `docker` group
  (`docker_add_ubuntu_user_to_group: true` by default) so `docker` can be
  run without `sudo`. This is effectively root-equivalent access (the
  Docker daemon runs as root and the socket is unauthenticated for group
  members) - set the variable to `false` if that's not acceptable for your
  environment.
- `patch.yml` never reboots automatically (`reboot_if_required: false` by
  default) - pass `-e reboot_if_required=true` to opt in.

## Changes made to the existing Terraform

Additive changes only (nothing existing changed/removed - confirmed with
`terraform plan`):

- Added `private_instance_names` output (Name tag of each private instance,
  in the same order as `private_instance_ids`/`private_instance_private_ips`),
  in both the root module and `environments/dev`.

**Abandoned attempt (reverted, for context):** an `aws_ssm_document`
resource with Session Manager's "Run As" (`runAsDefaultUser = "root"`) was
briefly added to try to make the `amazon.aws.aws_ssm` connection plugin work
without `become`. It was reverted after live testing showed the SSM Agent
hard-rejects `runAsDefaultUser: root` (`invalid uid and gid` - Run As only
supports non-root OS users). The Run Command approach used instead needs no
Terraform changes at all - `AWS-ApplyAnsiblePlaybooks` is an AWS-owned
document and command execution already runs as root by default.

Nothing else in `terraform-aws-vpc-ec2/` was modified. See
[terraform-aws-vpc-ec2/README.md](terraform-aws-vpc-ec2/README.md) for full
Terraform documentation.
