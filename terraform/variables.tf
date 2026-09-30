variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "region" {
  description = "AWS region to use."
  type        = string
}

variable "docker_tag" {
  description = "Image tag to use."
  type        = string
}

variable "service_count" {
  description = "Number of services to run."
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Smallest number of tasks the service can scale-in to."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Largest number of tasks the service can scale-out to."
  type        = number
  default     = 3
}

variable "cpu" {
  description = "CPU units to use."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory to allocate in MB."
  type        = number
  default     = 512
}

variable "enable_alarms" {
  description = "Whether to enable CloudWatch alarms for the service."
  type        = bool
  default     = false
}

variable "enable_observability_alerts" {
  type    = bool
  default = false
}

variable "metrics_namespace" {
  description = "CloudWatch namespace for the MCP server's metrics. Terraform passes it to the container as MCP_METRICS_NAMESPACE and uses it in alarms.tf, so the alarms always watch the namespace that the server writes to."
  type        = string
  default     = "TradeTariffMCP"
}
