provider "aws" {
  region = var.region
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # Tags required for EKS
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = 1
  }

  tags = {
    Name = "eks-vpc"
  }
}

################################################################################
# EKS Cluster Role
################################################################################

resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.29"

  vpc_config {
    subnet_ids              = concat(module.vpc.private_subnets, module.vpc.public_subnets)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = {
    Environment = "dev"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

################################################################################
# Node Group Role
################################################################################

resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

################################################################################
# Node group with t3.small
################################################################################

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = module.vpc.private_subnets

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.small"]

  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only
  ]
}

################################################################################
# OIDC Provider for IRSA
################################################################################

data "aws_eks_cluster" "this" {
  name       = aws_eks_cluster.this.name
  depends_on = [aws_eks_cluster.this]
}

data "tls_certificate" "eks" {
  url        = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  depends_on = [data.aws_eks_cluster.this]
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  depends_on      = [data.tls_certificate.eks]
}

################################################################################
# ALB Controller IRSA
################################################################################

module "alb_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.53.0"

  role_name = "eks-alb-controller"

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.this.arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  attach_load_balancer_controller_policy = true
  depends_on                             = [aws_iam_openid_connect_provider.this]
}

################################################################################
# Service Account Creation
################################################################################

resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_irsa.iam_role_arn
    }
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
  }
  depends_on = [
    module.alb_irsa,
    aws_eks_node_group.default
  ]
}

################################################################################
# ALB Security Group - Allow HTTP (Port 80)
################################################################################

resource "aws_security_group" "alb_http" {
  name        = "alb-http-sg"
  description = "Allow inbound HTTP traffic on port 80"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-http-sg"
  }
}

################################################################################
# Validation before installation of ALB Controller
################################################################################

resource "time_sleep" "wait_for_nodes" {
  depends_on      = [aws_eks_node_group.default]
  create_duration = "120s"
}

data "aws_eks_cluster_auth" "this" {
  name       = aws_eks_cluster.this.name
  depends_on = [aws_eks_cluster.this]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

################################################################################
# Helm chart to install the ALB Controller
################################################################################

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  chart      = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  namespace  = "kube-system"
  version    = "1.7.1"
  timeout    = 900 # Increased timeout (15 minutes) to avoid deadline exceeded

  set {
    name  = "clusterName"
    value = aws_eks_cluster.this.name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  set {
    name  = "defaultSecurityGroups"
    value = aws_security_group.alb_http.id
  }

  depends_on = [
    kubernetes_service_account.aws_load_balancer_controller,
    time_sleep.wait_for_nodes
  ]
}
