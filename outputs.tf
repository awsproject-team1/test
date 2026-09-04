output "sandbox_bucket_name" {
  description = "Name of the customer-controlled onboarding bucket."
  value       = aws_s3_bucket.sandbox.id
}

output "sandbox_bucket_arn" {
  description = "ARN of the customer-controlled onboarding bucket."
  value       = aws_s3_bucket.sandbox.arn
}

output "assessment_resources" {
  description = "Resource coordinates to copy into the platform's approved assessment target."
  value = [
    { resource_type = "AWS::S3::Bucket", resource_id = aws_s3_bucket.sandbox.id },
    { resource_type = "AWS::EC2::Instance", resource_id = aws_instance.assessment.id },
    { resource_type = "AWS::RDS::DBInstance", resource_id = aws_db_instance.assessment.identifier },
    {
      resource_type = "AWS::ElasticLoadBalancingV2::LoadBalancer"
      resource_id   = aws_lb.assessment.arn
    },
  ]
}
