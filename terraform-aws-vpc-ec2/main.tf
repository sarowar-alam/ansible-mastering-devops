# Existing IAM instance profile lookup - we NEVER create/modify IAM.
# Failing fast here with a clear error if the profile doesn't exist, instead
# of a confusing EC2 API error at instance-creation time.
data "aws_iam_instance_profile" "ssm" {
  name = var.ssm_instance_profile_name
}

# --- Ubuntu 26.04 LTS AMI lookup (Canonical, account 099720109477) ---------
# Logic:
#   1. Only ever search AMIs owned by Canonical's official account.
#   2. The "name" filter pins the Ubuntu release to "26.04" specifically
#      (wildcards only match the codename and storage variant, e.g.
#      hvm-ssd / hvm-ssd-gp3) - this prevents accidentally matching 24.04,
#      25.10, or any other release.
#   3. The "architecture" filter makes the lookup architecture-aware and
#      driven by var.instance_architecture (default x86_64).
#   4. root-device-type/virtualization-type restrict results to modern
#      EBS-backed HVM images (required for current instance types).
#   5. most_recent = true picks the newest matching build (latest point
#      release / kernel patch of 26.04) at plan time.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/*/ubuntu-*-26.04-${local.ami_name_arch}-server-*"]
  }

  filter {
    name   = "architecture"
    values = [var.instance_architecture]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "vpc" {
  source = "./modules/vpc"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  tags                 = local.common_tags
}

module "security_group" {
  source = "./modules/security-group"

  name                     = "${local.name_prefix}-ec2-sg"
  vpc_id                   = module.vpc.vpc_id
  allowed_ssh_cidr         = var.allowed_ssh_cidr
  additional_ingress_ports = var.additional_ingress_ports
  tags                     = local.common_tags
}

module "ec2" {
  source   = "./modules/ec2"
  for_each = local.instances

  name                 = each.key
  ami_id               = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  subnet_id            = each.value.subnet_id
  security_group_ids   = [module.security_group.security_group_id]
  iam_instance_profile = data.aws_iam_instance_profile.ssm.name
  create_eip           = each.value.create_eip
  root_volume_size     = var.root_volume_size
  root_volume_type     = var.root_volume_type

  tags = merge(local.common_tags, {
    Role = each.value.role
  })

  depends_on = [module.vpc]
}
