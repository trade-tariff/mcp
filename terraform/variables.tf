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

variable "mcp_rate_limit_rpm" {
  description = "The shared MCP usage plan's limit in requests per minute, as configured in the terraform repo's gateway.tf. Used only to derive the alarm threshold and to describe it."
  type        = number
  default     = 3000
}

variable "mcp_rate_limit_alarm_percentage" {
  description = "Percentage of the global MCP rate limit at which the approaching-limit alarm fires."
  type        = number
  default     = 80
}

variable "mcp_rate_limit_alarm_periods" {
  description = "Number of consecutive 60-second periods above the threshold before the approaching-limit alarm fires."
  type        = number
  default     = 5
}

variable "enable_mcp_rate_limit_alarms" {
  description = "Whether to enable the MCP global rate limit alarms (approaching-limit and rate-limited). Deliberately separate from enable_alarms, which governs the ecs-service module's own unrelated alarms and defaults to false; these alarms should be on everywhere by default so the development verification step (triggering the 429 alarm) works out of the box."
  type        = bool
  default     = true
}
