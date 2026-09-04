# The EC2/RDS/ALB fixture that used to live here was consolidated into main.tf.
# This file is intentionally kept (not deleted) but must define no resources:
# Terraform merges every *.tf in the directory, so declaring the same resource
# addresses here as well would be a duplicate-definition error.
