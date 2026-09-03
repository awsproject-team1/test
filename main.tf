resource "aws_s3_bucket" "sandbox" {
  bucket = "sandbox"

  # Other configuration

  # Add public access block configuration
  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy      = true
    ignore_public_acls       = true
    restrict_public_buckets   = true
  }
}
