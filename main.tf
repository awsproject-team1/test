resource "aws_s3_bucket" "sandbox" {
  bucket = "sandbox"

  # Add the following block to disable public access
  # This is the only change required to resolve the finding
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  require_bucket_owner_full_control = true
}
