variable "region" {
  description = "The AWS region to deploy the resources"
  type        = string
  default     = "us-east-1"
}

variable "lambda_alias" {
  description = "The alias for the Lambda function"
  type        = string
  default     = "PROD"
}
