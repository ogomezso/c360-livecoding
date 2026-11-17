# ====================================================================
# AWS Resources Outputs
# ====================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Tableflow storage"
  value       = aws_s3_bucket.tableflow_storage.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.tableflow_storage.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.tableflow_storage.region
}

output "iam_role_arn" {
  description = "ARN of the IAM role for Tableflow"
  value       = aws_iam_role.tableflow_role.arn
}

output "iam_role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.tableflow_role.name
}

# ====================================================================
# Provider Integration Outputs
# ====================================================================

output "provider_integration_id" {
  description = "ID of the Confluent provider integration"
  value       = var.create_provider_integration ? try(confluent_provider_integration.tableflow_aws[0].id, "Not created") : "Manual creation required"
}

output "confluent_role_arn" {
  description = "Confluent's IAM role ARN for trust policy (use this to update IAM role trust policy)"
  value       = var.create_provider_integration ? try(confluent_provider_integration.tableflow_aws[0].aws[0].iam_role_arn, "Not available") : "Not available"
}

output "confluent_external_id" {
  description = "External ID for trust policy (use this to update IAM role trust policy)"
  value       = var.create_provider_integration ? try(confluent_provider_integration.tableflow_aws[0].aws[0].external_id, "Not available") : "Not available"
  sensitive   = true
}

# ====================================================================
# MCP Configuration Export
# ====================================================================

output "mcp_environment_variables" {
  description = "Environment variables for Confluent MCP configuration"
  value = {
    TABLEFLOW_S3_BUCKET_NAME          = aws_s3_bucket.tableflow_storage.id
    TABLEFLOW_S3_BUCKET_REGION        = aws_s3_bucket.tableflow_storage.region
    TABLEFLOW_IAM_ROLE_ARN            = aws_iam_role.tableflow_role.arn
    TABLEFLOW_PROVIDER_INTEGRATION_ID = var.create_provider_integration ? try(confluent_provider_integration.tableflow_aws[0].id, "") : ""
    CONFLUENT_ENVIRONMENT_ID          = var.confluent_environment_id
    CONFLUENT_CLUSTER_ID              = var.confluent_cluster_id
  }
}

output "mcp_export_command" {
  description = "Command to export MCP environment variables to your shell"
  value       = <<-EOT
    # Copy and paste these commands to export MCP environment variables:
    export TABLEFLOW_S3_BUCKET_NAME="${aws_s3_bucket.tableflow_storage.id}"
    export TABLEFLOW_S3_BUCKET_REGION="${aws_s3_bucket.tableflow_storage.region}"
    export TABLEFLOW_IAM_ROLE_ARN="${aws_iam_role.tableflow_role.arn}"
    export TABLEFLOW_PROVIDER_INTEGRATION_ID="${var.create_provider_integration ? try(confluent_provider_integration.tableflow_aws[0].id, "") : ""}"
    export CONFLUENT_ENVIRONMENT_ID="${var.confluent_environment_id}"
    export CONFLUENT_CLUSTER_ID="${var.confluent_cluster_id}"
  EOT
}

# ====================================================================
# Next Steps Instructions
# ====================================================================

output "next_steps" {
  description = "Instructions for completing the Tableflow setup"
  value       = <<-EOT
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║  Tableflow AWS Infrastructure Deployment Complete!                        ║
    ╚═══════════════════════════════════════════════════════════════════════════╝

    📦 S3 Bucket: ${aws_s3_bucket.tableflow_storage.id}
    🔑 IAM Role:  ${aws_iam_role.tableflow_role.arn}
    🔗 Provider Integration: ${var.create_provider_integration ? try(confluent_provider_integration.tableflow_aws[0].id, "Not created") : "Manual creation required"}

    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "⚠️  IMPORTANT: Trust Policy Update Required!" : ""}
    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "The IAM role trust policy needs to be updated with Confluent's role ARN." : ""}
    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "" : ""}
    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "Run these commands:" : ""}
    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "  1. terraform output -raw confluent_role_arn" : ""}
    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "  2. terraform output -raw confluent_external_id" : ""}
    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "  3. Set these values in terraform.tfvars:" : ""}
    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "     confluent_provider_integration_role_arn = \"<confluent_role_arn>\"" : ""}
    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "     confluent_external_id                    = \"<external_id>\"" : ""}
    ${var.create_provider_integration && var.confluent_provider_integration_role_arn == "" ? "  4. terraform apply" : ""}

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    📋 Next Steps - Create Tableflow Topics:

    1. Export MCP environment variables:
       $ terraform output -raw mcp_export_command | sh

    2. Create a Tableflow-enabled topic using Confluent MCP:
       Use: mcp__confluent__create-tableflow-topic
       Parameters:
         - display_name: Name of your Kafka topic
         - storage.bucket_name: ${aws_s3_bucket.tableflow_storage.id}
         - storage.provider_integration_id: ${var.create_provider_integration ? try(confluent_provider_integration.tableflow_aws[0].id, "") : ""}
         - table_formats: ["ICEBERG"] or ["DELTA"]

    3. Create AWS Glue Catalog Integration (optional):
       Use: mcp__confluent__create-tableflow-catalog-integration
       Parameters:
         - display_name: Name for the catalog integration
         - config.kind: "AwsGlue"
         - config.provider_integration_id: ${var.create_provider_integration ? try(confluent_provider_integration.tableflow_aws[0].id, "") : ""}

    4. Verify Tableflow is working:
       - Produce messages to your topic
       - Check S3 bucket for Iceberg table files
       - Query tables via AWS Athena or Glue Data Catalog

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    📚 Documentation:
       - Tableflow Docs: https://docs.confluent.io/cloud/current/topics/tableflow/
       - AWS S3 Console: https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.tableflow_storage.id}
       - IAM Console: https://console.aws.amazon.com/iam/home?region=${var.aws_region}#/roles/${aws_iam_role.tableflow_role.name}

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  EOT
}

# ====================================================================
# Trust Policy Information (for manual updates or verification)
# ====================================================================

output "current_trust_policy_status" {
  description = "Current status of the IAM role trust policy"
  value       = var.confluent_provider_integration_role_arn != "" ? "Trust policy updated with Confluent role" : "Trust policy not yet updated (deny-all placeholder)"
}

output "trust_policy_update_command" {
  description = "AWS CLI command to view the current trust policy"
  value       = "aws iam get-role --role-name ${aws_iam_role.tableflow_role.name} --query 'Role.AssumeRolePolicyDocument' --output json"
}
