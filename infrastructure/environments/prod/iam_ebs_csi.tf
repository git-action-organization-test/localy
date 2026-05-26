# -------------------------------------------------------------------------
# 1. 제로 트러스트 OIDC 신뢰 정책 (Trust Relationship)
# KMS ARN은 동일 state의 module.eks output을 직접 참조합니다.
# data "aws_kms_key"는 키 미생성 시 plan/apply에서 'couldn't find resource'를 유발합니다.
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
  name               = "${module.eks.cluster_name}-ebs-csi-role"
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
    resources = [module.eks.kms_key_arn]
  }
}

# 인라인 정책을 Role에 영구 용접 (이 정책이 없으면 볼륨 Mount 시 Pending 발생)
resource "aws_iam_role_policy" "ebs_csi_kms_inline" {
  name   = "${module.eks.cluster_name}-ebs-csi-kms-policy"
  role   = aws_iam_role.ebs_csi_role.name
  policy = data.aws_iam_policy_document.ebs_csi_kms_policy.json
}
