# Customer 360 Real-Time Data Product with Confluent & Claude Code

> **Build a complete real-time Customer 360 data product using natural language with Claude Code + Confluent MCP**

This project demonstrates how to build a production-grade **Customer 360 real-time data product** on Confluent Cloud using **Apache Flink SQL** and **Claude Code with MCP (Model Context Protocol)** integration.

Instead of writing SQL manually, you'll use natural language prompts with Claude Code to explore data, design schemas, generate Flink SQL, and build streaming aggregations—all through conversation.

---

## 🎯 What is Customer 360?

**Customer 360** is a unified, real-time view of each customer that consolidates data from multiple systems into a single, queryable snapshot. For banks and financial services, this means:

### Business Value

- **Single Source of Truth**: All customer data in one place—profile, accounts, transactions, digital activity
- **Real-Time Insights**: Updates within seconds as customers interact across channels
- **Personalized Experiences**: Instant access to complete customer context for service reps, mobile apps, and marketing
- **Risk Management**: Real-time fraud detection and credit risk assessment
- **Cross-Sell Opportunities**: Identify product gaps based on customer segment and behavior

### Use Cases

1. **Customer Service**: Service reps see complete customer history instantly when answering calls
2. **Personalization**: Mobile apps show relevant offers based on current balance, segment, and recent activity
3. **Fraud Detection**: Real-time anomaly detection across transactions and digital behavior
4. **Marketing Campaigns**: Target customers based on product ownership, spending patterns, and engagement
5. **Risk Scoring**: Continuous credit risk assessment using transaction velocity and account balances

### Traditional Challenges

Building Customer 360 traditionally requires:
- Writing complex SQL joins across multiple databases
- Managing data pipelines and ETL processes
- Handling schema changes and data quality
- Maintaining low latency (<1 second) for real-time updates
- Expertise in stream processing frameworks

**This demo shows how Claude Code + Confluent MCP makes this dramatically simpler.**

---

## 🏗️ What You'll Build

A real-time **`c360_snapshot`** topic that aggregates data from 4 source topics:

### Source Data

| Topic | Data | Retention |
|-------|------|-----------|
| `corebank.customers` | Customer profiles (segment, risk, contact info) | Infinite (compacted) |
| `corebank.accounts` | Account details (balance, product type, status) | Infinite (compacted) |
| `corebank.transactions` | Transaction history (amount, merchant, channel) | 30 days |
| `digital.interactions.avro` | Digital events (login, transfer, payment) | 30 days |

### Output: c360_snapshot

A log-compacted topic with **37 fields per customer**, updated in real-time:

**Customer Profile** (8 fields)
- Name, segment (RETAIL/PREMIER/PRIVATE), risk band, relationship manager, contact info

**Account Summary** (10 fields)
- Total balance, account count, product ownership flags (checking, savings, investment, credit card, mortgage)

**Transaction Metrics** (8 fields)
- 30-day transaction count, total spent, total received, average amount, preferred channel

**Digital Engagement** (9 fields)
- Last 3 interactions (type, channel, timestamp), total logins, preferred digital channel

**Real-Time Updates**: As customers make transactions, open accounts, or use digital channels, their snapshot updates within seconds.

---

## ✅ Prerequisites

### Required Infrastructure

