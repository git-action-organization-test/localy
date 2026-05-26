# =============================================================================
# [Frame 2 - Step 2] 관제탑 코어 기동 (Prometheus & Grafana)
# Part 1: 관제탑 뼈대 및 보안 통제 (Base & Security)
# =============================================================================

# -----------------------------------------------------------------------------
# Task 1: Grafana Admin Password 동적 생성
# (※ 주의: tfstate 평문 노출 부채 발생. Frame 3에서 Secrets Manager로 이관 예정)
# -----------------------------------------------------------------------------
resource "random_password" "grafana_admin" {
  length           = 16
  special          = true
  override_special = "!#%&*()-_=+[]{}<>:?"
}

# -----------------------------------------------------------------------------
# Task 2~4: 방어적 SRE 튜닝이 결속된 관제탑 본체 투하
# -----------------------------------------------------------------------------
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "58.2.2" # 안정성이 검증된 최신 Stable 버전
  namespace        = "monitoring"
  create_namespace = true
  wait             = true
  timeout          = 600

  # [SRE 튜닝] 레이스 컨디션 방어:
  # EBS CSI 드라이버와 AWS LBC가 완벽히 기동된 후에만 관제탑 배포를 시작하도록 족쇄를 채움
  depends_on = [
    aws_eks_addon.ebs_csi,
    helm_release.aws_load_balancer_controller,
  ]

  values = [
    yamlencode({
      # -----------------------------------------------------------------------
      # [Part 1] Grafana 보안 통제 튜닝
      # -----------------------------------------------------------------------
      grafana = {
        adminPassword = random_password.grafana_admin.result
      }

      # -----------------------------------------------------------------------
      # [Part 2 & 3] Prometheus SRE 튜닝 (Storage, AZ Pinning, OOM 방어)
      # -----------------------------------------------------------------------
      prometheus = {
        prometheusSpec = {
          # [Part 2] 데이터 보존 주기 14일
          retention = "14d"

          # [Part 2] AZ Pinning 및 온디맨드 스케줄링 강제 (Karpenter 족쇄)
          nodeSelector = {
            "topology.kubernetes.io/zone" = "ap-northeast-2a"
            "karpenter.sh/capacity-type"  = "on-demand"
          }

          # [Part 2] EBS CSI 기반 50Gi gp3 영구 스토리지 프로비저닝
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
              }
            }
          }

          # -------------------------------------------------------------------
          # [Part 3] OOMKilled 방어 및 리소스 격리 (Graviton 8GB 노드 기준)
          # -------------------------------------------------------------------
          resources = {
            requests = {
              cpu    = "500m"
              memory = "2Gi" # 최소 보장 메모리
            }
            limits = {
              cpu    = "1000m"
              memory = "4Gi" # 최대 허용 메모리 (초과 시 해당 파드만 즉시 사살)
            }
          }
        }
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# Output: 초기 접속용 패스워드 출력 (Step 5 E2E 실증 접속용)
# -----------------------------------------------------------------------------
output "grafana_admin_password" {
  description = "Grafana 초기 Admin 패스워드 (절대 외부에 노출 금지)"
  value       = random_password.grafana_admin.result
  sensitive   = true
}
