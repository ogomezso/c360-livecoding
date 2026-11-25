# AWS Provider Configuration
variable "aws_region" {
  description = "AWS region for S3 bucket and IAM resources"
  type        = string
  default     = "eu-west-1"

  validation {
    condition = contains([
      "eu-west-1", "eu-west-2", "eu-west-3",
      "eu-central-1", "eu-north-1", "eu-south-1", "eu-south-2",
      "us-east-1", "us-east-2", "us-west-1", "us-west-2"
    ], var.aws_region)
    error_message = "AWS region must be a valid region."
  }
}

variable "aws_access_key" {
  description = "AWS access key ID for authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_secret_key" {
  description = "AWS secret access key for authentication"
  type        = string
  sensitive   = true
  default     = ""
}

# S3 Bucket Configuration
variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name (will be appended with random suffix for global uniqueness)"
  type        = string
  default     = "customer-360-tableflow-storage"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Confluent Cloud Configuration
variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key for provider integration creation"
  type        = string
  sensitive   = true
  default     = ""
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret for provider integration creation"
  type        = string
  sensitive   = true
  default     = ""
}

variable "confluent_environment_id" {
  description = "Confluent Environment ID (from terraform-confluent-aws outputs)"
  type        = string

  validation {
    condition     = can(regex("^env-[a-z0-9]+$", var.confluent_environment_id))
    error_message = "Environment ID must start with 'env-' followed by alphanumeric characters."
  }
}

variable "confluent_cluster_id" {
  description = "Kafka Cluster ID (from terraform-confluent-aws outputs)"
  type        = string

  validation {
    condition     = can(regex("^lkc-[a-z0-9]+$", var.confluent_cluster_id))
    error_message = "Cluster ID must start with 'lkc-' followed by alphanumeric characters."
  }
}

# Optional variables for two-phase deployment
variable "confluent_provider_integration_role_arn" {
  description = "Confluent's IAM role ARN (from provider integration, used in phase 2)"
  type        = string
  default     = ""
}

variable "confluent_external_id" {
  description = "External ID from Confluent provider integration (used in phase 2)"
  type        = string
  sensitive   = true
  default     = ""
}

# Resource Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "customer-360-demo"
    ManagedBy   = "terraform"
    Purpose     = "tableflow-storage"
    Project     = "customer-360"
  }
}

# IAM Role Configuration
variable "iam_role_name" {
  description = "Name of the IAM role for Tableflow"
  type        = string
  default     = "customer-360-tableflow-role"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.iam_role_name))
    error_message = "IAM role name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# Provider Integration Configuration
variable "provider_integration_display_name" {
  description = "Display name for the Confluent provider integration"
  type        = string
  default     = "customer-360-tableflow-integration"
}

variable "create_provider_integration" {
  description = "Whether to create the Confluent provider integration via Terraform (true) or manually (false)"
  type        = bool
  default     = true
}

variable "name_suffix" {
  description = "Suffix for the IAM role name. Normally set by scripts/tableflow.sh to the Confluent deployment's suffix so one demo shares one suffix; empty falls back to this stack's own random suffix."
  type        = string
  default     = ""
}

variable "bucket_force_destroy" {
  description = "Delete the bucket even if it contains objects when destroying. True for a demo, where the bucket only holds Tableflow output; set false to protect data."
  type        = bool
  default     = true
}
