# Customer 360 Real-Time Data Product with Confluent & an AI Coding Assistant

> **Build a complete real-time Customer 360 data product using natural language with an AI coding assistant + Confluent MCP**

This project demonstrates how to build a production-grade **Customer 360 real-time data product** on Confluent Cloud using **Apache Flink SQL** and an **AI coding assistant connected through MCP (Model Context Protocol)** — Claude Code, GitHub Copilot or IBM Bob.

Instead of writing SQL manually, you'll use natural language prompts with your assistant to explore data, design schemas, generate Flink SQL, and build streaming aggregations—all through conversation.

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

**This demo shows how an AI coding assistant + Confluent MCP makes this dramatically simpler.**

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

## 🧰 Before You Start

**You need:** a Confluent Cloud account and an AI coding assistant connected to Confluent through MCP — [Claude Code](https://claude.ai/code), VS Code with GitHub Copilot, or IBM Bob. The prompts in this guide are the same for all three.

**Set up the environment first:** follow the **[Build Guide](BUILD_GUIDE.md)** — it covers prerequisites, building, connecting your assistant, and teardown.

Once it's built, open a **new** session in your assistant and ask:

```
Can you list all my Kafka topics?
```

**Expected response**: the assistant lists all topics including `corebank.customers`, `corebank.accounts`, `corebank.transactions` and `digital.interactions`. The first time, you'll be asked to log in with your Confluent account (once per assistant) — do this before presenting. If you belong to several organizations, sign in to the one that owns the demo environment.

✅ **You're ready to build!**

---

## 💬 Implementation Guide: Building Customer 360 with Your AI Assistant

This section shows the **actual conversation flow** used to build the Customer 360 data product. Copy these prompts into your assistant (Claude Code, GitHub Copilot or IBM Bob) and follow along. They are the same for all three.

### Phase 1: Data Discovery

**Prompt 1: Explore Topics**
```
Can you list all my Kafka topics?
```

The assistant will show all topics in your cluster.

**Prompt 2: Identify C360 Topics**
```
I'm implementing a Banking Customer 360 use case. 
Can you list the related topics for me?
```

The assistant identifies the 4 C360 topics: `corebank.customers`, `corebank.accounts`, `corebank.transactions`, `digital.interactions`.

**Prompt 3: Detailed Analysis**
```
Can you give me a detailed view of the core banking and digital 
banking topics? This should include topic config, schema, data 
quality, and data samples.
```

The assistant will:
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

The assistant will:
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

The assistant creates tags and applies them to source topics for data governance.

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

The assistant will:
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

The assistant saves the complete analysis as `customer360_dataset_analysis.md`.

> A finished example of this file is included: [C360_DATASET_ANALYSIS_example.md](C360_DATASET_ANALYSIS_example.md). Use it as a reference for what a good result looks like, or as a fallback if the live generation goes sideways.

**Prompt 10: Deploy**
```
OK, let's go! Implement the c360 snapshot for me.
```

The assistant will:
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

The assistant provides:
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

The assistant applies governance tags to mark this as a curated data product in the c360 domain.

### Phase 7: Automate Future Deployments

**Prompt 14: Generate Terraform**
```
Perfect! Can you create a Terraform script so I can reproduce this 
new use case on different environments? This should be placed in a 
different folder.
```

The assistant creates:
- Complete Terraform configuration in a new `terraform-c360-snapshot/` folder (generated by this step)
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

> Problems building the environment or connecting your assistant? See the [Build Guide](BUILD_GUIDE.md#8-troubleshooting-the-build).

### Runtime Issues

#### Problem: Flink statement stays in PENDING

**Symptoms**:
- Flink statement created but never reaches RUNNING
- No data flowing to c360_snapshot

**Solution**:
1. Check statement status: `confluent flink statement describe <statement-name> --compute-pool <pool-id>`
2. Look for validation errors in status detail
3. Verify source topics have data: Ask your assistant to consume from source topics
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
4. Ask your assistant: "Can you consume messages from corebank.customers?"
5. If source topics are empty, regenerate data: `make data`

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

### Assistant + MCP Issues

#### Problem: The assistant generates incorrect Flink SQL

**Symptoms**:
- Flink statement fails with SQL syntax error
- Column names don't match schema

**Solution**:
1. Copy the FULL error message to your assistant
2. Ask: "Can you fix this Flink SQL error: <paste error>"
3. The assistant will analyze and provide corrected SQL
4. Delete failed statement and recreate with fixed SQL

#### Problem: Tags aren't being created

**Symptoms**:
- The assistant says tools unavailable or permission denied

**Solution**:
1. Ensure MCP is fully configured: `make ai-status`, then re-run the `make ai-*` target for your assistant
2. Restart your assistant (start a new session)
3. Verify tags work: Ask your assistant "Can you create a tag called 'test'?"
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
4. Ask your assistant to consume with proper format: "Can you consume from c360_snapshot with AVRO deserialization?"

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

## 🗑️ Resetting and Tearing Down

| When | Run | What happens |
| --- | --- | --- |
| Run the demo again | `make reset` | Deletes the Flink statements and every topic and schema the session built. Keeps the cluster, Flink pool and source topics. Preview first with `make reset-plan`. |
| Finished with the demo | `make down` | Destroys everything (you type `destroy` to confirm) so nothing keeps billing. |

Tags your assistant created are removed by asking it: *"Delete the tags c360, source and data_product."* Full details are in the [Build Guide](BUILD_GUIDE.md#6-operating-the-environment).

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
   - Materialize c360_snapshot to Iceberg/Delta tables (`make tableflow-enable`)
   - Query with Athena, Redshift Spectrum, or Databricks
   - Join with data warehouse for historical analysis

4. **Multi-Region**
   - Deploy Terraform config to different regions
   - Set up cluster linking for DR
   - Build global customer view

### Learn More

**Project Documentation**:
- [Build Guide](BUILD_GUIDE.md) — build, operate and tear down the environment
- [Terraform Infrastructure Guide](environment/terraform-confluent-aws/README.md)
- [Data Generation Guide](environment/data-generation/README.md)
- [Confluent MCP Tools Reference](environment/MCP_TOOLS_REFERENCE.md)
- [Example Dataset Analysis](C360_DATASET_ANALYSIS_example.md)
- [Session slides](C360_SESSION_SLIDES.html)

**Confluent Resources**:
- [Flink SQL Reference](https://docs.confluent.io/cloud/current/flink/reference/overview.html)
- [Stream Processing Patterns](https://developer.confluent.io/patterns/)
- [Customer 360 Reference Architecture](https://www.confluent.io/resources/customer-360/)

**MCP & AI Assistants**:
- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [Confluent MCP Server](https://github.com/confluentinc/mcp-confluent)
- [Claude Code Documentation](https://claude.ai/code) (GitHub Copilot and IBM Bob: see their own MCP documentation)

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
- New prompts and workflows, tested with each assistant

---

## 📞 Getting Help

**Quick Help**:
1. Check [Troubleshooting](#-troubleshooting) above, or the [Build Guide](BUILD_GUIDE.md#8-troubleshooting-the-build) for setup problems
2. `make status` shows the environment, source topics and assistant wiring in one view
3. Ask your assistant! Paste error messages and ask for help

**Issues**:
- Infrastructure: `make info`, then check Terraform state and the Confluent Cloud console
- MCP: `make ai-status`, then re-run `make ai-claude` / `make ai-copilot` / `make ai-bob`
- Flink: Check statement status and error details
- Data: Regenerate synthetic data with `make data`

**Still stuck?**
- Open a GitHub issue with details (error messages, logs, steps to reproduce)
- Contact your Confluent Solutions Engineer
- Visit [Confluent Community](https://forum.confluent.io/)

---

**Built with**: Confluent Cloud + Apache Flink + MCP + an AI coding assistant (Claude Code, GitHub Copilot or IBM Bob)  
**Total Lines of Code**: ~0 (built entirely with natural language prompts!)
