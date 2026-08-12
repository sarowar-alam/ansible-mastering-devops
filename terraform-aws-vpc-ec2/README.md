# terraform-aws-vpc-ec2

Production-quality, modular Terraform codebase that provisions a VPC with a
public subnet and two private subnets (across two AZs), NAT/Internet
Gateways, a least-privilege security group, and three Ubuntu 26.04 LTS EC2
instances managed via AWS Systems Manager (SSM).

## 1. Architecture

```
                         Internet
                            │
                            ▼
                    ┌───────────────┐
                    │ Internet GW   │
                    └───────┬───────┘
                            │
                    Public Subnet
                            │
              ┌─────────────┴─────────────┐
              │                           │
       NAT Gateway                  Public EC2
       (+ its own EIP)               Ubuntu 26.04
              │                       Elastic IP
              │
              ▼
       Private Route Table
              │
       ┌──────┴───────┐
       │              │
 Private Subnet AZ-1  Private Subnet AZ-2
       │              │
       ▼              ▼
 Private EC2 #1    Private EC2 #2
 Ubuntu 26.04      Ubuntu 26.04
 No Public IP      No Public IP
       │              │
       └──────┬───────┘
              │
         AWS SSM Access (outbound via NAT)
```

All three EC2 instances share one security group and use the same
**existing** IAM instance profile (SSM only - no IAM is created here).

## 2. Prerequisites

- Terraform >= 1.7 (tested with 1.15.x)
- AWS CLI v2, configured with a named profile that has permissions to create
  VPC/EC2/NAT/EIP resources and to read the existing IAM instance profile
- An **existing** IAM instance profile (with a role that has
  `AmazonSSMManagedInstanceCore` attached) - this repo never creates or
  modifies IAM

## 3. AWS CLI profile configuration

This repo is wired to use the named profile `sarowar-ostad` and region
`us-west-2` by default (both are configurable variables). Verify the profile
works before running Terraform:

```powershell
aws sts get-caller-identity --profile sarowar-ostad
```

## 4. Terraform installation

Install Terraform >= 1.7 from https://developer.hashicorp.com/terraform/install,
or via a package manager (`choco install terraform`, `brew install terraform`, etc.).

## 5. Repository structure

```
terraform-aws-vpc-ec2/
├── README.md
├── .gitignore
├── versions.tf                 # Terraform + provider version constraints
├── providers.tf                # aws provider (region/profile from variables)
├── variables.tf                # All input variables + validation
├── locals.tf                   # Naming, tagging, AMI arch map, instance map
├── main.tf                     # AMI/IAM data sources + module composition
├── outputs.tf
├── terraform.tfvars.example    # Copy to terraform.tfvars to customize
│
├── modules/
│   ├── vpc/                    # VPC, subnets, IGW, NAT, route tables
│   ├── security-group/         # Shared least-privilege SG
│   └── ec2/                    # Single hardened EC2 instance (+ optional EIP)
│
└── environments/
    └── dev/                    # Thin wrapper calling the root module,
                                 # demonstrating how staging/prod would be
                                 # added later without duplicating logic
```

The **root directory** (this one) is the primary, directly-runnable
configuration. `environments/dev` calls it as a module (`source = "../../"`)
purely to demonstrate the pattern for adding more environments later; running
Terraform from either location produces the same infrastructure. Don't run
`apply` from both against the same AWS account/region without a distinct
backend/state per directory, or you'll create duplicate resources.

