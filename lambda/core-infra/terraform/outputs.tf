################################################################################
# Outputs
################################################################################

output "api_id" {
  value = aws_apigatewayv2_api.api.id
}

output "route_id" {
  value = aws_apigatewayv2_route.test_route.id
}

output "api_endpoint_with_route" {
  value = "https://${aws_apigatewayv2_api.api.id}.execute-api.${var.region}.amazonaws.com/test"
}

output "lambda_exec_role_arn" {
  value = aws_iam_role.lambda_exec.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.lambda_bucket.id
}

output "s3_object_blue_key" {
  value = aws_s3_object.blue_lambda_zip.key
}

output "s3_object_green_key" {
  value = aws_s3_object.green_lambda_zip.key
}

output "s3_object_sqs_key" {
  value = aws_s3_object.sqs_lambda_zip.key
}

output "target_group_arn" {
  value = aws_lb_target_group.default.arn
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.example_queue.arn
}

output "elb_endpoint" {
  value = aws_lb.default.dns_name
}