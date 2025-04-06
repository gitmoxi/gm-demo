provider "aws" {
  region = "us-east-1" # Replace with your desired region and update the variable below
}

################################################################################
# Locals and Variables
################################################################################

variable "region" {
  type        = string
  default     = "us-east-1"
}

variable "lambdaAlias" {
  type        = string
  default     = "PROD"
}

locals {
  api_name         = "example-api"
  lambda_role_name = "TestLambdaExecutionRole"
  blue_lambda_zip_file  = "blue_function.zip"
  green_lambda_zip_file  = "green_function.zip"
  sqs_lambda_zip_file  = "sqs_function.zip"
  lambda_runtime   = "python3.8"
  tags = {
    Project = "GitMoxi"
    Owner   = "User"
  }
}

################################################################################
# IAM Role for Lambda Execution
################################################################################

resource "aws_iam_role" "lambda_exec" {
  name = local.lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "sqs_lambda_policy" {
  name        = "SQSAccessPolicy"
  description = "Policy to allow Lambda to read messages from SQS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.example_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sqs_lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.sqs_lambda_policy.arn
}

################################################################################
# S3 Bucket for Lambda Deployment
################################################################################

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "lambda-function-deployment-bucket-${random_id.suffix.hex}"

  tags = local.tags
}

################################################################################
# Package Lambda Code and Upload to S3
################################################################################

# Unique identifier for the S3 bucket
resource "random_id" "suffix" {
  byte_length = 4
}

# Upload the Lambda zip file to S3
resource "aws_s3_object" "blue_lambda_zip" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = local.blue_lambda_zip_file
  source = local.blue_lambda_zip_file
  etag   = filemd5(local.blue_lambda_zip_file)
}

resource "aws_s3_object" "green_lambda_zip" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = local.green_lambda_zip_file
  source = local.green_lambda_zip_file
  etag   = filemd5(local.green_lambda_zip_file)
}

resource "aws_s3_object" "sqs_lambda_zip" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = local.sqs_lambda_zip_file
  source = local.sqs_lambda_zip_file
  etag   = filemd5(local.sqs_lambda_zip_file)
}

################################################################################
# API Gateway
################################################################################

resource "aws_apigatewayv2_api" "api" {
  name          = local.api_name
  protocol_type = "HTTP"

  tags = local.tags
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  stage_variables = {
    lambdaAlias = var.lambdaAlias
  }

  tags = local.tags
}

resource "aws_apigatewayv2_route" "test_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /test"
}

################################################################################
# VPC and Subnet Configuration
################################################################################

data "aws_vpc" "default" {
  default = true
}

resource "aws_vpc" "custom" {
  count      = length(data.aws_vpc.default.id) > 0 ? 0 : 1
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "custom-vpc"
  }
}

locals {
  vpc_id = length(data.aws_vpc.default.id) > 0 ? data.aws_vpc.default.id : aws_vpc.custom[0].id
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

resource "aws_subnet" "custom" {
  count                   = length(data.aws_subnets.default.ids) > 0 ? 0 : 2
  vpc_id                  = local.vpc_id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "custom-subnet-${count.index}"
  }
}

locals {
  subnet_ids = length(data.aws_subnets.default.ids) > 0 ? data.aws_subnets.default.ids : aws_subnet.custom[*].id
}

data "aws_availability_zones" "available" {}

################################################################################
# Load Balancer and Target Group
################################################################################

resource "aws_security_group" "elb_sg" {
  name        = "elb-security-group"
  description = "Security group for the ELB"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elb-sg"
  }
}

resource "aws_lb_target_group" "default" {
  name        = "my-target-group"
  vpc_id      = local.vpc_id
  target_type = "lambda"

  tags = {
    Name = "my-target-group"
  }
}

resource "aws_lb" "default" {
  name               = "my-application-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = local.subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "my-elb"
  }
}

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  protocol          = "HTTP"
  port = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
}

################################################################################
# SQS Queue
################################################################################

resource "aws_sqs_queue" "example_queue" {
  name = "example-queue"
}


################################################################################
# Send Initial Message to SQS
################################################################################

resource "null_resource" "send_message_to_sqs" {
  provisioner "local-exec" {
    command = <<EOT
      aws sqs send-message \
        --queue-url ${aws_sqs_queue.example_queue.url} \
        --message-body "Hello from SQS!" \
        --region ${var.region}
    EOT
  }

  depends_on = [aws_sqs_queue.example_queue]
}
