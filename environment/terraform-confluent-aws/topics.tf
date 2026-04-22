# ============================================================================
# Kafka Topics for Customer 360 Demo
# ============================================================================
# Creates the 4 source topics for the Customer 360 data product:
# - corebank.customers: Customer master data
# - corebank.accounts: Account information linked to customers
# - corebank.transactions: Transaction events
# - digital.interactions: Digital channel interactions
# ============================================================================

# Customer Master Data Topic
resource "confluent_kafka_topic" "customers" {
  kafka_cluster {
    id = confluent_kafka_cluster.customer_360.id
  }

  topic_name       = "corebank.customers"
  partitions_count = 6
  rest_endpoint    = confluent_kafka_cluster.customer_360.rest_endpoint

  credentials {
    key    = confluent_api_key.customer_360_kafka_api_key.id
    secret = confluent_api_key.customer_360_kafka_api_key.secret
  }

  config = {
    "cleanup.policy"    = "compact"
    "retention.ms"      = "-1"
    "max.message.bytes" = "1048588"
  }

  lifecycle {
    prevent_destroy = false
    # Don't modify existing topics - only create if they don't exist
    ignore_changes  = [
      config,
      partitions_count
    ]
  }

  depends_on = [
    confluent_role_binding.customer_360_cluster_admin
  ]
}

# Accounts Topic
resource "confluent_kafka_topic" "accounts" {
  kafka_cluster {
    id = confluent_kafka_cluster.customer_360.id
  }

  topic_name       = "corebank.accounts"
  partitions_count = 6
  rest_endpoint    = confluent_kafka_cluster.customer_360.rest_endpoint

  credentials {
    key    = confluent_api_key.customer_360_kafka_api_key.id
    secret = confluent_api_key.customer_360_kafka_api_key.secret
  }

  config = {
    "cleanup.policy"    = "compact"
    "retention.ms"      = "-1"
    "max.message.bytes" = "1048588"
  }

  lifecycle {
    prevent_destroy = false
    # Don't modify existing topics - only create if they don't exist
    ignore_changes  = [
      config,
      partitions_count
    ]
  }

  depends_on = [
    confluent_role_binding.customer_360_cluster_admin
  ]
}

# Transactions Topic (Event Stream)
resource "confluent_kafka_topic" "transactions" {
  kafka_cluster {
    id = confluent_kafka_cluster.customer_360.id
  }

  topic_name       = "corebank.transactions"
  partitions_count = 12
  rest_endpoint    = confluent_kafka_cluster.customer_360.rest_endpoint

  credentials {
    key    = confluent_api_key.customer_360_kafka_api_key.id
    secret = confluent_api_key.customer_360_kafka_api_key.secret
  }

  config = {
    "cleanup.policy"    = "delete"
    "retention.ms"      = "2592000000"
    "max.message.bytes" = "1048588"
  }

  lifecycle {
    prevent_destroy = false
    # Don't modify existing topics - only create if they don't exist
    ignore_changes  = [
      config,
      partitions_count
    ]
  }

  depends_on = [
    confluent_role_binding.customer_360_cluster_admin
  ]
}

# Digital Interactions Topic (Event Stream)
resource "confluent_kafka_topic" "interactions" {
  kafka_cluster {
    id = confluent_kafka_cluster.customer_360.id
  }

  topic_name       = "digital.interactions"
  partitions_count = 12
  rest_endpoint    = confluent_kafka_cluster.customer_360.rest_endpoint

  credentials {
    key    = confluent_api_key.customer_360_kafka_api_key.id
    secret = confluent_api_key.customer_360_kafka_api_key.secret
  }

  config = {
    "cleanup.policy"    = "delete"
    "retention.ms"      = "2592000000"
    "max.message.bytes" = "1048588"
  }

  lifecycle {
    prevent_destroy = false
    # Don't modify existing topics - only create if they don't exist
    ignore_changes  = [
      config,
      partitions_count
    ]
  }

  depends_on = [
    confluent_role_binding.customer_360_cluster_admin
  ]
}
