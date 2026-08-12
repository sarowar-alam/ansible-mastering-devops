# vpc module

Creates a VPC with one public subnet and two private subnets (across two
availability zones), plus the networking needed for public/private internet
egress.

## Resources created

- `aws_vpc`
- `aws_internet_gateway`
- 1x public `aws_subnet` + 2x private `aws_subnet` (AZs picked dynamically via
  `aws_availability_zones` data source - no hard-coded AZ names)
- 1x `aws_eip` + `aws_nat_gateway` (placed in the public subnet)
- Public route table (`0.0.0.0/0` → IGW) associated with the public subnet
- Private route table (`0.0.0.0/0` → NAT Gateway) associated with both
  private subnets

## Cost note: single NAT Gateway

This module intentionally provisions a **single** NAT Gateway (in the public
subnet) shared by both private subnets, to keep costs down for a dev/learning
environment. This means an AZ outage affecting the NAT Gateway's AZ would
disrupt outbound internet access for private subnets in the other AZ too.

For a highly-available production design, deploy **one NAT Gateway per AZ**
(each in its own public subnet) and give each private subnet its own route
table pointing at the NAT Gateway in the same AZ. That would require adding a
public subnet per AZ and parameterizing this module with a map of
`{ az => { public_cidr, private_cidr } }` instead of a single public subnet.

## Inputs / Outputs

See [variables.tf](variables.tf) and [outputs.tf](outputs.tf).
