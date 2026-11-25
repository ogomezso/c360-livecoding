# Customer 360 Real-Time Data Product with Confluent & an AI Coding Assistant

> **Build a complete real-time Customer 360 data product using natural language with an AI coding assistant + Confluent MCP**

This project demonstrates how to build a production-grade **Customer 360 real-time data product** on Confluent Cloud using **Apache Flink SQL** and an **AI coding assistant connected through MCP (Model Context Protocol)** — Claude Code, GitHub Copilot or IBM Bob.

Instead of writing SQL manually, you'll use natural language prompts with your assistant to explore data, design schemas, generate Flink SQL, and build streaming aggregations—all through conversation.

---

## 🎯 What is Customer 360?

**Customer 360** is a unified, real-time view of each customer that consolidates data from multiple systems into a single, queryable snapshot. For banks and financial services, this means:

### Business Value

- **Single Source of Truth**: All customer data in one place—profile, accounts, transactions, digital activity
- **Real-Time Insights**: Raw events are queryable within about a second; the aggregated 360 view follows within about a minute (see *Two speeds* in Phase 10)
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

**Real-Time Updates**: As customers make transactions, open accounts, or use digital channels, their snapshot updates within about a minute (a Flink statement commits its output roughly once a minute), and the raw events are queryable within about a second — see *Two speeds* in Phase 10.

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

### The demo flow at a glance

| Step | What you show | Where |
|---|---|---|
| 1 | Build the Customer 360 use case just by prompting, and what the prompts actually create | Phases 1–6 (Prompt 11 starts the Lightning Table setup, which takes minutes) |
| 2 | Switch on Tableflow (Console UI or prompt) on the live table, then read the Iceberg table with Trino through Polaris — on the pre-built twin, already materialized: the analytical state *today* | Phases 7–8 |
| 3 | Make something happen: new interactions and purchases arrive — written to the source topics and, by a plain producer, straight to a live feed | Phase 9 |
| 4 | See it change in real time with Lightning queries: the Console or CLI, the live front end, and **asking your assistant in natural language** — at two speeds: the raw feed in about a second, the Flink-built Customer 360 in up to a minute | Phase 10 |
| 5 | See the same change reach the analytical side through Tableflow, Polaris and Trino | Phase 11 |

### The pre-built twin: why there are two Customer 360 tables

Steps 1 and 2–5 use **two tables on purpose**, like a cooking show: you cook one live, and one is ready from the oven.

| | `c360_snapshot` | `c360_snapshot_prebuilt` |
|---|---|---|
| Built | **live**, by your assistant (Phases 1–4) | at **build time**, from the SQL in `environment/prebuilt/` |
| Used for | showing *how* it is built; you also switch Tableflow and Lightning on for it live | steps 2–5: Trino, Lightning, the live front end — already warm |
| Why | the GenAI part of the story | the live result is non-deterministic and Tableflow and Lightning need minutes to warm up; the twin has fixed columns and is ready now |

Same logic, same shape (200 rows, one per customer); the twin already has Tableflow, Polaris/Trino and a Lightning Table on it. `make reset` leaves it alone. Tell the audience it is the one prepared earlier. If the live build ever goes sideways, the demo carries on with the twin.

