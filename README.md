# Customer 360 Live Coding Workshop – Implementation Notes

Minimal checklist to implement the live demo: **Customer 360 data product on Confluent DSP using Flink + Claude Code (via MCP)**.

## 📊 Current Status

**✅ Completed:**

- Infrastructure provisioned (Terraform)
- Confluent MCP server configured and working
- Kafka cluster running: `customer-360-cluster` (lkc-jq5kwq, AWS eu-west-1)
- Flink compute pool ready
- Environment protection (.gitignore consolidated)

**🚧 In Progress:**

- Creating Kafka topics and schemas
- Generating synthetic data
- Building Flink SQL transformations

**⏳ To Do:**

- Create `customer_360_snapshot` data product
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

After infrastructure is provisioned, create topics and schemas:

- **Kafka topics** (example names):
  - `corebank.customers`
  - `corebank.accounts`
  - `corebank.transactions`
  - `digital.interactions`

- **Schemas** registered in Schema Registry:
  - `customers`: `customer_id`, `name`, `segment`, `risk_band`, `relationship_manager`, ...
  - `accounts`: `account_id`, `customer_id`, `product_type`, `status`, ...
  - `transactions`: `txn_id`, `account_id`, `amount`, `currency`, `mcc`, `channel`, `ts`, ...
  - `interactions`: `event_id`, `customer_id`, `event_type`, `ts`, `channel`, ...

Populate topics with **realistic synthetic data**.

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

- **Misc utilities**
  - Optional Kafka/CLI client for debugging.
  - Synthetic data generator (your own script or existing tools).

---

## 6. Practical Next Steps

1. Stand up the minimum Confluent environment (topics + Flink).
2. Implement and test the MCP server with **one simple flow** (list topics + run a trivial `SELECT` in Flink).
3. Once that works, add:
   - Customer 360 SQL
   - Iteration with Claude
   - (Optional) Tableflow

This should be enough to remind you **what to build** and **which pieces you need** when you start the actual implementation.
