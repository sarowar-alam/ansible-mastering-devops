resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.tags, { Name = "${var.name}-root" })
  }

  # IMDSv2 required - mitigates SSRF-style credential theft via the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.tags, { Name = var.name })
}

# Elastic IP is the ONLY source of a public IP address for this instance -
# the subnet does not auto-assign one (map_public_ip_on_launch = false).
resource "aws_eip" "this" {
  count = var.create_eip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.this.id

  tags = merge(var.tags, { Name = "${var.name}-eip" })
}
