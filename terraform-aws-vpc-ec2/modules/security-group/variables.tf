variable "name" {
  description = "Name of the security group."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to create the security group in."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH (port 22). Leave empty (\"\") to skip creating an SSH ingress rule entirely."
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

variable "tags" {
  description = "Common tags applied to the security group."
  type        = map(string)
  default     = {}
}
