resource "aws_s3_bucket" "sandbox" {
  bucket = "sandbox"

  # Other configuration

  # Add block to disable public access
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  require_bucket_owner_full_control = true
}
