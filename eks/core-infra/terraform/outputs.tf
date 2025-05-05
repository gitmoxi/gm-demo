output "cluster_arn" {
  value = aws_eks_cluster.this.arn
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "kubeconfig" {
  value = aws_eks_cluster.this.endpoint
}

