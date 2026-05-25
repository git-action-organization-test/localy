# -------------------------------------------------------------------------
# ExternalDNS IRSA 구성 (1단계): AWS Route53 레코드 조작 권한 최소화
# -------------------------------------------------------------------------

# 1. EKS 클러스터 정보를 동적으로 조회하여 OIDC Issuer URL을 확보합니다.
#    하드코딩 금지, 클러스터 이름은 지시대로 prod-platform-eks를 사용합니다.
data "aws_eks_cluster" "prod_platform_eks" {
  name = "prod-platform-eks"
}

# 2. 클러스터의 OIDC 발급자를 직접 참조하여 IAM OIDC Provider를 조회합니다.
#    이로써 IRSA의 신뢰 관계가 실제 클러스터의 OIDC 공급자와 연결됩니다.
data "aws_iam_openid_connect_provider" "eks_oidc" {
  url = data.aws_eks_cluster.prod_platform_eks.identity[0].oidc[0].issuer
}

# 3. ExternalDNS가 AWS Route53에 접근할 수 있는 최소 권한 Policy 정의
resource "aws_iam_policy" "prod_externaldns_route53_policy" {
  name        = "prod-externaldns-route53-policy"
  path        = "/"
  description = "Least privilege Route53 policy for ExternalDNS in prod"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowListHostedZones"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowListResourceRecordSets"
        Effect = "Allow"
        Action = [
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowChangeResourceRecordSets"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      }
    ]
  })
}

# 4. OIDC Trust Relationship 정의: 오직 kube-system 네임스페이스의 external-dns-sa만 Role을 Assume 가능
data "aws_iam_policy_document" "prod_externaldns_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks_oidc.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.prod_platform_eks.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:external-dns-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.prod_platform_eks.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# 5. ExternalDNS IRSA 전용 IAM Role 생성
resource "aws_iam_role" "prod_externaldns_irsa_role" {
  name               = "prod-externaldns-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.prod_externaldns_assume_role_policy.json
}

# 6. IAM Role에 최소 권한 Policy 결합
resource "aws_iam_role_policy_attachment" "prod_externaldns_policy_attach" {
  role       = aws_iam_role.prod_externaldns_irsa_role.name
  policy_arn = aws_iam_policy.prod_externaldns_route53_policy.arn
}

# 7. Kubernetes Service Account 생성 및 IAM Role 바인딩
resource "kubernetes_service_account_v1" "external_dns_sa" {
  depends_on = [aws_iam_role_policy_attachment.prod_externaldns_policy_attach]

  metadata {
    name      = "external-dns-sa"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.prod_externaldns_irsa_role.arn
    }
  }
}