## 6. Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-west-2` | AWS region |
| `aws_profile` | `sarowar-ostad` | Named AWS CLI profile |
| `environment` | `dev` | Environment name (naming/tagging) |
| `project_name` | `terraform-aws-infrastructure` | Project name (naming/tagging) |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR |
| `public_subnet_cidr` | `10.0.1.0/24` | Public subnet CIDR |
| `private_subnet_cidrs` | `["10.0.11.0/24","10.0.12.0/24"]` | Private subnet CIDRs (AZ-1, AZ-2) |
| `instance_type` | `t3.micro` | Instance type for all 3 EC2s |
| `instance_architecture` | `x86_64` | `x86_64` or `arm64`, drives AMI lookup |
| `root_volume_size` | `20` | Root EBS size (GiB) |
| `root_volume_type` | `gp3` | Root EBS volume type |
| `ssm_instance_profile_name` | `SSM` | **Existing** IAM instance profile name |
| `allowed_ssh_cidr` | `""` (disabled) | CIDR allowed to SSH; empty = no SSH rule |
| `additional_ingress_ports` | `[]` | Extra inbound app ports |
| `common_tags` | see `variables.tf` | Base tags merged onto every resource |

Full descriptions/validation rules are in [variables.tf](variables.tf).

## 7. Initialize Terraform

```powershell
cd terraform-aws-vpc-ec2
cp terraform.tfvars.example terraform.tfvars   # then edit as needed
terraform init
```

## 8. Validate

```powershell
terraform fmt -recursive
terraform validate
```

## 9. Plan

```powershell
terraform plan -var-file="terraform.tfvars"
```

(If you didn't create `terraform.tfvars`, `terraform plan` still works using
the built-in defaults, which already match `sarowar-ostad` / `us-west-2`.)

## 10. Apply

Review the plan output carefully first. Then:

```powershell
terraform apply -var-file="terraform.tfvars"
```

## 11. Destroy

```powershell
terraform destroy -var-file="terraform.tfvars"
```

This tears down every resource this configuration created. It does **not**
touch the existing IAM instance profile/role - that was never created by
Terraform.

## 12. How SSM access works

