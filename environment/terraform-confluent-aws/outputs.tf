# Environment outputs
output "environment_id" {
  description = "The ID of the Confluent Cloud environment"
  value       = confluent_environment.customer_360.id
}

output "environment_name" {
  description = "The name of the Confluent Cloud environment"
  value       = confluent_environment.customer_360.display_name
}

output "environment_resource_name" {
  description = "The resource name (CRN) of the environment"
  value       = confluent_environment.customer_360.resource_name
}

# Kafka Cluster outputs
output "kafka_cluster_id" {
  description = "The ID of the Kafka cluster"
  value       = confluent_kafka_cluster.customer_360.id
}

output "kafka_cluster_name" {
  description = "The name of the Kafka cluster"
  value       = confluent_kafka_cluster.customer_360.display_name
}

output "kafka_cluster_bootstrap_endpoint" {
  description = "The bootstrap endpoint of the Kafka cluster"
  value       = confluent_kafka_cluster.customer_360.bootstrap_endpoint
}

output "kafka_cluster_rest_endpoint" {
  description = "The REST endpoint of the Kafka cluster"
  value       = confluent_kafka_cluster.customer_360.rest_endpoint
}

output "kafka_cluster_region" {
  description = "The region where the Kafka cluster is deployed"
  value       = "${var.cluster_cloud}/${var.cluster_region}"
}

output "kafka_cluster_rbac_crn" {
  description = "The RBAC CRN of the Kafka cluster"
  value       = confluent_kafka_cluster.customer_360.rbac_crn
}

# Flink Compute Pool outputs
output "flink_compute_pool_id" {
  description = "The ID of the Flink compute pool"
  value       = confluent_flink_compute_pool.customer_360.id
}

output "flink_compute_pool_name" {
  description = "The name of the Flink compute pool"
  value       = confluent_flink_compute_pool.customer_360.display_name
}

output "flink_rest_endpoint" {
  description = "The REST endpoint for the Flink compute pool (constructed from region)"
  value       = "https://flink.${var.cluster_region}.${lower(var.cluster_cloud)}.confluent.cloud"
}

output "flink_compute_pool_resource_name" {
  description = "The resource name (CRN) of the Flink compute pool"
  value       = confluent_flink_compute_pool.customer_360.resource_name
}

# Service Account outputs
output "service_account_id" {
  description = "The ID of the service account"
  value       = confluent_service_account.customer_360_app.id
}

output "service_account_name" {
  description = "The name of the service account"
  value       = confluent_service_account.customer_360_app.display_name
}

# API Keys (sensitive outputs)
output "kafka_api_key" {
  description = "The Kafka API Key"
  value       = confluent_api_key.customer_360_kafka_api_key.id
  sensitive   = true
}

output "kafka_api_secret" {
  description = "The Kafka API Secret"
  value       = confluent_api_key.customer_360_kafka_api_key.secret
  sensitive   = true
}

output "flink_api_key" {
  description = "The Flink API Key"
  value       = confluent_api_key.customer_360_flink_api_key.id
  sensitive   = true
}

output "flink_api_secret" {
  description = "The Flink API Secret"
  value       = confluent_api_key.customer_360_flink_api_key.secret
  sensitive   = true
}

output "schema_registry_api_key" {
  description = "The Schema Registry API Key"
  value       = confluent_api_key.customer_360_schema_registry_api_key.id
  sensitive   = true
}

output "schema_registry_api_secret" {
  description = "The Schema Registry API Secret"
  value       = confluent_api_key.customer_360_schema_registry_api_key.secret
  sensitive   = true
}

# Consolidated connection information
output "connection_info" {
  description = "Connection information for the Customer 360 infrastructure"
  value = {
    environment = {
      id   = confluent_environment.customer_360.id
      name = confluent_environment.customer_360.display_name
    }
    kafka = {
      cluster_id        = confluent_kafka_cluster.customer_360.id
      bootstrap_servers = confluent_kafka_cluster.customer_360.bootstrap_endpoint
      rest_endpoint     = confluent_kafka_cluster.customer_360.rest_endpoint
      region            = "${var.cluster_cloud}/${var.cluster_region}"
    }
    flink = {
      compute_pool_id = confluent_flink_compute_pool.customer_360.id
      rest_endpoint   = "https://flink.${var.cluster_region}.${lower(var.cluster_cloud)}.confluent.cloud"
      region          = "${var.cluster_cloud}/${var.cluster_region}"
    }
  }
}

