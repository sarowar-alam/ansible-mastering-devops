output "vpc_id" {
  value = module.dev.vpc_id
}

output "public_subnet_id" {
  value = module.dev.public_subnet_id
}

output "private_subnet_ids" {
  value = module.dev.private_subnet_ids
}

output "internet_gateway_id" {
  value = module.dev.internet_gateway_id
}

output "nat_gateway_id" {
  value = module.dev.nat_gateway_id
}

output "public_instance_id" {
  value = module.dev.public_instance_id
}

output "public_instance_private_ip" {
  value = module.dev.public_instance_private_ip
}

output "public_instance_public_ip" {
  value = module.dev.public_instance_public_ip
}

output "public_instance_eip" {
  value = module.dev.public_instance_eip
}

output "private_instance_ids" {
  value = module.dev.private_instance_ids
}

output "private_instance_private_ips" {
  value = module.dev.private_instance_private_ips
}

output "security_group_id" {
  value = module.dev.security_group_id
}

output "ubuntu_ami_id" {
  value = module.dev.ubuntu_ami_id
}