- [ ] **Confluent Cloud Account** ([Sign up free](https://www.confluent.io/get-started/))
- [ ] **Terraform** >= 1.5.0 ([Install](https://www.terraform.io/downloads))
- [ ] **Node.js** >= 18 (for Confluent MCP server) ([Install](https://nodejs.org/))
- [ ] **Claude Code** ([Download](https://claude.ai/code))
- [ ] **Python 3.8+** (for synthetic data generation)

### What Gets Deployed

The automated setup provisions:

✅ Confluent Cloud environment  
✅ Standard Kafka cluster (AWS eu-west-1, multi-zone)  
✅ Flink compute pool (serverless, 0-10 CFUs)  
✅ Service account with proper RBAC  
✅ Schema Registry  
✅ 4 source topics with AVRO schemas  
✅ Confluent MCP server configured  
✅ Synthetic Spanish banking data

---

## 🚀 Quick Start

### Step 1: Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd c360-livecoding

# Configure Confluent Cloud credentials
cd environment/terraform-confluent-aws
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Add your Confluent Cloud API key/secret
```

Get your API credentials at: https://confluent.cloud/settings/api-keys

### Step 2: Run Automated Setup

```bash
# Return to project root
cd ../..

# Run the startup script
./startup-demo.sh
```

**What happens:**
1. ✓ Detects first run and triggers bootstrap
2. ✓ Deploys Kafka cluster + Flink compute pool (Terraform)
3. ✓ Creates 4 source topics with AVRO schemas
4. ✓ Configures Confluent MCP server for Claude Code
5. ✓ Generates 2,000+ realistic Spanish banking records
6. ✓ Shows infrastructure summary and Claude prompts

### Step 3: Verify Setup

Setup already generated a project-level `.mcp.json` at the repo root (OAuth-based `@confluentinc/mcp-confluent`) — no manual settings edit needed for the Claude Code CLI. Open a **new** terminal/session in the repo (Claude Code only reads `.mcp.json` on session start) and ask:

```
Can you list all my Kafka topics?
```

**Expected response**: Claude lists all topics including `corebank.customers`, `corebank.accounts`, `corebank.transactions`, `digital.interactions`. The first tool call triggers an interactive Confluent Cloud OAuth login.

If you also use the VS Code extension or Claude Desktop app, run `./environment/configure-claude-mcp.sh --vscode` or `--desktop` — those read from global settings, not the project `.mcp.json`.

✅ **You're ready to build!**

---

## 💬 Implementation Guide: Building Customer 360 with Claude

This section shows the **actual conversation flow** used to build the Customer 360 data product. Copy these prompts into Claude Code and follow along.

### Phase 1: Data Discovery

**Prompt 1: Explore Topics**
```
Can you list all my Kafka topics?
```

Claude will show all topics in your cluster.

**Prompt 2: Identify C360 Topics**
```
I'm implementing a Banking Customer 360 use case. 
Can you list the related topics for me?
```

Claude identifies the 4 C360 topics: `corebank.customers`, `corebank.accounts`, `corebank.transactions`, `digital.interactions`.

**Prompt 3: Detailed Analysis**
```
Can you give me a detailed view of the core banking and digital 
banking topics? This should include topic config, schema, data 
quality, and data samples.
```

Claude will:
- Show topic configurations (partitions, retention, cleanup policy)
- Display complete AVRO schemas
- Consume and analyze sample messages
- Assess data quality (completeness, validity, consistency)
- Provide business insights from the data

### Phase 2: Schema Enforcement

**Prompt 4: Create AVRO Version**
```
Can you create a Flink query that replicates the digital.interactions 
topic with the same exact configuration but enforcing an AVRO schema? 
The query should replicate all new data that comes to the source topic.
```

Claude will:
1. Create `digital.interactions.avro` topic with AVRO schema
2. Generate Flink SQL to parse JSON and write AVRO
3. Deploy the streaming pipeline
4. Verify schema registration

**Result**: Real-time JSON → AVRO transformation using Flink.

### Phase 3: Data Governance

**Prompt 5: Tag Topics**
```
Can you tag all primary topics with 'source' and 'c360' tags?
```

Claude creates tags and applies them to source topics for data governance.

**Prompt 6: Tag Raw Data**
```
Can you tag digital.interactions as 'c360' and 'raw'?
```

Distinguishes raw JSON from schema-enforced version.

**Prompt 7: View by Tags**
```
Can you list my topics ordered by tag?
```

Shows topics organized by governance tags.

### Phase 4: Build C360 Snapshot

**Prompt 8: Design and Implement**
```
Can you build a Dataset Analysis of the c360+source tagged topics 
which includes topic configuration, data schema and sampling, business 
insights and recommendations for building a c360_snapshot topic using 
Flink that covers the c360 use case—real-time customer 360 data 
including the last 3 digital interactions?
```

Claude will:
1. Analyze all 4 source topics in detail
2. Design comprehensive `c360_snapshot` schema (37 fields)
3. Generate Flink SQL CREATE TABLE statement
4. Generate complex INSERT SELECT with:
   - Multi-way streaming joins
   - Account aggregations (SUM, COUNT, product flags)
   - ROW_NUMBER window function for Top-3 interactions
   - Login metrics aggregation
5. Provide implementation recommendations
6. Show expected business outcomes

**Prompt 9: Get Documentation**
```
Can you give me this as a markdown document?
```

Claude saves the complete analysis as `customer360_dataset_analysis.md`.

**Prompt 10: Deploy**
```
OK, let's go! Implement the c360 snapshot for me.
```

Claude will:
1. Create the `c360_snapshot` Kafka topic (12 partitions, log compacted, 90-day retention)
2. Deploy Flink CREATE TABLE statement
3. Deploy Flink INSERT SELECT statement (multi-way join + aggregations)
4. Verify deployment and data flow
5. Consume sample records to validate

### Phase 5: Verify and Analyze

**Prompt 11: List C360 Topics**
```
Can you list again my c360 related topics?
```

Shows all 6 topics: 4 source + 1 raw + 1 aggregated snapshot.

**Prompt 12: Detailed Analysis**
```
Can you give me detailed information about the new c360_snapshot topic?
```

Claude provides:
- Topic configuration (partitions, retention, compaction settings)
- Complete AVRO schema (37 fields)
- Sample data with real customer snapshots
- Data quality assessment
- Business insights from aggregated data
- Use cases and operational recommendations

### Phase 6: Tag the Data Product

**Prompt 13: Tag C360 Snapshot**
```
Can you tag the c360_snapshot topic with 'c360' and 'data_product' tags?
```

Claude applies governance tags to mark this as a curated data product in the c360 domain.

### Phase 7: Automate Future Deployments

**Prompt 14: Generate Terraform**
```
Perfect! Can you create a Terraform script so I can reproduce this 
new use case on different environments? This should be placed in a 
different folder.
```

Claude creates:
- Complete Terraform configuration in `environment/terraform-c360-snapshot/`
- Variables for all configurable parameters
- Comprehensive README with deployment guide
- QUICKSTART for 5-minute deployment
- Makefile for common operations
- terraform.tfvars.example template

**Result**: One-command deployment for dev/staging/prod environments.

---

## 🏛️ Architecture: What Was Built

### System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Source Systems (Spanish Bank)                 │
├─────────────────────────────────────────────────────────────────┤
│  Core Banking    │  Account System  │  Transaction  │  Digital  │
│  (Customers)     │  (Accounts)      │  Processing   │  Channels │
└────────┬─────────┴────────┬─────────┴──────┬────────┴─────┬─────┘
         │                  │                 │              │
         ▼                  ▼                 ▼              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Confluent Cloud - Kafka Cluster                  │
│                   (AWS eu-west-1, Multi-Zone)                    │
├─────────────────────────────────────────────────────────────────┤
│  📊 corebank.customers      │  📊 corebank.accounts            │
│     - Compacted              │     - Compacted                   │
│     - AVRO                   │     - AVRO                        │
│     - 200 customers          │     - 400+ accounts               │
├──────────────────────────────┼───────────────────────────────────┤
│  📊 corebank.transactions   │  📊 digital.interactions         │
│     - 30-day retention       │     - JSON (raw)                  │
│     - AVRO                   │     - 30-day retention            │
│     - 1,000+ transactions    │     - 800+ events                 │
├──────────────────────────────┴───────────────────────────────────┤
│  📊 digital.interactions.avro (Created by Flink)                │
│     - AVRO (schema enforced)                                     │
│     - Continuous JSON→AVRO transformation                        │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Apache Flink on Confluent Cloud                     │
│                  (Serverless Compute Pool)                       │
├─────────────────────────────────────────────────────────────────┤
│  🔄 Flink Statement: populate-c360-snapshot                     │
│                                                                  │
│  SELECT (Multi-way Streaming Join):                             │
│    ├─ corebank.customers (base)                                 │
│    ├─ LEFT JOIN corebank.accounts (GROUP BY customer_id)        │
│    │   └─ Aggregations: SUM(balance), COUNT(*), product flags   │
│    ├─ LEFT JOIN digital.interactions.avro (ROW_NUMBER Top-3)    │
│    │   └─ Last 3 interactions per customer                      │
│    └─ LEFT JOIN digital.interactions.avro (GROUP BY)            │
│        └─ Login metrics: COUNT(logins), MAX(last_login)         │
│                                                                  │
│  INSERT INTO c360_snapshot                                       │
│    - Real-time updates (<1 second latency)                      │
│    - Stateful aggregations with changelog mode                  │
│    - Auto-scaling (0-10 CFUs based on load)                     │
└────────┬────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    🎯 c360_snapshot Topic                        │
│                   (Real-Time Customer 360)                       │
├─────────────────────────────────────────────────────────────────┤
│  Configuration:                                                  │
│    - 12 partitions (for high throughput)                        │
│    - Log compacted (latest state per customer)                  │
│    - 90-day retention                                            │
│    - AVRO schema (37 fields)                                     │
│    - Schema ID: 100010 (value), 100011 (key)                    │
│                                                                  │
│  Data per Customer:                                              │
│    ✓ Profile: name, segment, risk, contact                      │
│    ✓ Accounts: balance, count, product flags                    │
│    ✓ Transactions: 30d metrics, spending patterns               │
│    ✓ Digital: last 3 interactions, login counts                 │
└────────┬────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Consumer Applications                         │
├─────────────────────────────────────────────────────────────────┤
│  📱 Mobile App        │  👤 Customer Service  │  🤖 ML Models   │
│     - Personalization │     - 360° view       │     - Churn     │
│     - Real-time offers│     - Context pop     │     - Fraud     │
│                       │                       │     - Scoring   │
│  📊 Analytics         │  🎯 Marketing         │  ⚠️  Alerts     │
│     - Dashboards      │     - Segmentation    │     - Risk      │
│     - Reporting       │     - Campaigns       │     - Anomalies │
└─────────────────────────────────────────────────────────────────┘
```

### Data Governance (Tags)

```
Tags Applied:
├─ c360 (6 topics)
│  ├─ source (4 topics)
│  │  ├─ corebank.customers
│  │  ├─ corebank.accounts
│  │  ├─ corebank.transactions
│  │  └─ digital.interactions.avro
│  ├─ raw (1 topic)
│  │  └─ digital.interactions
│  └─ aggregated (1 topic)
│     └─ c360_snapshot
```

### Schema Registry

```
Registered Schemas:
├─ corebank.customers-value (Schema ID: 100001)
├─ corebank.accounts-value (Schema ID: 100002)
├─ corebank.transactions-value (Schema ID: 100003)
├─ digital.interactions.avro-key (Schema ID: 100008)
├─ digital.interactions.avro-value (Schema ID: 100009)
├─ c360_snapshot-key (Schema ID: 100011)
└─ c360_snapshot-value (Schema ID: 100010)
```

### Flink Statements

1. **create-digital-interactions-avro-table**
   - Status: COMPLETED
   - Creates AVRO table definition

2. **replicate-digital-interactions-avro**
   - Status: RUNNING
   - Continuous JSON → AVRO transformation
   - Reads: `digital.interactions` (JSON)
   - Writes: `digital.interactions.avro` (AVRO)

3. **create-c360-snapshot-table**
   - Status: COMPLETED
   - Creates c360_snapshot table with 37 fields

4. **populate-c360-snapshot**
   - Status: RUNNING
   - Multi-way streaming join
   - Real-time aggregations
   - Updates customer snapshots continuously

---

## 🔧 Troubleshooting

### Setup Issues

#### Problem: Terraform fails with authentication error

**Symptoms**:
```
Error: error authorizing Confluent Cloud Client
```

**Solution**:
1. Verify API credentials in `environment/terraform-confluent-aws/terraform.tfvars`
2. Ensure they are organization-level API keys (not cluster-scoped)
3. Generate new keys at: https://confluent.cloud/settings/api-keys

#### Problem: Claude Code doesn't see Confluent MCP tools

**Symptoms**:
- Claude says "I don't have access to Confluent tools"
- Tool list doesn't include `list-topics`, `consume-messages`, etc.

**Solution**:
1. Confirm `.mcp.json` exists at the repo root and points at `@confluentinc/mcp-confluent`
2. Open a **new** terminal/session — Claude Code only reads `.mcp.json` on session start, it won't pick up changes in an already-running window
3. Run: `cd environment && ./reconfigure-mcp.sh` to regenerate `.mcp.json` and reset stale approval state
4. Trigger a tool call (e.g. "list my Kafka topics") to go through the Confluent Cloud OAuth login if you haven't already

#### Problem: Synthetic data generation fails

**Symptoms**:
```
Error: Topic does not exist
```

**Solution**:
1. Ensure infrastructure is deployed: `cd environment/terraform-confluent-aws && terraform state list`
2. Verify topics exist: Ask Claude "Can you list all my Kafka topics?"
3. Check credentials in `environment/data-generation/.env`
4. Regenerate: `cd environment && ./generate-data.sh`

### Runtime Issues

#### Problem: Flink statement stays in PENDING

**Symptoms**:
- Flink statement created but never reaches RUNNING
- No data flowing to c360_snapshot

**Solution**:
1. Check statement status: `confluent flink statement describe <statement-name> --compute-pool <pool-id>`
2. Look for validation errors in status detail
3. Verify source topics have data: Ask Claude to consume from source topics
4. Check Flink compute pool has available CFUs
5. Delete and recreate statement if needed

#### Problem: c360_snapshot has no data

**Symptoms**:
- Topic exists but consuming returns empty or zeros

**Root Cause**: Flink join is building state

**Solution**:
1. Wait for state to build (Flink stateful joins need initialization time)
2. Check Flink statement is RUNNING (not FAILED)
3. Verify source topics have data
4. Ask Claude: "Can you consume messages from corebank.customers?"
5. If source topics empty, regenerate data: `cd environment && ./generate-data.sh`

#### Problem: Schema evolution errors

**Symptoms**:
```
Schema is incompatible with previous version
```

**Solution**:
1. Check Schema Registry compatibility mode
2. Use forward/backward compatible changes only
3. Or delete schema and recreate (non-production only):
   ```bash
   confluent schema-registry schema delete --subject <subject> --version all --permanent
   ```

### Claude + MCP Issues

#### Problem: Claude generates incorrect Flink SQL

**Symptoms**:
- Flink statement fails with SQL syntax error
- Column names don't match schema

**Solution**:
1. Copy the FULL error message to Claude
2. Ask: "Can you fix this Flink SQL error: <paste error>"
3. Claude will analyze and provide corrected SQL
4. Delete failed statement and recreate with fixed SQL

#### Problem: Tags aren't being created

**Symptoms**:
- Claude says tools unavailable or permission denied

**Solution**:
1. Ensure MCP is fully configured: `cd environment && ./reconfigure-mcp.sh`
2. Restart Claude Code
3. Verify tags work: Ask Claude "Can you create a tag called 'test'?"
4. Check service account has `EnvironmentAdmin` role

#### Problem: Consumer can't deserialize AVRO

**Symptoms**:
```
Error deserializing value
```

**Solution**:
1. Ensure using `--value-format avro` flag
2. Verify Schema Registry credentials are configured
3. Check schema ID in message matches registered schema
4. Ask Claude to consume with proper format: "Can you consume from c360_snapshot with AVRO deserialization?"

### Performance Issues

#### Problem: High Flink CFU consumption

**Symptoms**:
- Flink dashboard shows high CFU usage
- Resource utilization higher than expected

**Solution**:
1. Check for large state size (unbounded aggregations)
2. Add TTL to stateful operations
3. Reduce parallelism if over-provisioned
4. Optimize window sizes (use fixed windows instead of session windows)
5. Consider scaling down max CFUs in Terraform

#### Problem: Consumer lag on c360_snapshot

**Symptoms**:
- Downstream apps falling behind
- Lag metrics increasing

**Solution**:
1. Increase consumer parallelism
2. Check consumer application performance
3. Consider adding more partitions (requires recreation)
4. Use consumer groups for load distribution

---

## 🗑️ Cleanup

### Option 1: Clean Demo Resources (Keep Infrastructure)

Removes c360_snapshot and Flink statements, preserves infrastructure for reuse:

```bash
./cleanup-demo.sh
# Select Option 1

# Follow prompts to:
# - Delete Flink statements
# - Delete c360_snapshot topic
# - Remove tags (via Claude + MCP)
```

**What's kept:**
- ✓ Kafka cluster
- ✓ Flink compute pool
- ✓ Source topics (`corebank.*`, `digital.interactions`)
- ✓ MCP configuration

**Use this when**: You want to rebuild the data product fresh or try different designs.

### Option 2: Destroy Everything

Removes all Confluent Cloud resources:

```bash
./cleanup-demo.sh
# Select Option 2

# Confirms and runs:
terraform destroy
```

**What's deleted:**
- ✗ Kafka cluster
- ✗ Flink compute pool
- ✗ All topics (source + c360_snapshot)
- ✗ All schemas
- ✗ Service account

**What's kept:**
- ✓ Local project files (including `.mcp.json`, though it'll point at a deleted cluster until you re-provision and run `./reconfigure-mcp.sh`)

**Use this when**: Demo is complete and you want to remove all billable resources.

### Manual Cleanup (If Needed)

```bash
# Delete specific Flink statement
confluent flink statement delete <statement-name> --compute-pool <pool-id>

# Delete topic
confluent kafka topic delete c360_snapshot --cluster <cluster-id>

# Delete schema (hard delete)
confluent schema-registry schema delete --subject c360_snapshot-value --permanent
```

---

## 📚 Next Steps & Resources

### Extend the Use Case

Once c360_snapshot is running, try:

1. **Add More Metrics**
   - Last 10 transactions instead of just counts
   - Geographic analysis (ATM locations, merchant regions)
   - Velocity metrics (transactions per day, week, month)

2. **Build Downstream Applications**
   - Real-time dashboard with customer snapshots
   - ML model consuming c360_snapshot for churn prediction
   - Alerting on high-risk customer behavior

3. **Enable Tableflow**
   - Materialize c360_snapshot to Iceberg/Delta tables
   - Query with Athena, Redshift Spectrum, or Databricks
   - Join with data warehouse for historical analysis

4. **Multi-Region**
   - Deploy Terraform config to different regions
   - Set up cluster linking for DR
   - Build global customer view

### Learn More

**Project Documentation**:
- [Terraform Infrastructure Guide](environment/terraform-confluent-aws/README.md)
- [C360 Snapshot Terraform](environment/terraform-c360-snapshot/README.md)
- [Data Generation Guide](environment/data-generation/README.md)
- [Confluent MCP Tools Reference](environment/MCP_TOOLS_REFERENCE.md)
- [Complete Dataset Analysis](customer360_dataset_analysis.md)

**Confluent Resources**:
- [Flink SQL Reference](https://docs.confluent.io/cloud/current/flink/reference/overview.html)
- [Stream Processing Patterns](https://developer.confluent.io/patterns/)
- [Customer 360 Reference Architecture](https://www.confluent.io/resources/customer-360/)

**MCP & Claude**:
- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [Confluent MCP Server](https://github.com/confluentinc/mcp-confluent)
- [Claude Code Documentation](https://claude.ai/code)

### Community & Support

- **Confluent Community**: [forum.confluent.io](https://forum.confluent.io/)
- **GitHub Issues**: Report bugs or request features
- **Confluent Cloud Support**: Available with paid plans

---

## 📄 License

This project is provided as a demonstration and learning resource.

---

## 🤝 Contributing

Contributions welcome! To improve this demo:

1. Fork the repository
2. Create a feature branch
3. Add improvements (new prompts, better error handling, additional use cases)
4. Update documentation
5. Submit a pull request

**Areas for contribution**:
- Additional Customer 360 metrics
- Multi-language support (currently Spanish)
- Alternative cloud providers (Azure, GCP)
- Performance optimizations
- New Claude prompts and workflows

---

## 📞 Getting Help

**Quick Help**:
1. Check [Troubleshooting](#-troubleshooting) section above
2. Review logs: `./startup-demo.sh` provides diagnostic information
3. Ask Claude! Paste error messages and ask for help

**Issues**:
- Infrastructure: Check Terraform state and Confluent Cloud console
- MCP: Verify `.mcp.json` exists at the repo root and re-run `environment/reconfigure-mcp.sh` if stale
- Flink: Check statement status and error details
- Data: Regenerate synthetic data with `./generate-data.sh`

**Still stuck?**
- Open a GitHub issue with details (error messages, logs, steps to reproduce)
- Contact your Confluent Solutions Engineer
- Visit [Confluent Community](https://forum.confluent.io/)

---

**Built with**: Confluent Cloud + Apache Flink + Claude Code + MCP  
**Total Lines of Code**: ~0 (built entirely with natural language prompts!)
