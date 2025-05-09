# EKS Cluster w/ Managed Node Group(s)

The configuration in this directory creates the following resources:

- EKS cluster with EKS managed node group(s) for data plane compute resources
- AWS load balancer controller deployed into the EKS cluster, configured to use EKS Pod Identity
  - :info: Note: this could be deployed via Gitmoxi as well but shown here for demonstration purposes for folks migrating from Terraform based deployments to Gitmoxi
- EKS access entry for the Gitmoxi deployment controller IAM role
- VPC with public and private subnets (for demonstration purposes)

## Deployment

After cloning the repository locally, navigate to the `eks/core-infra/terraform` directory and run the following commands:

> [!IMPORTANT]
> You will need the ARN of your Gitmoxi deployment controller IAM role to provision the EKS cluster correctly. Without this role, Gitmoxi will not be able to deploy and manage resources inside the cluster.

```sh
terraform init -upgrade
terraform apply -var="gitmoxi_iam_role_arn=<gitmoxi_iam_role_arn>"
```
