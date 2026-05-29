
variable "primary_aws_region" {
  description = "The AWS region to deploy resources in US-EAST-1."
  type        = string
  default     = "us-east-1"
}

variable "secondary_aws_region" {
  description = "The AWS region to deploy resources in US-EAST-2."
  type        = string
  default     = "us-east-2"
}