**A second prepared piece: the live feed.** The build also creates `c360_live_activity`, a small Avro topic with a Lightning Table on it, for the *fast* half of the real-time demo. It is **not** a copy of the Customer 360 table: it holds one row per raw event (a digital interaction or a card purchase, with the customer's name and segment), written by a plain producer when you press the button or run `make demo-changes`. Because no Flink statement sits in its path it is queryable about a second later, while the Flink-built Customer 360 table needs up to a minute — that contrast is the point of Phase 10. `make reset` leaves it alone too.

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
The query should replicate all new and exisitng data on the source topic.
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

**Prompt 11: Enable Lightning Queries**
```
Can you enable a Lightning Table on the c360_snapshot topic, so I can
query its current state with low-latency SQL?
```

The assistant will:
1. Enable a Lightning Table for `c360_snapshot` (the environment already has the read-only identity and the live front end; the pre-built twin already has its own table)
2. Tell you it takes **several minutes** and how to check it

Carry on with Phases 5–6 while it sets up. The demo's real-time half runs on the pre-built twin, so you never wait for this one; it is the live proof that enabling takes a prompt. Because `c360_snapshot` has a primary key, the Lightning Table keeps the *current row per customer* — the same shape as the topic.

### Phase 5: Verify and Analyze

**Prompt 12: List C360 Topics**
```
Can you list again my c360 related topics?
```

Shows all 6 topics: 4 source + 1 raw + 1 aggregated snapshot.

**Prompt 13: Detailed Analysis**
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

**Prompt 14: Tag C360 Snapshot**
```
Can you tag the c360_snapshot topic with 'c360' and 'data_product' tags?
```

The assistant applies governance tags to mark this as a curated data product in the c360 domain.

### Phase 7: Materialize the Data Product with Tableflow

The environment was prepared with storage for Tableflow (an S3 bucket and the access Confluent needs to write to it — see the [Build Guide](BUILD_GUIDE.md)), so all that is left is to switch it on.

> **The twin is already done.** `c360_snapshot_prebuilt` has had Tableflow on since the build, so its Iceberg table is committed and queryable now. Enable Tableflow on the live `c360_snapshot` below to show *how*, and run the Trino questions of Phase 8 on the twin while the live one materializes.

**Prefer the Console?** The same step in the UI: *Environments → your environment → cluster → Topics → `c360_snapshot` → Enable Tableflow* → format **Iceberg** → **Use your own storage** → pick the provider integration `customer-360-tableflow-integration` and the bucket (`make tableflow-status` shows both). Labels may vary slightly between Console releases. Polaris and Trino are already connected to this catalog by the build, so the table becomes queryable as soon as Tableflow has committed.

**Prompt 15: Enable Tableflow**
```
Can you enable Tableflow on the c360_snapshot topic in Iceberg format,
using the storage already prepared for this environment?
```

The assistant will:
1. Find the S3 bucket and provider integration prepared for this environment
2. Enable Tableflow on `c360_snapshot` as an Iceberg table in that bucket
3. Confirm the topic is enabled and materializing

**Prompt 16: Check the Result**
```
Can you show me the Tableflow status of c360_snapshot and where
the Iceberg table is stored?
```

The assistant reports the Tableflow status and the S3 location of the table.

**Result**: the real-time snapshot is now also an open-format table in your own bucket, kept up to date from the topic. Because `c360_snapshot` has a primary key it is materialized in *upsert* mode — the latest state per customer — which you can query from Athena, Trino, Snowflake or Databricks. The first snapshot can take a few minutes to appear.

### Phase 8: Ask Business Questions of the Iceberg Table

The environment also includes an open-source lakehouse (Apache Polaris and Trino on your laptop — see the [Build Guide](BUILD_GUIDE.md) §4.7), so the Tableflow output can be queried with plain SQL by anyone, with no Confluent tooling on the read side. This phase tells the Customer 360 story in natural language: each prompt is one business question, answered from `c360_snapshot` with a single query and no joins. Tableflow commits to Iceberg in batches of about 5 minutes, so start a few minutes after Phase 7.

**Prompt 17: Discover the Lakehouse**
```
Using Trino, which tables can you see in the Iceberg catalog,
and how many customers are in the Customer 360 table?
```

The assistant lists the tables — `c360_snapshot_prebuilt`, plus `c360_snapshot` once its Tableflow has committed — and reports 200 customers for the Customer 360 table (it knows to use the pre-built twin). Polaris hands Trino short-lived, read-only storage access, so Trino holds no AWS keys.

**Prompt 18: The 360 View**
```
Show me the full picture of our three most valuable customers in each
segment: profile, products, balances, spend and their last three digital actions.
```

One row per customer carries everything that used to need four topics. Customers with no digital activity show dashes — that is a finding, not an error.

**Prompt 19: Segments and Risk**
```
How big is each customer segment, how deep is the relationship
(accounts and balances), and how risky is it?
```

**Prompt 20: Cross-Sell**
```
Which customers hold a current account with a healthy balance but no
savings or investment product? Rank them by balance.
```

**Prompt 21: Where to Call First**
```
Which PREMIER or PRIVATE customers are high-risk or have debts far above
what they hold? Who is their relationship manager?
```

**Prompt 22: Re-Engagement**
```
Which customers with real balances have never used our digital channels?
```

**Prompt 23: Real-Time Activity**
```
Who interacted with us most recently, and what exactly did they do?
```

Note the customer at the top and when they were last seen.

### Phase 9: Make Something Happen

Run this in a terminal — or press **Make something happen** in the live view (Phase 10):

```bash
make demo-changes
```

It writes a small burst of new data: for the three richest customers who have never used our digital channels it adds a mobile `LOGIN → VIEW_BALANCE → PAYMENT` session and one card purchase, all timestamped now (`make demo-changes CHANGES=5` for more customers, `DRY_RUN=1` to preview who would be picked). Those are exactly the customers at the top of the re-engagement list from Prompt 22. Each run picks the next inactive customers, so you can repeat it.

Every new event is written **twice**: to the source topics, which the Flink statement turns into the Customer 360 table, and — by a plain producer, with no Flink in between — straight to the live-feed topic `c360_live_activity`. That is on purpose: the demo shows **two speeds**. The raw feed is queryable in about a second; the Customer 360 table follows when Flink commits (up to about a minute); the Iceberg table has it with the next Tableflow commit (a few minutes). First, see it where it is instant.

### Phase 10: Real Time with Lightning Queries

A Lightning Table answers plain SQL — key lookups, filters, `ORDER BY`, `LIMIT` — with no consumer to write and no database to run. It queries **one** table (no joins or aggregates), which is why the data product was precomputed into `c360_snapshot`. Make sure the Lightning Tables are ready: `make lightning-status` (the build enables two: the live feed and the pre-built twin; Prompt 11 adds `c360_snapshot`).

**Two speeds — and the trade-off we accept.** How fresh a Lightning Table is depends on who writes its topic:

| Table | Written by | A change is queryable after | Why |
|---|---|---|---|
| `c360_live_activity` — the live feed, one row per event | a plain producer | **about 1 second** (Confluent's target: under 100 ms once committed; about 1 s on a quiet topic) | no Flink in the path |
| `c360_snapshot_prebuilt` — the Customer 360 table, one row per customer | a **Flink statement** | **up to about 1 minute** (0–60 s; every extra Flink statement in a chain adds up to another minute) | Confluent Cloud Flink writes to Kafka in transactions that commit about once a minute (**exactly-once**), and Lightning reads only committed data |
| the Iceberg table (Trino) | Tableflow | a few minutes | Tableflow publishes about every 5 minutes |

The trade-off: the Customer 360 table is **exactly-once and aggregated** (one row per customer, joined from four topics), so it is a minute behind; the feed is **raw and immediate** but has no aggregation and, because Lightning cannot join, only carries the customer's name and segment, not their balances. Making the Flink lane faster would mean giving up exactly-once for Flink-to-Flink hops (`'kafka.consumer.isolation-level' = 'read-uncommitted'`), which allows duplicates — and it would not change what Lightning sees, since Lightning reads committed data. A shorter Flink checkpoint interval is on Confluent's roadmap but is not available today. Use the minute to talk through the pipeline.

**Four ways to ask the same question**

| Way | Who it is for | How |
|---|---|---|
| **The Console** | you, on stage | the SQL editor of the `c360_snapshot_prebuilt` topic's Lightning Table |
| **A terminal** | scripts and automation | `make lightning-query LSQL='…'` (the Query API) |
| **The live front end** | an application, querying over **JDBC** | `make c360-live` |
| **Natural language** | you and AI agents | just ask your assistant — see below |

1. **In the Console.** Open the `c360_live_activity` topic and use its Lightning Table SQL editor (labels may vary slightly between releases). Run, press the button (or `make demo-changes`), run again a second later — the new events are there:
   ```sql
   SELECT full_name, segment, kind, action, channel, amount, ts
   FROM c360_live_activity ORDER BY ts DESC LIMIT 8
   ```
   Then do the same on the Customer 360 table of `c360_snapshot_prebuilt` and watch it **take up to a minute to catch up** — that is the second speed:
   ```sql
   SELECT full_name, segment, interaction_1_type, interaction_1_channel, interaction_1_ts
   FROM c360_snapshot_prebuilt WHERE interaction_1_ts IS NOT NULL ORDER BY interaction_1_ts DESC LIMIT 5
   ```
2. **From a terminal** (the same SQL through the Query API; newer Confluent CLI versions also offer `confluent lightning query`):
   ```bash
   make lightning-query LSQL='SELECT full_name, segment, interaction_1_type, interaction_1_ts FROM c360_snapshot_prebuilt WHERE interaction_1_ts IS NOT NULL ORDER BY interaction_1_ts DESC LIMIT 5'
   ```
3. **In the live front end** — a Java-driver-based application that runs exactly these queries every second **over JDBC** (the Confluent JDBC driver, `jdbc:confluent:lightning://`) and shows the Customer 360 changing:
   ```bash
   make c360-live        # opens http://localhost:8088
   ```
   Press **Make something happen**: a progress box tracks the **two lanes**. The *Live event feed* at the top fills in about a second after the events are produced ("visible 1.2 s after the event"); the *Customer 360* panels follow when Flink commits — the three customers move to the top of *Customer 360 — who touched our digital channels last* with their new actions and last purchase, and leave *Never used digital*. **Allow up to a minute or two for that second lane:** Confluent Cloud Flink commits its Kafka transactions about once a minute and Lightning reads only committed data, so a change made by a Flink statement (the Customer 360 table) shows up within ~60 s — use that time to talk through the pipeline. Click a row for the customer card. The page shows the SQL it sends and the query latency. It runs on the same local cluster as Trino with a **read-only** identity (the Global API key is the JDBC user and password); only the button uses a write credential. Any other JDBC client — DBeaver, DataGrip, sqlline — connects the same way (Build Guide §4.8).

#### Ask in natural language — in real time

The build also gives your assistant a **second MCP server, `confluent-rtce`**, next to the `confluent` one — in Claude Code, GitHub Copilot and IBM Bob alike. It is the *Real-Time Context Engine*, the MCP interface to the same Lightning Table (see the [Build Guide](BUILD_GUIDE.md) §4.8 for the naming). You do nothing special: ask in plain language and the assistant

1. calls `listTopics` to see which tables can be queried in real time,
2. calls `getMetadata` to learn the columns of the Customer 360 table,
3. writes the SQL itself and calls `queryData` (at most 200 rows, 20 s timeout),

and answers with data that is **seconds old**. It signs in with a read-only key, so there is no browser step (unlike the `confluent` server). Before presenting, open a **new** session and check that the server is connected — Claude Code: `/mcp`; Copilot: *MCP: List Servers*; Bob: *Settings → MCP Servers*.

**Which engine answers what**

| The question is about… | Use | Why |
|---|---|---|
| the **current state**: *who just…, right now, latest, show me that customer*; filters and top-N on one table | **Lightning** (natural language) | the feed is ~1 s old, the Customer 360 table up to ~1 min; no pipeline to build |
| **counts, sums, group-bys, joins, history** | **Trino** on the Iceberg table (Phase 8) | Lightning is read-only on one table, with no aggregates |

**Prompt 24: What Can You See in Real Time?**
```
What data can you query in real time, and what do the columns of
the Customer 360 table mean?
```

The assistant lists the Lightning Tables (`c360_live_activity`, `c360_snapshot_prebuilt`, and `c360_snapshot` once enabled) and describes their columns — it has discovered the tables itself, and can tell the raw event feed from the per-customer 360 table.

**Prompt 25: Who Is Active Right Now?**
```
Using real-time data, not Trino, who interacted with us most recently
and what exactly did they do?
```

After Phase 9 the assistant can answer from the live feed `c360_live_activity` within seconds (the new events, newest first) and from the Customer 360 table about a minute later (the three customers with their mobile `LOGIN → VIEW_BALANCE → PAYMENT` session) — long before the Iceberg table has them. If it uses the feed, ask it to also check the Customer 360 table: it should tell you which of the two speeds it is looking at.

**Prompt 26: One Customer, Right Now**
```
Show me the current 360 card of that customer.
```

**Prompt 27: Filters and Top-N**
```
Show me the five richest customers who have never used our digital channels.
```

The three customers from Phase 9 are no longer on the list — they just logged in.

**Prompt 28: Know the Limits**
```
How many customers have never used our digital channels?
```

A good teaching moment: Lightning cannot count. The assistant should say so, then either list the matching rows or switch to Trino (which gives the exact number). One product for current state, another for analytics.

### Phase 11: The Analytical Side Catches Up

Tableflow commits to Iceberg in batches of about 5 minutes. After that, the same change is visible to every analytical engine — here Trino through Polaris — with no extra pipeline.

**Prompt 29: See It Arrive**
```
Using Trino, who interacted with us most recently and what did they do?
And which customers with real balances have still never used our digital channels?
```

After the next Tableflow commit the customers from Phase 9 are at the top of the activity list with their new actions, and they have left the "never used digital" list. The table still has 200 rows: each customer's old version was replaced, not duplicated. The real-time answers came from Lightning — the raw event within about a second, the Customer 360 row within about a minute; the analytical one from Iceberg minutes later — three speeds, one pipeline.

**Prompt 30: From Data to Decisions**
```
Based on what you found, what are the three most valuable actions this
bank could take, and which customers would each one target?
```

The assistant combines the earlier answers into actions — for example a savings offer to the idle-cash customers, a manager call for the leveraged high-risk ones, and a digital campaign for the inactive ones.

**Result**: one real-time data product, served two ways — current state with Lightning queries for applications and agents, history and analytics with Tableflow, Polaris and Trino. The same queries are ready-made if you prefer the terminal: `make c360-queries` lists them, `make c360-queries Q=3` runs one and `make c360-queries Q=all` runs all eight (two more than the prompts above: manager portfolios and spend pressure).

### Phase 12: Automate Future Deployments

**Prompt 31: Generate Terraform**
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
│    - Output visible to readers when Flink commits (~1 min)    │
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

### Real-time serving: two speeds

The same button press (or `make demo-changes`) feeds two lanes. Lightning Tables read **committed** records, so the lane with a Flink statement in it waits for Flink's transaction commit (about once a minute); the lane without Flink does not.

```
                         ┌──► c360_live_activity ───────────────► Lightning Table ──► live feed (~1 s)
 "Make something         │     (Avro, plain producer, no Flink)
  happen" /              │
  make demo-changes ─────┤
                         │                                   Flink statement
                         └──► corebank.* + digital.interactions ──► c360-prebuilt-populate ──► c360_snapshot_prebuilt
                               (source topics)                    (commits ~every 60 s)        │
                                                                                               ├──► Lightning Table ──► Customer 360 (≤ ~1 min)
                                                                                               └──► Tableflow ──► Iceberg ──► Polaris ──► Trino (~5 min)
```

| Lane | Freshness | Aggregation | Why |
|---|---|---|---|
| `c360_live_activity` → Lightning | ~1 s | none — one row per raw event | plain producer, committed immediately |
| `c360_snapshot_prebuilt` → Lightning | up to ~1 min | one row per customer, joined from four topics | Flink exactly-once: output is committed on each checkpoint |
| `c360_snapshot_prebuilt` → Tableflow → Trino | a few minutes | same row, plus history | Tableflow publishes about every 5 minutes |

The trade-off is deliberate: exactly-once aggregation costs up to a minute, so the demo shows the immediate raw feed next to it. Details and the options not taken are in Phase 10 and in the [Build Guide](BUILD_GUIDE.md#48-real-time-queries--lightning-tables-and-the-live-front-end).

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

The build adds two more for the pre-built twin: **c360-prebuilt-table** (COMPLETED) and **c360-prebuilt-populate** (RUNNING). `make reset` leaves them alone; the statements above are the ones the live prompts create.

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

#### Problem: The assistant can't enable Tableflow

**Symptoms**:
- Authorization or "provider integration" errors
- The assistant tries to create its own bucket or storage

**Solution**:
1. Confirm the environment was built with Tableflow storage (it is on by default — see the [Build Guide](BUILD_GUIDE.md#46-tableflow-storage--prepared-at-build-enabled-during-the-demo)); `make status` shows it
2. Ask the assistant to use "the storage already prepared for this environment" and start a new session if it ignores that — `make ai-status` shows whether its environment context is current
3. Tableflow fixes its write mode (upsert or append) the first time it materializes a topic. If a topic was enabled before its final definition, delete the Tableflow topic and the Kafka topic and recreate both

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

#### Problem: The live view doesn't change after "Make something happen"

**Symptoms**:
- The progress box says "waiting for Flink's commit" and the Customer 360 panels don't move

**Cause and fix**:
1. This is expected for up to about a minute: the Customer 360 table is written by a Flink statement, which commits its Kafka transaction roughly once a minute, and Lightning reads only committed data. The *Live event feed* panel at the top should show the new events within about a second — if it does, nothing is wrong.
2. If the feed is empty or says it is "still being set up", check `make lightning-status` (both `c360_live_activity` and `c360_snapshot_prebuilt` must be ACTIVE; setup takes a few minutes after the build) and `make prebuilt-status`.
3. If nothing arrives even after two minutes, check that the Flink statement is RUNNING (`make prebuilt-status`) and that the button's output (the toast) says the events were produced.

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

#### Problem: The assistant can't answer in real time

**Symptom**: the assistant doesn't know about real-time data, says it has no Lightning tool, or reports no tables.

**Fix**:
1. Open a **new** session — assistants read their MCP configuration only at start — and check the `confluent-rtce` server is connected (Claude Code `/mcp`, Copilot *MCP: List Servers*, Bob *Settings → MCP Servers*).
2. `make ai-status` should show `+ rtce` for your assistant. If not: `make lightning-up`, then your `make ai-<tool>`.
3. The server only lists tables whose Lightning Table is ACTIVE: `make lightning-status`. The build enables `c360_snapshot_prebuilt` and `c360_live_activity` (a few minutes after `make up`); `c360_snapshot` appears after Prompt 11.
4. Fallback that needs no MCP: `make lightning-query LSQL='…'` or the live front end, `make c360-live`.

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

3. **Query the Iceberg Table**
   - Trino through Polaris is built in (Phase 8, Build Guide §4.7)
   - Or add another catalog integration (for example AWS Glue) and query with Athena, Snowflake or Databricks
   - Join with warehouse data for historical analysis

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
