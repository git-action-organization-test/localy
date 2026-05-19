# 🏰 방탄형 ALB Ingress 배포 (Ingress Core)
# EKS 외부 트래픽을 내부 서비스로 안전하게 연결하는 최종 Ingress
# 3대 전술(비용 절감, 다이렉트 라우팅, WAF 결합)이 어노테이션으로 매핑됩니다.

resource "kubernetes_ingress_v1" "platform_ingress" {
  metadata {
    name      = "prod-platform-ingress"
    namespace = "default"

    annotations = {
      # ALB 프로바이더 및 인터넷 개방
      "kubernetes.io/ingress.class"      = "alb"
      "alb.ingress.kubernetes.io/scheme" = "internet-facing"

      # 전술 2: Target Type 'ip' 강제
      "alb.ingress.kubernetes.io/target-type" = "ip"

      # 전술 1: ALB Ingress Grouping (FinOps)
      "alb.ingress.kubernetes.io/group.name"  = "prod-ingress-group"
      "alb.ingress.kubernetes.io/group.order" = "10"

      # 전술 3: WAFv2 동적 결합 (루트 모듈의 WAF 리소스 직접 참조)
      # - 동일 디렉터리 내 다른 .tf 파일(waf.tf)에 선언된
      #   aws_wafv2_web_acl.prod_ingress_waf 리소스를 직접 참조합니다.
      "alb.ingress.kubernetes.io/wafv2-acl-arn" = aws_wafv2_web_acl.ingress_waf.arn
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.target_svc.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubernetes_service_v1.target_svc,
  ]
}
