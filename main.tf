resource "aws_s3_bucket" "sandbox" {
  bucket = "sandbox"

  # Add the following block to disable public access
  block_public_acls   = true
  block_public_policy = true
  # Add other necessary configurations
}
