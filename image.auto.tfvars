# Pinned EC2 AMI for the disposable sandbox fixture.
#
# Loaded automatically by terraform plan/apply (*.auto.tfvars), so no workflow
# change is required. The restricted TerraformPlanRole has no ec2:DescribeImages
# permission by design, so the image must be a resolved ID rather than discovered.
# This is an AWS-owned public Amazon Linux 2023 x86_64 image in us-east-1 and
# carries no customer data or secret; refresh it if the Region or baseline changes.
assessment_image_id = "ami-0ac62d2d72afdce51"
