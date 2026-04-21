# Create Confluent Cloud Environment
resource "confluent_environment" "customer_360" {
  display_name = var.environment_display_name

  lifecycle {
    prevent_destroy = false
  }
}

# Create Standard Kafka Cluster on AWS
# Standard clusters have public endpoints and support Flink
# Perfect for local MCP server access and demo workloads
# Auto-scales from 0 to 10 eCKU based on usage
resource "confluent_kafka_cluster" "customer_360" {
  display_name = var.cluster_display_name
  availability = var.cluster_availability
  cloud        = var.cluster_cloud
  region       = var.cluster_region

  standard {}

  environment {
    id = confluent_environment.customer_360.id
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Create Service Account for the application
resource "confluent_service_account" "customer_360_app" {
  display_name = var.service_account_name
  description  = var.service_account_description
}

# Create API Key for Kafka Cluster
resource "confluent_api_key" "customer_360_kafka_api_key" {
  display_name = "customer-360-kafka-api-key"
  description  = "Kafka API Key for Customer 360 application"

  owner {
    id          = confluent_service_account.customer_360_app.id
    api_version = confluent_service_account.customer_360_app.api_version
    kind        = confluent_service_account.customer_360_app.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.customer_360.id
    api_version = confluent_kafka_cluster.customer_360.api_version
    kind        = confluent_kafka_cluster.customer_360.kind

    environment {
      id = confluent_environment.customer_360.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Grant ClusterAdmin role to the service account on the Kafka cluster
resource "confluent_role_binding" "customer_360_cluster_admin" {
  principal   = "User:${confluent_service_account.customer_360_app.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.customer_360.rbac_crn
}

# Get Flink Region information
data "confluent_flink_region" "customer_360" {
  cloud  = var.cluster_cloud
  region = var.cluster_region
}

# Create Flink Compute Pool
resource "confluent_flink_compute_pool" "customer_360" {
  display_name = var.flink_compute_pool_name
  cloud        = var.cluster_cloud
  region       = var.cluster_region
  max_cfu      = var.flink_max_cfu

  environment {
    id = confluent_environment.customer_360.id
  }

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [
    confluent_kafka_cluster.customer_360
  ]
}

# Create API Key for Flink (scoped to Flink region, not compute pool)
resource "confluent_api_key" "customer_360_flink_api_key" {
  display_name = "customer-360-flink-api-key"
  description  = "Flink API Key for Customer 360 application"

  owner {
    id          = confluent_service_account.customer_360_app.id
    api_version = confluent_service_account.customer_360_app.api_version
    kind        = confluent_service_account.customer_360_app.kind
  }

  managed_resource {
    id          = data.confluent_flink_region.customer_360.id
    api_version = data.confluent_flink_region.customer_360.api_version
    kind        = data.confluent_flink_region.customer_360.kind

    environment {
      id = confluent_environment.customer_360.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [
    confluent_role_binding.customer_360_flink_developer
  ]
}

# Grant FlinkDeveloper role to the service account on the Flink compute pool
resource "confluent_role_binding" "customer_360_flink_developer" {
  principal   = "User:${confluent_service_account.customer_360_app.id}"
  role_name   = "FlinkDeveloper"
  crn_pattern = confluent_flink_compute_pool.customer_360.resource_name
}

# Grant EnvironmentAdmin role to the service account on the environment
resource "confluent_role_binding" "customer_360_env_admin" {
  principal   = "User:${confluent_service_account.customer_360_app.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.customer_360.resource_name
}
