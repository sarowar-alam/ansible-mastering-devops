# ansible-mastering-devops

Infrastructure (`terraform-aws-vpc-ec2/`) provisions a VPC with 1 public + 2
private Ubuntu EC2 instances, all reachable via AWS Systems Manager Session
Manager (no SSH keys, no inbound security-group rules). This repo turns the
public instance into an Ansible controller that manages all 3 nodes purely
over SSM.

## Prerequisites (run once, locally, with IAM/S3 admin rights)

The `amazon.aws.aws_ssm` connection plugin requires an S3 bucket for file
transfer and extra IAM permissions on the instances' "SSM" role - neither of
which terraform-aws-vpc-ec2 manages (it only looks up that role). Create them
with:

```bash
AWS_PROFILE=sarowar-ostad AWS_REGION=ap-south-1 ./scripts/prepare-aws-prereqs.sh
```

Copy the printed bucket name into `ansible/group_vars/all.yml`
(`ansible_aws_ssm_bucket_name`), commit and push.

## Bootstrap the controller

1. Log in to the public instance via SSM (from your laptop):
   ```bash
   aws ssm start-session --target <public_instance_id> --profile sarowar-ostad --region ap-south-1
   ```
2. Inside the session:
   ```bash
   git clone https://github.com/sarowar-alam/ansible-mastering-devops.git
   cd ansible-mastering-devops
   bash scripts/bootstrap-ansible-controller.sh
   ```

## Verify and run

```bash
bash scripts/verify-ansible-controller.sh
cd ansible
ansible-playbook -i inventories/aws_ec2.yml playbooks/site.yml
```

The playbook installs and starts nginx on all 3 discovered nodes (grouped by
tag `Role` into `role_public` / `role_private`; use `--limit role_private` to
target only the private nodes).
