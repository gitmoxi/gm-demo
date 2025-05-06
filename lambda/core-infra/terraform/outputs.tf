################################################################################
# Outputs
################################################################################

output "api_id" {
  description = "The API identifier"
  value       = aws_apigatewayv2_api.api.id
}

output "route_id" {
  description = "The route identifier"
  value       = aws_apigatewayv2_route.test_route.id
}

output "api_endpoint_with_route" {
  description = "The API endpoint with the route"
  value       = "https://${aws_apigatewayv2_api.api.id}.execute-api.${var.region}.amazonaws.com/test"
}

output "lambda_exec_role_arn" {
  description = "The ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_exec.arn
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.lambda_bucket.id
}

output "s3_object_blue_key" {
  description = "The key of the blue Lambda zip file in S3"
  value       = aws_s3_object.blue_lambda_zip.key
}

output "s3_object_green_key" {
  description = "The key of the green Lambda zip file in S3"
  value       = aws_s3_object.green_lambda_zip.key
}

output "s3_object_sqs_key" {
  description = "The key of the SQS Lambda zip file in S3"
  value       = aws_s3_object.sqs_lambda_zip.key
}

output "target_group_arn" {
  description = "The ARN of the load balancer target group"
  value       = aws_lb_target_group.default.arn
}

output "sqs_queue_arn" {
  description = "The ARN of the SQS queue"
  value       = aws_sqs_queue.example_queue.arn
}

output "elb_endpoint" {
  description = "The endpoint of the load balancer"
  value       = aws_lb.default.dns_name
}
