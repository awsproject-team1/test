variable "aws_region" {
  description = "Approved customer sandbox Region."
  type        = string
  default     = "us-east-1"
}

variable "sandbox_bucket_name" {
  description = "Globally unique, non-sensitive name for the first sandbox bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.sandbox_bucket_name))
    error_message = "Use a 3-63 character lowercase S3-compatible bucket name."
  }
}

variable "assessment_availability_zones" {
  description = "Two explicit Availability Zones for the disposable ALB and RDS fixture."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition = (
      length(var.assessment_availability_zones) == 2 &&
      alltrue([for zone in var.assessment_availability_zones : startswith(zone, var.aws_region)])
    )
    error_message = "Provide exactly two Availability Zones in the approved AWS Region."
  }
}

variable "assessment_image_id" {
  description = "AMI ID or EC2 resolve:ssm reference used by the disposable EC2 fixture."
  type        = string
  default     = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

  validation {
    condition = (
      can(regex("^ami-[0-9a-f]{8,17}$", var.assessment_image_id)) ||
      startswith(var.assessment_image_id, "resolve:ssm:/aws/service/ami-amazon-linux-latest/")
    )
    error_message = "Use an AMI ID or the approved AWS-owned Amazon Linux public parameter."
  }
}
