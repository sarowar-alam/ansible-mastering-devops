locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    var.common_tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  )

  # Canonical's Ubuntu AMI names encode architecture as "amd64"/"arm64", while
  # the EC2 "architecture" attribute/filter uses "x86_64"/"arm64". Map between
  # the two so instance_architecture stays a natural Terraform/AWS value.
  ami_architecture_map = {
    x86_64 = "amd64"
    arm64  = "arm64"
  }
  ami_name_arch = lookup(local.ami_architecture_map, var.instance_architecture, "amd64")

  public_instance_key = "${var.environment}-public-01"

  # Single source of truth for the 3 required EC2 instances and where they live.
  instances = {
    "${var.environment}-public-01" = {
      subnet_id  = module.vpc.public_subnet_id
      create_eip = true
      role       = "public"
    }
    "${var.environment}-private-01" = {
      subnet_id  = module.vpc.private_subnet_ids[0]
      create_eip = false
      role       = "private"
    }
    "${var.environment}-private-02" = {
      subnet_id  = module.vpc.private_subnet_ids[1]
      create_eip = false
      role       = "private"
    }
  }
}
