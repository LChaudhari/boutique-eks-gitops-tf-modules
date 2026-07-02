data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  # OIDC issuer host (without the https:// scheme), used in IRSA trust conditions.
  oidc_issuer = replace(aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
  partition   = data.aws_partition.current.partition
}

# ---------------------------------------------------------------------------
# KMS key for EKS Secrets envelope encryption (AWS-managed defaults + rotation).
# ---------------------------------------------------------------------------
resource "aws_kms_key" "eks_secrets" {
  description             = "EKS secrets envelope encryption for ${var.cluster_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = var.tags
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# ---------------------------------------------------------------------------
# Control plane CloudWatch log group (created up front so retention applies).
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# EKS Cluster role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# EKS Cluster — private nodes, restricted public endpoint, logging, secrets enc.
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "eks" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.cluster_version

  enabled_cluster_log_types = var.cluster_log_types

  vpc_config {
    # Control plane ENIs span both private and public subnets; nodes live private.
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.eks,
  ]
}

# ---------------------------------------------------------------------------
# OIDC provider for IRSA
# ---------------------------------------------------------------------------
data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks.identity[0].oidc[0].issuer
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# Node group role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "eks_node_role" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ---------------------------------------------------------------------------
# Managed node group — private subnets only.
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  disk_size      = var.disk_size
  labels         = var.node_labels

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(var.tags, { Terraform = "true" })

  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_policy,
  ]
}

# ---------------------------------------------------------------------------
# IRSA: EBS CSI driver
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_irsa" {
  name               = "${var.cluster_name}-ebs-csi-irsa"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_irsa_policy" {
  role       = aws_iam_role.ebs_csi_irsa.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ---------------------------------------------------------------------------
# Managed add-ons. vpc-cni / kube-proxy install before nodes; coredns after.
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.eks.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.eks.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.eks.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.node_group]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.eks.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi_irsa.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_irsa_policy,
    aws_eks_node_group.node_group,
  ]
}

# ---------------------------------------------------------------------------
# IRSA: Fluent Bit (ships pod logs to CloudWatch). Scoped to this account/region.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "fluent_bit_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:amazon-cloudwatch:aws-for-fluent-bit"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fluent_bit_irsa" {
  name               = "${var.cluster_name}-fluent-bit-irsa"
  assume_role_policy = data.aws_iam_policy_document.fluent_bit_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "fluent_bit_cloudwatch_logs" {
  name = "${var.cluster_name}-fluent-bit-cloudwatch-logs"
  role = aws_iam_role.fluent_bit_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
      ]
      Resource = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*"
    }]
  })
}

# ---------------------------------------------------------------------------
# IRSA: AWS Load Balancer Controller (policy JSON pulled from upstream v2.7.2).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "alb_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller_irsa" {
  name               = "${var.cluster_name}-alb-controller-irsa"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role.json
  tags               = var.tags
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${var.cluster_name}-alb-controller"
  description = "AWS Load Balancer Controller permissions"
  policy      = file("${path.module}/alb_controller_iam_policy.json")
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller_irsa.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# ---------------------------------------------------------------------------
# IRSA: ExternalDNS (manages Route53 records for Ingress hosts).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "external_dns_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns_irsa" {
  name               = "${var.cluster_name}-external-dns-irsa"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "external_dns" {
  name = "${var.cluster_name}-external-dns"
  role = aws_iam_role.external_dns_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = ["arn:${local.partition}:route53:::hostedzone/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
        Resource = ["*"]
      },
    ]
  })
}
