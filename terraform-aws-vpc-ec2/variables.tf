variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile used for authentication. Must already exist in ~/.aws/credentials or ~/.aws/config."
  type        = string
  default     = "sarowar-ostad"
}

variable "environment" {
  description = "Environment name, used for naming/tagging (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name, used for naming/tagging resources."
  type        = string
  default     = "terraform-aws-infrastructure"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (one per AZ: AZ-1, AZ-2)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2 && alltrue([for c in var.private_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "private_subnet_cidrs must contain exactly 2 valid IPv4 CIDR blocks (one per AZ)."
  }
}

variable "instance_type" {
  description = "EC2 instance type used for all 3 instances."
  type        = string
  default     = "t3.micro"
}

variable "instance_architecture" {
  description = "CPU architecture for the Ubuntu AMI lookup and instance type compatibility. One of: x86_64, arm64."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.instance_architecture)
    error_message = "instance_architecture must be either \"x86_64\" or \"arm64\"."
  }
}

variable "root_volume_size" {
  description = "Size (in GiB) of the root EBS volume for each EC2 instance."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}

variable "root_volume_type" {
  description = "EBS volume type for the root volume."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_type must be one of: gp2, gp3, io1, io2."
  }
}

variable "ssm_instance_profile_name" {
  description = <<-EOT
    Name of an EXISTING IAM instance profile (with an attached role that has
    AmazonSSMManagedInstanceCore) to attach to all EC2 instances. This module
    NEVER creates or modifies IAM resources - the instance profile must already
    exist. Terraform will fail fast with a clear error at plan time if it does
    not exist.
  EOT
  type        = string
  default     = "SSM"
}

variable "allowed_ssh_cidr" {
  description = <<-EOT
    CIDR block allowed to SSH (port 22) into instances via the security group.
    Leave as an empty string ("") to NOT create any SSH ingress rule at all
    (recommended - use AWS Systems Manager Session Manager instead of SSH).
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.allowed_ssh_cidr == "" || can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be empty (\"\") or a valid IPv4 CIDR block, e.g. \"203.0.113.10/32\"."
  }
}

variable "additional_ingress_ports" {
  description = "Additional inbound application ports to allow on the security group, beyond SSH."
  type = list(object({
    description = string
    port        = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "common_tags" {
  description = "Common tags applied to all resources, merged with Project/Environment/ManagedBy."
  type        = map(string)
  default = {
    Project     = "terraform-aws-infrastructure"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
