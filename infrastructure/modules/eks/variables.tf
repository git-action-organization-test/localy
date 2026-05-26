variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "admin_ip" {
  type = string
}

variable "cluster_endpoint_public_access" {
  description = "Enable access to the EKS public API endpoint."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the EKS public API endpoint."
  type        = list(string)
  default     = []
}

variable "cluster_security_group_additional_rules" {
  description = "Additional ingress/egress rules to attach to the cluster security group."
  type = map(object({
    type                     = string
    from_port                = number
    to_port                  = number
    protocol                 = string
    cidr_blocks              = optional(list(string))
    ipv6_cidr_blocks         = optional(list(string))
    source_security_group_id = optional(string)
    description              = optional(string)
  }))
  default = {}
}

variable "subnet_ids" {
  description = "EKS 클러스터와 노드가 배치될 서브넷 ID 리스트"
  type        = list(string)
}