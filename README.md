# Customer 360 Live Coding Workshop – Implementation Notes

Minimal checklist to implement the live demo: **Customer 360 data product on Confluent DSP using Flink + Claude Code (via MCP)**.

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

### 2.1 Kafka & Schema Registry

Create a demo environment with:

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

- Create a **compute pool** and **Flink SQL workspace** in Confluent Cloud.
- Verify you can:
  - Run `SELECT * FROM <table> LIMIT 10;` using simple dynamic tables.
  - Create tables and jobs from the Flink console.

### 2.3 (Optional) Tableflow

- Configure integration with S3/ADLS if you want to show materialization:
  - A demo bucket/account.
  - At least one topic enabled with Tableflow to confirm it works.

---

## 3. MCP + Claude Code

### 3.1 MCP Server (Confluent MCP)

Implement an MCP server (e.g. `confluent-mcp`) that uses Confluent Cloud APIs and exposes at least these tools:

**Kafka / schemas:**

- `list_topics()`
- `get_topic_schema(topic)`
- `sample_records(topic, limit)`

**Flink:**

- `run_flink_sql(statement)`
- (Optional) `list_flink_tables()`, `describe_flink_table(name)`

The server should:

- Read Confluent Cloud credentials (API key/secret, org/env/cluster IDs).
- Handle errors and return clear messages to Claude.

### 3.2 Configuration in Claude Code

In Claude Code’s configuration file, add something like:

  ```json
 {
"mcpServers": {
"confluent": {
"command": "confluent-mcp",
"args": ["--config", "mcp-config.yaml"]
}
}
}
  ```

Validate that from Claude you can call, for example:

- `confluent.list_topics`
- `confluent.sample_records` on a test topic
- `confluent.run_flink_sql` with a simple `SELECT 1`

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