All 3 instances use the existing IAM instance profile (`ssm_instance_profile_name`,
default `SSM`), whose role has `AmazonSSMManagedInstanceCore` attached. The
SSM Agent (preinstalled on Canonical's Ubuntu AMIs) calls out to the SSM
service endpoints over HTTPS (443):

- The **public** instance reaches SSM via the Internet Gateway.
- The **private** instances reach SSM via the NAT Gateway.

No inbound security group rule is required for SSM - only outbound
(egress `0.0.0.0/0`, already configured).

## 13. Network architecture

- 1 VPC (`vpc_cidr`, default `10.0.0.0/16`), DNS support + DNS hostnames enabled.
- 1 public subnet, 1 route table with a `0.0.0.0/0 → Internet Gateway` route.
- 2 private subnets (one per AZ, AZs picked dynamically via
  `aws_availability_zones` - never hard-coded), sharing 1 route table with a
  `0.0.0.0/0 → NAT Gateway` route.
- 1 Internet Gateway attached to the VPC.
- 1 NAT Gateway (in the public subnet) with its own Elastic IP.

## 14. Security considerations

- **IMDSv2 required** on every instance (`http_tokens = "required"`, hop
  limit `1`) - blocks SSRF-based instance-credential theft.
- **Encrypted root EBS volumes** on every instance.
- **No SSH by default.** `allowed_ssh_cidr` defaults to `""`, so no inbound
  SSH rule exists at all; SSM Session Manager is the management path.
  If you do set `allowed_ssh_cidr`, scope it to your own IP (`/32`), never
  `0.0.0.0/0`.
- **Least-privilege security group.** Only egress is open by default;
  inbound is opt-in and scoped.
- **No IAM created/modified.** The instance profile must already exist;
  Terraform fails fast (clear error) at plan time if it doesn't, rather than
  silently creating one.
- **Private instances have no public IP** at all - not even an ephemeral
  one (`map_public_ip_on_launch = false` on both private subnets).
- No credentials are hard-coded anywhere; authentication is entirely via the
  named AWS CLI profile (`aws_profile`).

## 15. NAT Gateway cost considerations

This design uses a **single** NAT Gateway (hourly charge + per-GB data
processing charge) shared by both private subnets, to keep costs reasonable
for a dev/learning environment.

For production-grade high availability, deploy **one NAT Gateway per AZ**
(each with its own EIP, in a public subnet in that AZ), and give each private
subnet a route table pointing at the NAT Gateway in its own AZ. This avoids
cross-AZ data transfer charges and removes the single NAT Gateway as a
single point of failure. See [modules/vpc/README.md](modules/vpc/README.md).

Additionally, **VPC Interface Endpoints** for SSM (`com.amazonaws.<region>.ssm`,
`ssmmessages`, `ec2messages`) could be added later to remove the NAT Gateway
dependency for SSM traffic specifically (reducing NAT data-processing costs
if SSM traffic volume is high). This is not implemented here to keep the
initial design simple, per the task requirements.

## 16. Why private instances don't have public IPs

Private EC2 instances (`dev-private-01`, `dev-private-02`) are launched into
subnets with `map_public_ip_on_launch = false`, and the EC2 module never sets
`associate_public_ip_address`. This means they have no route reachable from
the public internet at all - all outbound traffic goes through the NAT
Gateway (source-NAT'd to the NAT Gateway's EIP), and all management is via
SSM. This is the standard "private subnet" security posture: reduced attack
surface, no direct inbound exposure.

## 17. How to connect to the instances using SSM

Ensure the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
for the AWS CLI is installed, then:

```powershell
# List managed instances (should show all 3 once SSM Agent has checked in)
aws ssm describe-instance-information --profile sarowar-ostad --region us-west-2

# Start an interactive shell session
aws ssm start-session --target <instance-id> --profile sarowar-ostad --region us-west-2
```

Get instance IDs from the Terraform outputs:

```powershell
terraform output public_instance_id
terraform output private_instance_ids
```

It can take a minute or two after instance launch for the SSM Agent to
register with the service.

## 18. How to change instance types

Set `instance_type` in `terraform.tfvars` (applies to all 3 instances):

```hcl
instance_type = "t3.small"
```

## 19. How to change CIDRs

Edit `vpc_cidr`, `public_subnet_cidr`, and `private_subnet_cidrs` in
`terraform.tfvars`. `private_subnet_cidrs` must contain exactly 2 entries
(validated). Example:

```hcl
vpc_cidr             = "10.20.0.0/16"
public_subnet_cidr   = "10.20.1.0/24"
private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]
```

## 20. How to replace the existing SSM instance profile

Set `ssm_instance_profile_name` to the name of a different, already-existing
IAM instance profile:

```hcl
ssm_instance_profile_name = "my-other-ssm-profile"
```

The profile's role must have `AmazonSSMManagedInstanceCore` (or equivalent
permissions) attached. Terraform reads it via a data source
(`data.aws_iam_instance_profile.ssm` in [main.tf](main.tf)) and will fail
with a clear "no matching IAM instance profile" error at `plan` time if the
name doesn't exist - it will never create or modify one for you.

## AMI selection logic (Ubuntu 26.04 LTS)

See the documented `data "aws_ami" "ubuntu"` block in [main.tf](main.tf).
Summary:

1. Restricted to Canonical's official owner ID (`099720109477`).
2. The `name` filter pins the release to `26.04` explicitly
   (`ubuntu-*-26.04-<arch>-server-*`), so a `24.04`/`25.10`/etc. image can
   never be selected by accident.
3. `architecture` filter is driven by `instance_architecture`
   (`x86_64` → AMI name arch `amd64`; `arm64` → `arm64`), so switching
   architecture doesn't require touching the filter logic.
4. Restricted to EBS-backed, HVM images, and `most_recent = true` picks the
   newest matching build.

## Assumptions / notes

- The existing IAM instance profile `SSM` (role `SSM`) was found in the
  target AWS account and has `AmazonSSMManagedInstanceCore` attached; it is
  used as the default for `ssm_instance_profile_name`.
- No SSH key pair is configured on any instance (SSM is the management
  path). If you set `allowed_ssh_cidr` to enable SSH, you'll also need to
  add a `key_name` to the instances yourself (not included, since SSH is
  intentionally not the primary access method here).
- A single NAT Gateway is used by design (see cost considerations above).
