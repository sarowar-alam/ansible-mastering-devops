output "instance_id" {
  description = "ID of the EC2 instance."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the instance."
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Public (Elastic) IP address, or null if create_eip = false."
  value       = try(aws_eip.this[0].public_ip, null)
}

output "eip_public_ip" {
  description = "Elastic IP address allocated to this instance, or null if create_eip = false."
  value       = try(aws_eip.this[0].public_ip, null)
}

output "eip_allocation_id" {
  description = "Allocation ID of the Elastic IP, or null if create_eip = false."
  value       = try(aws_eip.this[0].id, null)
}
