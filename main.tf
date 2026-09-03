resource "aws_s3_bucket" "sandbox" {
  bucket = "tfsbx-20260903-7f3a-a91c"

  # Add the following block to disable public access
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  require_bucket_owner_full_control = true
}
