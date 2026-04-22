# ============================================================================
# Datagen Source Connectors
# ============================================================================
# Creates Datagen connectors to populate demo topics with synthetic data
# ============================================================================

# Clickstream Datagen Connector
resource "confluent_connector" "datagen_clickstream" {
  environment {
    id = confluent_environment.customer_360.id
  }

  kafka_cluster {
    id = confluent_kafka_cluster.customer_360.id
  }

  config_sensitive = {}

  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "DatagenSourceConnector_clickstream"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.customer_360_app.id
    "kafka.topic"              = confluent_kafka_topic.clickstream.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "CLICKSTREAM"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_kafka_topic.clickstream,
    confluent_role_binding.customer_360_cluster_admin
  ]

  lifecycle {
    prevent_destroy = false
  }
}

# Orders Datagen Connector
resource "confluent_connector" "datagen_orders" {
  environment {
    id = confluent_environment.customer_360.id
  }

  kafka_cluster {
    id = confluent_kafka_cluster.customer_360.id
  }

  config_sensitive = {}

  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "DatagenSourceConnector_orders"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.customer_360_app.id
    "kafka.topic"              = confluent_kafka_topic.orders.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "ORDERS"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_kafka_topic.orders,
    confluent_role_binding.customer_360_cluster_admin
  ]

  lifecycle {
    prevent_destroy = false
  }
}

# Pageviews Datagen Connector
resource "confluent_connector" "datagen_pageviews" {
  environment {
    id = confluent_environment.customer_360.id
  }

  kafka_cluster {
    id = confluent_kafka_cluster.customer_360.id
  }

  config_sensitive = {}

  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "DatagenSourceConnector_pageviews"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.customer_360_app.id
    "kafka.topic"              = confluent_kafka_topic.pageviews.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "PAGEVIEWS"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_kafka_topic.pageviews,
    confluent_role_binding.customer_360_cluster_admin
  ]

  lifecycle {
    prevent_destroy = false
  }
}

# Stock Trades Datagen Connector
resource "confluent_connector" "datagen_stock_trades" {
  environment {
    id = confluent_environment.customer_360.id
  }

  kafka_cluster {
    id = confluent_kafka_cluster.customer_360.id
  }

  config_sensitive = {}

  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "DatagenSourceConnector_stock_trades"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.customer_360_app.id
    "kafka.topic"              = confluent_kafka_topic.stock_trades.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "STOCK_TRADES"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_kafka_topic.stock_trades,
    confluent_role_binding.customer_360_cluster_admin
  ]

  lifecycle {
    prevent_destroy = false
  }
}
