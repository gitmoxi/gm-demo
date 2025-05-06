################################################################################
# AWS Load Balancer Controller
################################################################################

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  chart      = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  namespace  = "kube-system"
  version    = "1.12.0"
  wait       = false

  values = [
    <<-EOT
      vpcId: ${module.vpc.vpc_id}
      clusterName: ${module.eks.cluster_name}
      region: ${var.region}
    EOT
  ]
}

module "aws_load_balancer_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> v1.11"

  name = "aws-lbc"

  attach_aws_lb_controller_policy = true

  # Pod Identity Associations
  association_defaults = {
    namespace       = "kube-system"
    service_account = "aws-load-balancer-controller-sa"
  }

  associations = {
    default = {
      cluster_name = module.eks.cluster_name
    }
  }

  tags = local.tags
}
