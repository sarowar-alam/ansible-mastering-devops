# ansible-mastering-devops

Infrastructure (Terraform) + configuration management (Ansible) for a small
AWS lab: a VPC with one public and two private EC2 instances, where the
public instance acts as an **Ansible controller** that manages the private
instances entirely through **AWS Systems Manager (SSM)** - no SSH keys.

> ## ⚠ ACTION REQUIRED before Ansible SSM playbooks will work
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
Public EC2 (dev-public-01) -- Elastic IP
   |
   v
Ansible Controller (Git, AWS CLI, Session Manager plugin, Python, Ansible, amazon.aws)
   |
   v
AWS Systems Manager (Session Manager + S3 file transfer)
   |
   v
Private EC2s (dev-private-01, dev-private-02) -- no public IP, SSM managed
```

```
                         Internet
                            |
                     Elastic IP
                            |
                            v
                 +--------------------+
                 |   dev-public-01    |
                 | Ansible Controller |
                 | AWS CLI / Ansible  |
                 | boto3 / SSM plugin |
                 +---------+----------+
                           |
                           | AWS SSM (Session Manager + S3)
                           |
                 +---------+----------+
                 |                    |
                 v                    v
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
│   ├── inventories/aws_ec2.yml   # dynamic AWS EC2 inventory (tag-based)
│   ├── group_vars/{all,private_servers}.yml
│   ├── playbooks/{test-ssm,patch,utilities,docker,site}.yml
│   └── roles/{common,patch,docker}/
├── scripts/
│   ├── bootstrap-ansible-controller.sh
│   ├── verify-ansible-controller.sh
│   └── run-ansible.sh
├── README.md
└── .gitignore
```

## Prerequisites

- The Terraform infrastructure in `terraform-aws-vpc-ec2/` already applied
  (VPC, 3 EC2 instances, `SSM` instance profile attached).
- AWS CLI v2 + the Session Manager plugin on your **workstation**, to reach
  `dev-public-01` initially over SSM (the same tools the bootstrap script
  installs *on* the controller).
- The S3 bucket + IAM permissions described in the box above, before running
  any playbook that actually connects over `amazon.aws.aws_ssm`.

## Initial setup

```powershell
git clone https://github.com/sarowar-alam/ansible-mastering-devops.git
cd ansible-mastering-devops

cd terraform-aws-vpc-ec2
terraform init
terraform plan
terraform apply   # review the plan first - not run automatically by this repo
```

Get the public instance ID and connect to it over SSM (no SSH key needed):

```powershell
terraform output public_instance_id
aws ssm start-session --target <instance-id> --profile sarowar-ostad --region us-west-2
```

## Bootstrapping the Ansible controller

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

## Full workflow

```
Terraform creates infrastructure
        |
EC2 public server starts
        |
Connect to public EC2 using SSM
        |
Install Git, clone this repo
        |
Run scripts/bootstrap-ansible-controller.sh
        |
(installs AWS CLI, Session Manager plugin, Ansible, amazon.aws collection)
        |
scripts/verify-ansible-controller.sh
        |
scripts/run-ansible.sh test        # dynamic inventory + SSM connectivity
        |
scripts/run-ansible.sh utilities
scripts/run-ansible.sh patch
scripts/run-ansible.sh docker
        |
scripts/run-ansible.sh site
```

## Running playbooks

```bash
cd ansible-mastering-devops
./scripts/run-ansible.sh test        # must succeed before anything else
./scripts/run-ansible.sh utilities
./scripts/run-ansible.sh patch
./scripts/run-ansible.sh docker
./scripts/run-ansible.sh site
```

Or drive Ansible directly from `ansible/`:

```bash
cd ansible
ansible-inventory -i inventories/aws_ec2.yml --graph
ansible-playbook -i inventories/aws_ec2.yml playbooks/test-ssm.yml
ansible-playbook -i inventories/aws_ec2.yml playbooks/site.yml --tags docker
ansible-playbook -i inventories/aws_ec2.yml playbooks/patch.yml -e reboot_if_required=true
```

## How Ansible connects to the private servers

- **Dynamic inventory** (`ansible/inventories/aws_ec2.yml`, `amazon.aws.aws_ec2`
  plugin) discovers running instances tagged
  `Project=terraform-aws-infrastructure`, `Environment=dev` and groups them
  by the Terraform `Role` tag: `Role=private` → group `private_servers`,
  `Role=public` → group `controller`. Hostnames come from the `Name` tag
  (`dev-private-01`, `dev-private-02`), never from IPs.
- **Connection**: `ansible_connection: amazon.aws.aws_ssm` (set in
  `ansible/group_vars/private_servers.yml`), which uses
  `ansible_aws_ssm_instance_id` (composed per-host by the inventory plugin
  from the real EC2 instance ID - an IP address is not sufficient for this
  plugin) plus `ansible_aws_ssm_region` and `ansible_aws_ssm_bucket_name`.
- **`private_servers` never includes `dev-public-01`** - the controller
  itself is placed in a separate `controller` group and is not a target of
  `patch.yml`/`utilities.yml`/`docker.yml`/`site.yml`.
- No SSH keys, no inbound security group rule, no public IPs on the private
  instances are required at any point.

## Required IAM permissions for Ansible SSM

The `amazon.aws.aws_ssm` connection plugin needs two things the `SSM` role
doesn't currently have: S3 access for module transfer, and SSM control-plane
permissions to manage other instances (confirmed missing via live testing -
`AmazonSSMManagedInstanceCore` alone only lets an instance be managed, not
manage others). Attach a policy like this, scoped to your chosen bucket
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
the ACTION REQUIRED box at the top. Set the bucket name in
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

Only additive, non-breaking output changes (no resources added/changed/
removed - confirmed with `terraform plan`):

- Added `private_instance_names` output (Name tag of each private instance,
  in the same order as `private_instance_ids`/`private_instance_private_ips`),
  in both the root module and `environments/dev`.

Nothing else in `terraform-aws-vpc-ec2/` was modified. See
[terraform-aws-vpc-ec2/README.md](terraform-aws-vpc-ec2/README.md) for full
Terraform documentation.
