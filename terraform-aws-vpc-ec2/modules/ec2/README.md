# ec2 module

Creates a single EC2 instance with a security-hardened baseline, meant to be
called once per instance (e.g. via `for_each` at the calling site).

## Security baseline

- **IMDSv2 required** (`http_tokens = "required"`, hop limit `1`) - blocks the
  classic SSRF-to-credential-theft path via the instance metadata service.
- **Encrypted root EBS volume** (`encrypted = true`), gp3 by default.
- **No public IP by default.** The instance never sets
  `associate_public_ip_address`; the subnet itself must have
  `map_public_ip_on_launch = false`. The only way this module gives an
  instance a public address is via `create_eip = true`, which allocates and
  associates a dedicated Elastic IP.
- **IAM via an existing instance profile only.** `iam_instance_profile` takes
  the *name* of a profile that must already exist - this module never creates
  IAM resources.

## Inputs / Outputs

See [variables.tf](variables.tf) and [outputs.tf](outputs.tf).
