# security-group module

Creates a single, shared least-privilege security group for the three EC2
instances.

## Design

- **No inbound rules by default.** SSM Session Manager requires only
  outbound connectivity, so with the default `allowed_ssh_cidr = ""` this
  security group has zero inbound rules.
- **SSH is opt-in and scoped.** If `allowed_ssh_cidr` is set to a specific
  CIDR (e.g. `"203.0.113.10/32"`), a single inbound TCP/22 rule is created
  for that CIDR only. `0.0.0.0/0` on port 22 is never created automatically.
- **Additional application ports** can be opened via `additional_ingress_ports`,
  each with its own description/port/protocol/CIDR list.
- **Egress is open** (`0.0.0.0/0`, all protocols) so instances can reach the
  SSM endpoints, Ubuntu package repositories, and any application dependency
  over the internet (via IGW for the public instance, via NAT Gateway for the
  private instances).

## Inputs / Outputs

See [variables.tf](variables.tf) and [outputs.tf](outputs.tf).
