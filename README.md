# Customer 360 Live Coding Workshop – Implementation Notes

Minimal checklist to implement the live demo: **Customer 360 data product on Confluent DSP using Flink + Claude Code (via MCP)**.

## 📊 Current Status

**✅ Completed:**

- Infrastructure provisioned (Terraform)
- Confluent MCP server configured and working
- Kafka cluster running: `customer-360-cluster` (lkc-jq5kwq, AWS eu-west-1)
- Flink compute pool ready
- Kafka topics created (automated via Terraform)
- Avro schemas defined
- Synthetic data generators ready (Spanish banking data)
- Environment protection (.gitignore consolidated)

**🚧 In Progress:**

- Building Flink SQL transformations
- Creating `customer_360_snapshot` data product

**⏳ To Do:**

- (Optional) Configure Tableflow integration

---

## 1. Goal

Build a `customer_360_snapshot` data product in (near) real time that aggregates key information per customer for a retail bank:

- Customer identity and segment
- Associated products/accounts
- Transaction activity (last 30 days)
- Digital activity (channels / last login)
- Basic risk/fraud signals (optional)

Claude Code should help to:

- Understand the datasets (topics, schemas, samples)
- Design the data product schema
- Generate and debug the Flink SQL

---

## 2. DSP Setup (Confluent)

**⚡ Automated Setup Available!** Use Terraform to provision the entire Confluent Cloud infrastructure:

```bash
cd environment/terraform-confluent-aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Confluent Cloud API credentials
terraform init
terraform apply
```

See [environment/terraform-confluent-aws/README.md](environment/terraform-confluent-aws/README.md) for complete instructions.

**What gets provisioned:**

- ✅ Confluent Cloud Environment
- ✅ Enterprise Kafka Cluster (AWS eu-west-1, Multi-Zone)
- ✅ Flink Compute Pool (Serverless, 0-10 CFUs)
- ✅ Service Account with proper RBAC roles
- ✅ API Keys for Kafka and Flink
- ✅ Schema Registry (included with cluster)

### 2.1 Kafka & Schema Registry

**Kafka topics** are automatically created by Terraform (`terraform-confluent-aws/topics.tf`):

**Customer 360 Topics:**

- `corebank.customers` - Customer master data (compacted, Avro)
- `corebank.accounts` - Account information (compacted, Avro)
- `corebank.transactions` - Transaction events (30-day retention, Avro)
- `digital.interactions` - Digital channel interactions (30-day retention, **Plain JSON - schemaless**)

**Additional Datagen Demo Topics:**

- `clickstream` - Web analytics events (7-day retention, Avro, Datagen connector)
- `orders` - E-commerce order events (30-day retention, Avro, Datagen connector)
- `pageviews` - Marketing analytics events (7-day retention, Avro, Datagen connector)
- `stock_trades` - Financial market events (7-day retention, Avro, Datagen connector)

These Datagen topics provide additional demo scenarios beyond Customer 360. The connectors automatically generate realistic synthetic data using Confluent's quickstart templates.

**Schemas:**

Avro schemas for customers, accounts, and transactions are auto-registered with Schema Registry:

- `customers`: `customer_id`, `full_name`, `segment`, `risk_band`, `relationship_manager`, `email`, `phone`, `created_at`
- `accounts`: `account_id`, `customer_id`, `product_type`, `status`, `balance`, `currency`, `opened_at`
- `transactions`: `txn_id`, `account_id`, `amount`, `currency`, `mcc`, `merchant_name`, `channel`, `ts`

The `digital.interactions` topic uses **plain JSON** (no Schema Registry) to demonstrate **Flink's schema inference capability**:

- `interactions` (JSON): `event_id`, `customer_id`, `event_type`, `channel`, `session_id`, `ts`

**Generate realistic synthetic data:**

```bash
cd environment
./generate-data.sh
```

This creates realistic Spanish banking data:

- 200 customers (Spanish names, segments, risk bands)
- 400+ accounts (checking, savings, credit cards, mortgages)
- 1,000+ transactions (Spanish merchants, EUR currency, MCC codes)
- 800+ digital interactions (login, transfers, payments)

See [environment/data-generation/README.md](environment/data-generation/README.md) for details.

### 2.2 Flink

The Terraform configuration automatically creates:

- ✅ **Flink compute pool** (serverless, auto-scales 0-10 CFUs)
- ✅ **Flink API key** with FlinkDeveloper role
- ✅ Direct console access via output URLs

Verify you can:

- Run `SELECT * FROM <table> LIMIT 10;` using simple dynamic tables
- Create tables and jobs from the Flink console
- Access Flink SQL workspace at: `terraform output -raw confluent_cloud_console_urls | jq -r '.flink_console'`

### 2.3 (Optional) Tableflow

- Configure integration with S3/ADLS if you want to show materialization:
  - A demo bucket/account
  - At least one topic enabled with Tableflow to confirm it works

---

## 3. MCP + Claude Code

### 3.1 MCP Server (Confluent MCP)

**⚡ Quick Setup:** This project includes automated provisioning scripts for the official Confluent MCP server!

```bash
cd environment/mcp-confluent
./provision-confluent-mcp.sh
```

See [environment/mcp-confluent/README.md](environment/mcp-confluent/README.md) for complete setup instructions.

The Confluent MCP server provides **50+ tools** including:

**Kafka / schemas:**

