################################################################################
# Variables
################################################################################

variable "region" {
  description = "The AWS region to deploy the resources"
  type        = string
  default     = "us-west-2"
}

variable "gitmoxi_iam_role_arn" {
  description = "The IAM role ARN for the Gitmoxi deployment controller"
  type        = string
  default     = ""
}