# Quick links
output "confluent_cloud_console_urls" {
  description = "Direct links to Confluent Cloud console"
  value = {
    environment   = "https://confluent.cloud/environments/${confluent_environment.customer_360.id}"
    kafka_cluster = "https://confluent.cloud/environments/${confluent_environment.customer_360.id}/clusters/${confluent_kafka_cluster.customer_360.id}"
    flink_console = "https://confluent.cloud/environments/${confluent_environment.customer_360.id}/flink"
    topics        = "https://confluent.cloud/environments/${confluent_environment.customer_360.id}/clusters/${confluent_kafka_cluster.customer_360.id}/topics"
  }
}

# Export for MCP server configuration
output "mcp_server_env_config" {
  description = "Environment variables for MCP server configuration - Complete setup for ALL MCP tools"
  value = <<-EOT
    # ============================================================================
    # CONFLUENT CLOUD API CREDENTIALS (Management Plane)
    # ============================================================================
    # Required for: Tag management, Catalog, Administrative operations
    CONFLUENT_CLOUD_API_KEY=${var.confluent_cloud_api_key}
    CONFLUENT_CLOUD_API_SECRET=${var.confluent_cloud_api_secret}
    CONFLUENT_CLOUD_REST_ENDPOINT=https://api.confluent.cloud

    # ============================================================================
    # KAFKA CLUSTER CONFIGURATION (Data Plane)
    # ============================================================================
    # Required for: Topic operations, Message production/consumption
    KAFKA_API_KEY=${confluent_api_key.customer_360_kafka_api_key.id}
    KAFKA_API_SECRET=${confluent_api_key.customer_360_kafka_api_key.secret}
    KAFKA_CLUSTER_ID=${confluent_kafka_cluster.customer_360.id}
    KAFKA_REST_ENDPOINT=${confluent_kafka_cluster.customer_360.rest_endpoint}
    KAFKA_ENV_ID=${confluent_environment.customer_360.id}
    BOOTSTRAP_SERVERS=${replace(confluent_kafka_cluster.customer_360.bootstrap_endpoint, "SASL_SSL://", "")}

    # ============================================================================
    # SCHEMA REGISTRY CONFIGURATION
    # ============================================================================
    # Required for: Schema operations, Tag tools, Catalog
    # Note: Exporting both ENDPOINT and URL for compatibility with different tools
    SCHEMA_REGISTRY_ENDPOINT=${data.confluent_schema_registry_cluster.customer_360.rest_endpoint}
    SCHEMA_REGISTRY_URL=${data.confluent_schema_registry_cluster.customer_360.rest_endpoint}
    SCHEMA_REGISTRY_API_KEY=${confluent_api_key.customer_360_schema_registry_api_key.id}
    SCHEMA_REGISTRY_API_SECRET=${confluent_api_key.customer_360_schema_registry_api_key.secret}

    # ============================================================================
    # FLINK CONFIGURATION
    # ============================================================================
    # Required for: Flink SQL, Flink Catalog, Flink Diagnostics tools
    FLINK_API_KEY=${confluent_api_key.customer_360_flink_api_key.id}
    FLINK_API_SECRET=${confluent_api_key.customer_360_flink_api_key.secret}
    FLINK_COMPUTE_POOL_ID=${confluent_flink_compute_pool.customer_360.id}
    FLINK_CLOUD=${var.cluster_cloud}
    FLINK_REGION=${var.cluster_region}
    FLINK_ENV_ID=${confluent_environment.customer_360.id}
    FLINK_ORG_ID=${local.org_id}
    FLINK_REST_ENDPOINT=${data.confluent_flink_region.customer_360.rest_endpoint}
    FLINK_DATABASE_NAME=${confluent_kafka_cluster.customer_360.id}
    FLINK_CATALOG_NAME=default_catalog

    # ============================================================================
    # CONNECTORS CONFIGURATION
    # ============================================================================
    # Required for: Connector management tools
    CONNECTORS_ENDPOINT=${confluent_kafka_cluster.customer_360.rest_endpoint}
    CONNECTORS_API_KEY=${confluent_api_key.customer_360_kafka_api_key.id}
    CONNECTORS_API_SECRET=${confluent_api_key.customer_360_kafka_api_key.secret}

    # ============================================================================
    # TABLEFLOW CONFIGURATION
    # ============================================================================
    # Required for: Tableflow topic management and catalog integration tools
    # Tableflow uses the same Kafka cluster API credentials
    TABLEFLOW_API_KEY=${confluent_api_key.customer_360_kafka_api_key.id}
    TABLEFLOW_API_SECRET=${confluent_api_key.customer_360_kafka_api_key.secret}
    TABLEFLOW_CATALOG_NAME=default_catalog

    # ============================================================================
    # TELEMETRY/METRICS CONFIGURATION
    # ============================================================================
    # Required for: Metrics querying and monitoring tools
    TELEMETRY_ENDPOINT=https://api.telemetry.confluent.cloud
    TELEMETRY_API_KEY=${var.confluent_cloud_api_key}
    TELEMETRY_API_SECRET=${var.confluent_cloud_api_secret}

    # ============================================================================
    # MCP SERVER CONFIGURATION
    # ============================================================================
    # Server runtime settings
    MCP_TRANSPORT=stdio
    LOG_LEVEL=info
    DO_NOT_TRACK=false
  EOT
  sensitive = true
}

