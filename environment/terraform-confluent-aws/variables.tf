# Confluent Cloud credentials
variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (Organization level)"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret (Organization level)"
  type        = string
  sensitive   = true
}

# Environment configuration
variable "environment_name" {
  description = "Name of the Confluent Cloud environment"
  type        = string
  default     = "customer-360-demo"
}

variable "environment_display_name" {
  description = "Display name for the Confluent Cloud environment (alphanumeric, hyphens, underscores only)"
  type        = string
  default     = "customer-360-demo-environment"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]$", var.environment_display_name))
    error_message = "Environment name must start and end with alphanumeric characters and can only contain hyphens and underscores (no spaces)."
  }
}

# Kafka cluster configuration
variable "cluster_display_name" {
  description = "Display name for the Kafka cluster"
  type        = string
  default     = "customer-360-cluster"
}

variable "cluster_cloud" {
  description = "Cloud provider for the Kafka cluster"
  type        = string
  default     = "AWS"
}

variable "cluster_region" {
  description = "AWS region for the Kafka cluster (closest European region)"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_availability" {
  description = "Availability zone configuration (SINGLE_ZONE or MULTI_ZONE)"
  type        = string
  default     = "MULTI_ZONE"

  validation {
    condition     = contains(["SINGLE_ZONE", "MULTI_ZONE"], var.cluster_availability)
    error_message = "Availability must be either SINGLE_ZONE or MULTI_ZONE."
  }
}

# Standard clusters use elastic eCKUs (auto-scaling from 0-10 eCKU)
# No CKU configuration needed - automatically scales based on usage

# Flink configuration
variable "flink_compute_pool_name" {
  description = "Display name for the Flink compute pool"
  type        = string
  default     = "customer-360-flink-pool"
}

variable "flink_max_cfu" {
  description = "Maximum Confluent Flink Units (CFUs) for the compute pool"
  type        = number
  default     = 10

  validation {
    condition     = var.flink_max_cfu >= 5
    error_message = "Maximum CFU must be at least 5."
  }
}

# Service Account configuration
variable "service_account_name" {
  description = "Name for the service account"
  type        = string
  default     = "customer-360-sa"
}

variable "service_account_description" {
  description = "Description for the service account"
  type        = string
  default     = "Service account for Customer 360 demo application"
}

# Resource tags
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    project     = "customer-360"
    environment = "demo"
    managed_by  = "terraform"
  }
}