- `list_topics()`
- `get_topic_schema(topic)`
- `sample_records(topic, limit)`
- `create_topic()`, `delete_topic()`
- `produce_message()`, `consume_messages()`

**Schema Registry:**

- `register_schema()`, `list_schemas()`
- `get_schema()`, `delete_schema()`

**Flink SQL:**

- `execute_flink_sql(statement)`
- `list_flink_statements()`, `get_flink_statement()`
- `create_flink_compute_pool()`, `list_flink_compute_pools()`

**Cloud Management:**

- `create_environment()`, `list_environments()`
- `create_cluster()`, `list_clusters()`
- `create_api_key()`, `delete_api_key()`

**Tableflow:**

- `create_tableflow_topic()`, `list_tableflow_topics()`

The server:

- Uses official Confluent Cloud APIs
- Reads credentials from `.env` file
- Handles errors and returns clear messages to Claude
- Supports multiple transport modes (stdio, HTTP, SSE)

### 3.2 Configuration in Claude Code

After running the provisioning script, add to your Claude Code MCP settings:

```json
{
  "mcpServers": {
    "confluent": {
      "command": "/Users/yourusername/.confluent-mcp/start-mcp-server.sh",
      "args": []
    }
  }
}
```

Or use npx directly:

```json
{
  "mcpServers": {
    "confluent": {
      "command": "npx",
      "args": ["-y", "@confluentinc/mcp-confluent", "-e", "/path/to/.env"]
    }
  }
}
```

Validate that from Claude you can call tools like:

- `list_topics`
- `get_topic_schema` on a test topic
- `execute_flink_sql` with a simple `SELECT 1`

---

## 4. What You Will Build in the Demo

### 4.1 Target schema: `customer_360_snapshot`

Flink table + backing topic (upsert):

- `customer_id` (logical PK)
- `full_name`
- `segment`, `risk_band`, `relationship_manager`
- `num_accounts`
- `products` (list of product types)
- `thirty_day_txn_count`
- `thirty_day_txn_amount`
- `thirty_day_avg_ticket`
- `preferred_channel`
- `last_login_ts`

### 4.2 Logical steps during live coding

1. **Data exploration with Claude + MCP**
   - Claude lists topics → inspects schemas → produces a mini data dictionary.
   - Claude proposes the `customer_360_snapshot` schema (columns + source).

2. **DDL in Flink**
   - Claude generates `CREATE TABLE` for the source tables (Kafka topics).
   - Claude generates `CREATE TABLE` for `customer_360_snapshot` (upsert-kafka).

3. **Aggregation/join logic**
   - Claude generates the `INSERT INTO customer_360_snapshot ... SELECT ...` that:
     - Joins customers + accounts + transactions + interactions.
     - Computes 30-day metrics per customer.

4. **Execution and debugging**
   - Run the statement in Flink SQL.
   - If it fails, copy the error to Claude so it can adjust the SQL.
   - Validate with `SELECT * FROM customer_360_snapshot LIMIT 10;`.

5. **(Optional) Tableflow**
   - Enable Tableflow on the `customer_360_snapshot` topic.
   - Briefly show how it would appear as an Iceberg/Delta table in the lakehouse.

---

## 5. Tools and Prerequisites

- **Confluent Cloud**
  - Kafka cluster, Schema Registry, Flink compute pool
  - (Optional) Tableflow + external storage (S3/ADLS)

- **Credentials**
  - Confluent Cloud API key/secret with permissions to:
    - Read topics and schemas
    - Run Flink SQL
    - (Optional) Configure Tableflow

- **MCP + Claude**
  - Claude Code installed and configured with MCP support.
  - Custom MCP server (`confluent-mcp`) reachable from the machine running Claude Code.

- **Python 3.8+**
  - Required for data generation scripts
  - Included dependencies: confluent-kafka, faker, python-dotenv

---

## 6. Practical Next Steps

### Quick Start (Automated)

```bash
# 1. Bootstrap complete environment
cd environment
./bootstrap.sh
# This will:
#   - Deploy Kafka cluster + Flink pool
#   - Provision MCP server
#   - Create topics
#   - Generate synthetic data (optional, prompted)

# 2. Test MCP integration in Claude Code
# Ask: "List my Kafka topics"
# Ask: "Sample records from corebank.customers"

# 3. Start building with Claude
# Ask Claude to:
#   - Explore the data and schemas
#   - Design the customer_360_snapshot schema
#   - Generate Flink SQL DDL and aggregations
```

### Manual Steps (if needed)

1. **Infrastructure**: `cd environment/terraform-confluent-aws && terraform apply`
2. **MCP Setup**: `cd environment/mcp-confluent && ./provision-confluent-mcp.sh`
3. **Generate Data**: `cd environment && ./generate-data.sh`
4. **Test**: Ask Claude to list topics and sample data

### Building the Customer 360 Data Product

Once infrastructure and data are ready:

1. **Explore** with Claude + MCP: "Analyze the schemas for all topics"
2. **Design**: Ask Claude to propose the `customer_360_snapshot` schema
3. **Generate DDL**: Have Claude create Flink SQL table definitions
4. **Build aggregations**: Claude generates the `INSERT INTO ... SELECT` query
5. **Debug**: Share any Flink errors with Claude for fixes
6. **Validate**: Run `SELECT * FROM customer_360_snapshot LIMIT 10`

See [environment/data-generation/README.md](environment/data-generation/README.md) for data details.
