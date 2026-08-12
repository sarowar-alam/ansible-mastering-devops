# This "dev" environment is a thin wrapper around the root module
# (the repository root, one level up). It exists so that additional
# environments (staging/prod) can be added later as sibling directories,
# each with their own state/backend and tfvars, without duplicating any
# resource logic - all actual resources live in the root module and its
# child modules (../../modules/vpc, ../../modules/security-group,
# ../../modules/ec2).
#
# The AWS provider is configured inside the root module (../../providers.tf)
# and is inherited here since this environment calls it exactly once
# (no for_each/count on the module block).
module "dev" {
  source = "../../"

  aws_region  = var.aws_region
  aws_profile = var.aws_profile

  environment  = var.environment
  project_name = var.project_name

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidrs = var.private_subnet_cidrs

  instance_type         = var.instance_type
  instance_architecture = var.instance_architecture

  root_volume_size = var.root_volume_size
  root_volume_type = var.root_volume_type

  ssm_instance_profile_name = var.ssm_instance_profile_name
  allowed_ssh_cidr          = var.allowed_ssh_cidr
  additional_ingress_ports  = var.additional_ingress_ports

  common_tags = var.common_tags
}
