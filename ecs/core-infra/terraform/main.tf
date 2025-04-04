provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}

locals {
  name   = "gitmoxidemo"
  region = "us-west-2"
  cloudwatch_log_group_name = "/gitmoxidemo/ecs/nginx"
  log_retention_in_days = 1

  task_execution_role_name = "GitmoxiTaskExecutionRole"
  
  app_port = 80

  security_groups = [
    {
      name        = "allow_web"
      description = "Allow web inbound traffic"
      app_port    = 80
    }
  ]


  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    GitmoxiDemo = local.name
  }
}

################################################################################
# ECS Cluster
################################################################################

module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 5.6"

  cluster_name = local.name

  fargate_capacity_providers = {
    FARGATE      = {}
    FARGATE_SPOT = {}
  }

  tags = local.tags
}

################################################################################
# VPC and Subnets
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  tags = local.tags
}

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "allow_web" {
    for_each = { for sg in local.security_groups : sg.name => sg }

    name        = each.value.name
    description = each.value.description
    vpc_id      = module.vpc.vpc_id

    ingress {
        from_port   = each.value.app_port
        to_port     = each.value.app_port
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
        Name = each.value.name
    }
}

################################################################################
# CloudWatch LogGroup
################################################################################

resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = local.cloudwatch_log_group_name
  retention_in_days = local.log_retention_in_days
  tags = local.tags
}

################################################################################
# Task Execution IAM Role
################################################################################

resource "aws_iam_role" "task_execution_role" {
    name = local.task_execution_role_name

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Principal = {
                    Service = "ecs-tasks.amazonaws.com"
                }
                Effect = "Allow"
                Sid    = ""
            },
        ]
    })
    tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
    role       = aws_iam_role.task_execution_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################################################################
# Load Balancer
################################################################################

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name = local.name

  # For example only
  enable_deletion_protection = false

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = { for idx, cidr_block in module.vpc.private_subnets_cidr_blocks :
    idx => {
      ip_protocol = "-1"
      cidr_ipv4   = cidr_block
    }
  }


  listeners = {
    http = {
      port     = "80"
      protocol = "HTTP"

      weighted_forward = {
        target_groups = [
          {
            target_group_key =  "blue-tg"
            weight = 1
          },
          {
            target_group_key = "green-tg"
            weight = 0
          }
        ]
      }
    }
  }

  target_groups = {
    blue-tg = {
      name = "blue-tg"
      backend_protocol = "HTTP"
      backend_port     = local.app_port
      target_type      = "ip"

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "200-299"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 15
        unhealthy_threshold = 2
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }
    green-tg = {
      name = "green-tg"
      backend_protocol = "HTTP"
      backend_port     = local.app_port
      target_type      = "ip"

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "200-299"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 15
        unhealthy_threshold = 2
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }
  }

  tags = local.tags
}
