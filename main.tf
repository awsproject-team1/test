resource "aws_s3_bucket" "sandbox" {
  bucket = "sandbox"

  # Other configuration

  # Add the following block to disable public access
  block_public_access {
    ignore_public_acls = false
    restrict_public_buckets = true
  }
}
