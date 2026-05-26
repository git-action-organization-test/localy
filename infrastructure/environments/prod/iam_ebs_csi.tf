# -------------------------------------------------------------------------
# 1. 선행 작업: KMS Key ARN 동적 낚아채기 (Hardcoding 방지)
# -------------------------------------------------------------------------
data "aws_kms_key" "eks_secrets" {
  # modules/eks/kms.tf에서 명명한 Alias를 타겟팅하여 ARN을 안전하게 로드합니다.
  key_id = "alias/${local.cluster_name}-secrets" 
}

# -------------------------------------------------------------------------
# 2. 제로 트러스트 OIDC 신뢰 정책 (Trust Relationship)
# -------------------------------------------------------------------------
data "aws_iam_policy_document" "ebs_csi_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    # [보안 록인] 오직 kube-system의 'ebs-csi-controller-sa'만 이 권한을 가질 수 있습니다.
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

# -------------------------------------------------------------------------
# 3. IAM Role 생성 및 AWS 깡통 권한 부여
# -------------------------------------------------------------------------
resource "aws_iam_role" "ebs_csi_role" {
  name               = "${local.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role_policy.json
}

# AWS가 제공하는 기본 EBS 제어 권한 (Attach, Detach, CreateVolume 등)
resource "aws_iam_role_policy_attachment" "ebs_csi_policy_attach" {
  role       = aws_iam_role.ebs_csi_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# -------------------------------------------------------------------------
# 4. [SRE 튜닝] KMS 암호화 해제 인라인 정책 (Inline Policy)
# -------------------------------------------------------------------------
data "aws_iam_policy_document" "ebs_csi_kms_policy" {
  statement {
    sid       = "AllowKMSDecryptForEBS"
    effect    = "Allow"
    actions   = [
      "kms:Decrypt",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:CreateGrant",
      "kms:DescribeKey",
      "kms:ReEncrypt*"
    ]
    # 위에서 동적으로 낚아챈 KMS Key에만 권한을 허용 (최소 권한의 원칙)
    resources = [data.aws_kms_key.eks_secrets.arn]
  }
}

# 인라인 정책을 Role에 영구 용접 (이 정책이 없으면 볼륨 Mount 시 Pending 발생)
resource "aws_iam_role_policy" "ebs_csi_kms_inline" {
  name   = "${local.cluster_name}-ebs-csi-kms-policy"
  role   = aws_iam_role.ebs_csi_role.name
  policy = data.aws_iam_policy_document.ebs_csi_kms_policy.json
}
