output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = module.vpc.public_subnet_id
}

output "private_subnet_ids" {
  description = "IDs of the two private subnets (AZ-1, AZ-2)."
  value       = module.vpc.private_subnet_ids
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = module.vpc.internet_gateway_id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway."
  value       = module.vpc.nat_gateway_id
}

output "public_instance_id" {
  description = "Instance ID of the public EC2 instance (dev-public-01)."
  value       = module.ec2[local.public_instance_key].instance_id
}

output "public_instance_private_ip" {
  description = "Private IP of the public EC2 instance."
  value       = module.ec2[local.public_instance_key].private_ip
}

output "public_instance_public_ip" {
  description = "Public IP (Elastic IP) of the public EC2 instance."
  value       = module.ec2[local.public_instance_key].public_ip
}

output "public_instance_eip" {
  description = "Elastic IP address allocated to the public EC2 instance."
  value       = module.ec2[local.public_instance_key].eip_public_ip
}

output "private_instance_ids" {
  description = "Instance IDs of the two private EC2 instances."
  value       = [for k, v in module.ec2 : v.instance_id if k != local.public_instance_key]
}

output "private_instance_private_ips" {
  description = "Private IPs of the two private EC2 instances."
  value       = [for k, v in module.ec2 : v.private_ip if k != local.public_instance_key]
}

output "security_group_id" {
  description = "ID of the shared EC2 security group."
  value       = module.security_group.security_group_id
}

output "ubuntu_ami_id" {
  description = "AMI ID resolved for the Ubuntu 26.04 LTS image actually used."
  value       = data.aws_ami.ubuntu.id
}
