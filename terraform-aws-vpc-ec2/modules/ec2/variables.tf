variable "name" {
  description = "Name tag for the instance (and its EIP, if created)."
  type        = string
}

variable "ami_id" {
  description = "AMI ID to launch (resolved by the caller, e.g. via an aws_ami data source)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the instance in."
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to attach."
  type        = list(string)
}

variable "iam_instance_profile" {
  description = "Name of an EXISTING IAM instance profile to attach (never created by this module)."
  type        = string
}

variable "create_eip" {
  description = "Whether to allocate and associate an Elastic IP with this instance."
  type        = bool
  default     = false
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

variable "tags" {
  description = "Common tags applied to the instance (and EIP)."
  type        = map(string)
  default     = {}
}
