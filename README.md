# Customer sandbox Terraform repository starter

Copy these files into a new, customer-owned private repository. They are a non-deploying starter only: the customer must supply the state backend, a globally unique bucket name, reviewer-approved OIDC roles, and a generated `.terraform.lock.hcl` before any workflow is run. A public repository is allowed only for an explicitly approved disposable test with no customer data, credentials, policy material, state file, or production configuration.

This disposable customer sandbox contains the original S3 assessment target plus deliberately non-compliant EC2, RDS, and ALB targets. The extra resources exist to exercise multi-resource IaC policy evaluation; they are not a production workload. The repository contains no account IDs, credentials, policy text, state, or customer data.

The multi-resource fixture is plan-first. A Terraform plan may be generated through the `customer-terraform-plan` environment, but creating the resources would incur AWS charges and therefore requires a separate protected `customer-terraform-apply` approval. Availability Zones are explicit inputs so the restricted plan role does not need account-wide discovery permissions. The EC2 image defaults to AWS's public Amazon Linux 2023 Systems Manager reference; pin `assessment_image_id` to the resolved AMI before approving an apply.

Expected policy violations:

- EC2: public IP requested in a private subnet, unrestricted SSH/HTTP ingress, and unencrypted root EBS.
- RDS: public accessibility, unrestricted MySQL ingress, storage encryption disabled, IAM DB authentication disabled, and log exports disabled.
- ALB: public plaintext HTTP listener and access logging disabled.

`terraform output assessment_resources` returns the four resource coordinates needed by the platform's protected assessment runtime configuration after an approved apply.

## Install

1. Copy `backend.hcl.example` to the customer-controlled `backend.hcl` and replace every placeholder.
2. Copy `terraform.tfvars.example` to a protected customer variable source or customer-controlled `terraform.tfvars`; choose a globally unique bucket name.
3. In the customer repository, initialize and lock the exact providers:

   ```bash
   terraform init -backend-config=backend.hcl
   terraform providers lock
   ```

   Commit `.terraform.lock.hcl`; do not commit `backend.hcl` or `terraform.tfvars` if they identify the customer.
4. Manually install the platform workflow templates and canonical hash helper described in `docs/CUSTOMER_SANDBOX_ONBOARDING.md`. Do not put role, state, or sandbox bucket values in the copied workflows: configure `AWS_REGION`, each role ARN, the shared state bucket/key/lock-table values, and `SANDBOX_BUCKET_NAME` as GitHub Environment variables instead.
5. Submit the first baseline through a normal customer PR. Never run local `terraform apply`; actual apply is through the protected GitHub workflow.

## State conventions

The backend uses one state key per customer/repository workspace. The concrete key belongs in customer-controlled `backend.hcl`; this template provides no default to prevent accidental state sharing.
