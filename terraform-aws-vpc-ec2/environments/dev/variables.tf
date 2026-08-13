variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile used for authentication."
  type        = string
  default     = "sarowar-ostad"
}

variable "environment" {
  description = "Environment name, used for naming/tagging."
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
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (AZ-1, AZ-2)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type used for all 3 instances."
  type        = string
  default     = "t3.micro"
}

variable "instance_architecture" {
  description = "CPU architecture for the Ubuntu AMI lookup. One of: x86_64, arm64."
  type        = string
  default     = "x86_64"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "root_volume_type" {
  description = "Root EBS volume type."
  type        = string
  default     = "gp3"
}

variable "ssm_instance_profile_name" {
  description = "Name of an EXISTING IAM instance profile with AmazonSSMManagedInstanceCore attached."
  type        = string
  default     = "SSM"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH. Leave empty to disable SSH ingress and rely on SSM."
  type        = string
  default     = ""
}

variable "additional_ingress_ports" {
  description = "Additional inbound application ports/CIDRs to allow."
  type = list(object({
    description = string
    port        = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "common_tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    Project     = "terraform-aws-infrastructure"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
