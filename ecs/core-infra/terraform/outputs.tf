
################################################################################
# Environment
################################################################################

output "region" {
  value = local.region
}

################################################################################
# VPC
################################################################################

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "A list of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "A list of private subnets for the client app"
  value       = module.vpc.private_subnets
}

output "private_subnets_cidr_blocks" {
  description = "A list of private subnets CIDRs"
  value       = module.vpc.private_subnets_cidr_blocks
}

################################################################################
# Security Groups
################################################################################

output "allow_web_security_group_ids" {
  description = "The ARNs of the created security groups"
  value       = [for sg in values(aws_security_group.allow_web) : sg.id]
}

################################################################################
# Load Balancer & Target Groups
################################################################################

output "alb_endpoint" {
  description = "The DNS endpoint of the ALB"
  value       = module.alb.dns_name
}

output "target_group_arns" {
  description = "Map of target group names to their ARNs."
  value       = { for tg in module.alb.target_groups : tg.name => tg.arn }
}

################################################################################
# Cluster
################################################################################

output "cluster_arn" {
  description = "ARN that identifies the cluster"
  value       = module.ecs_cluster.arn
}

output "cluster_id" {
  description = "ID that identifies the cluster"
  value       = module.ecs_cluster.id
}

output "cluster_name" {
  description = "Name that identifies the cluster"
  value       = module.ecs_cluster.name
}

################################################################################
# CloudWatch Log Group
################################################################################

output "cloudwatch_log_group_name" {
  description = "Cloudwatch log group name"
  value = aws_cloudwatch_log_group.cloudwatch_log_group.name
}

################################################################################
# Task Execution Role
################################################################################

output "task_execution_role_arn" {
  description = "The ARN of the Task Execution IAM Role"
  value       = aws_iam_role.task_execution_role.arn
}