# MCP Tools Status
output "mcp_tools_status" {
  description = "Status of available MCP tools based on configuration"
  value = <<-EOT
    ✅ ENABLED MCP Tools (configured and ready):

    📊 Kafka & Topics (6 tools)
       - list-topics, create-topics, delete-topics
       - produce-message, consume-messages
       - get-topic-config, alter-topic-config

    🏷️  Tags & Catalog (7 tools)
       - add-tags-to-topic, create-topic-tags, delete-tag
       - list-tags, remove-tag-from-entity
       - search-topics-by-name, search-topics-by-tag

    🔧 Flink SQL & Catalog (10+ tools)
       - create-flink-statement, list-flink-statements
       - list-flink-catalogs, list-flink-databases, list-flink-tables
       - describe-flink-table, get-flink-table-info
       - check-flink-statement-health, detect-flink-statement-issues

    🔌 Connectors (4 tools)
       - list-connectors, read-connector
       - create-connector, delete-connector

    📋 Schema Registry (2 tools)
       - list-schemas, delete-schema

    🌍 Environments & Clusters (3 tools)
       - list-environments, read-environment, list-clusters

    📈 Metrics & Billing (3 tools)
       - query-metrics, list-available-metrics, list-billing-costs

    📊 Tableflow & Catalog (10+ tools)
       - create-tableflow-topic, list-tableflow-topics, read-tableflow-topic
       - create-tableflow-catalog-integration, list-tableflow-catalog-integrations
       - update-tableflow-topic, delete-tableflow-topic, list-tableflow-regions

    Total: 45+ tools enabled and ready to use!
  EOT
}

# Next steps
output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    🎉 Confluent Cloud infrastructure deployed successfully!

    📋 Next Steps:
    1. View your environment: https://confluent.cloud/environments/${confluent_environment.customer_360.id}
    2. Access Kafka cluster: https://confluent.cloud/environments/${confluent_environment.customer_360.id}/clusters/${confluent_kafka_cluster.customer_360.id}
    3. Open Flink console: https://confluent.cloud/environments/${confluent_environment.customer_360.id}/flink
    4. Configure MCP Server:
       terraform output -raw mcp_server_env_config > ~/.confluent-mcp/.env
       (or run: cd ../.. && ./environment/reconfigure-mcp.sh)
    5. Restart Claude Code to load ALL MCP tools
    6. Check tool status: terraform output mcp_tools_status

    💡 Tip: Use 'terraform output -json' to get all outputs in JSON format
  EOT
}
