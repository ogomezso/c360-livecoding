# C360 Dataset Analysis

Scope: the four topics tagged both `c360` and `source` — the primary, schema-enforced
records behind the Banking Customer 360 use case.

| Topic | Role |
|---|---|
| `corebank.customers` | Customer master data (identity, segment, risk, RM) |
| `corebank.accounts` | Account master data (product, status, balance) |
| `corebank.transactions` | Card/account transaction events |
| `digital.interactions.avro` | Governed Avro replica of digital channel events (login, transfer, payment, …) |

Environment: `env-87zorq` (`customer-360-demo-environment`), cluster `lkc-dogym37`
(`customer-360-cluster`), Flink compute pool `customer-360-flink-pool`.

Sampling method: each topic was consumed from `earliest` (15 records per topic). The
business insights below are directional patterns worth designing around, not a
statistically verified population study — re-run against the full topic before sizing
anything financially.

---

## 1. Topic Configuration

| Config | `corebank.customers` | `corebank.accounts` | `corebank.transactions` | `digital.interactions.avro` |
|---|---|---|---|---|
| Partitions | 6 | 6 | 12 | 12 |
| Replication factor | 3 | 3 | 3 | 3 |
| `cleanup.policy` | compact | compact | delete | delete |
| `retention.ms` | -1 (infinite) | -1 (infinite) | 2,592,000,000 (30d) | 2,592,000,000 (30d) |
| `min.insync.replicas` | 2 | 2 | 2 | 2 |
| Key | `customer_id` (raw string) | `account_id` (raw string) | `txn_id` (raw string) | `event_id` (raw string) |
| Records observed | ≈200 | ≈372 | 1,000 | ≥800, growing live |
| Semantic shape | Upsert / current-state master | Upsert / current-state master | Append-only event log | Append-only event log |

**Read:** the two master-data topics are compacted with infinite retention — correct
for "current truth about an entity" data. The two event topics are delete/30-day —
correct for a rolling activity window, but it means any snapshot or aggregate built on
`corebank.transactions` or `digital.interactions.avro` only has 30 days of history to
draw from.

`digital.interactions.avro` is itself a Flink-built replica of the schemaless
`digital.interactions` topic (tagged `c360` + `raw`), kept live by the
`replicate-digital-interactions-avro` statement on `customer-360-flink-pool` — its
record count keeps climbing in step with the source, it isn't a static snapshot.

---

## 2. Data Schema

All four topics are Avro, Schema Registry-governed:

| Subject | Schema ID | Fields |
|---|---|---|
| `corebank.customers-value` | 100005 | `customer_id` string · `full_name` string · `segment` enum{RETAIL,PREMIER,PRIVATE} · `risk_band` enum{LOW,MEDIUM,HIGH} · `relationship_manager` nullable string (default null) · `email` string · `phone` string · `created_at` long (timestamp-millis) |
| `corebank.accounts-value` | 100006 | `account_id` string · `customer_id` string · `product_type` enum{CHECKING,SAVINGS,CREDIT_CARD,MORTGAGE,INVESTMENT} · `status` enum{ACTIVE,DORMANT,CLOSED} · `balance` double · `currency` string (default EUR) · `opened_at` long (timestamp-millis) |
| `corebank.transactions-value` | 100007 | `txn_id` string · `account_id` string · `amount` double · `currency` string (default EUR) · `mcc` string · `merchant_name` string · `channel` enum{ATM,POS,ONLINE,MOBILE} · `ts` long (timestamp-millis) |
| `digital.interactions.avro-value` | 100008 | `event_id` string\|null · `customer_id` string\|null · `event_type` string\|null · `channel` string\|null · `session_id` string\|null · `ts` long\|null |

**Join graph:**

```
corebank.customers (customer_id) ──┬──< corebank.accounts (customer_id → account_id)
                                    │                         │
                                    │                         └──< corebank.transactions (account_id)
                                    │
                                    └──< digital.interactions.avro (customer_id)
```

`corebank.transactions` has **no direct `customer_id`** — it only reaches the customer
through `corebank.accounts.account_id`, a one-hop join. Every `customer_id` and
`account_id` spot-checked across topic boundaries during this analysis resolved to an
existing row on the other side — no orphaned foreign keys observed in-sample.

### Sample rows

**`corebank.customers`**
```json
{ "customer_id": "ac783acd-4284-449e-a3d7-48f64d525437", "full_name": "Rolando Cobo",
  "segment": "PREMIER", "risk_band": "LOW",
  "relationship_manager": "Carlos Fernández Ruiz",
  "email": "uanton@example.net", "phone": "+34 820 68 82 34" }
```

**`corebank.accounts`**
```json
{ "account_id": "d7609aa2-...", "customer_id": "984b0b46-...",
  "product_type": "MORTGAGE", "balance": -98300.09 }
{ "account_id": "2986b0a5-...", "customer_id": "e19444a8-...",
  "product_type": "INVESTMENT", "balance": 142264.20 }
```

**`corebank.transactions`**
```json
{ "txn_id": "54fce313-...", "account_id": "d9cc8a18-...",
  "amount": -202.21, "merchant_name": "Zara", "channel": "ATM" }
{ "txn_id": "c817efc7-...", "account_id": "d7609aa2-...",
  "amount": -86.77, "merchant_name": "Alcampo", "channel": "ONLINE" }
```

**`digital.interactions.avro`**
```json
{ "event_id": "019c39a4-...", "customer_id": "0cf89962-...",
  "event_type": "LOGIN", "channel": "MOBILE" }
{ "event_id": "279ca709-...", "customer_id": "0cf89962-...",
  "event_type": "VIEW_BALANCE", "channel": "MOBILE" }
```

---

## 3. Business Insights (from a 15-record sample per topic)

1. **Service tiering is real in the data, not just in the schema.** `relationship_manager`
   is populated only for PREMIER and PRIVATE customers — every sampled RETAIL row carries
   `null`. e.g. Rolando Cobo (PREMIER) → RM "Carlos Fernández Ruiz"; Ariel Lillo Ruiz
   (RETAIL) → RM null. A snapshot can branch on segment without a separate lookup.

2. **Multi-product relationships already exist.** Several sampled customers hold two
   accounts of different product types — e.g. `customer_id e19444a8-...` holds SAVINGS
   (18,765.24 EUR) + INVESTMENT (142,264.20 EUR). A snapshot exposing only one account per
   customer would hide the cross-sell picture.

3. **Balance sign encodes liability vs. asset.** MORTGAGE (−98,300.09) and CREDIT_CARD
   (−4,118.50) are consistently negative; CHECKING (+4,630.18), SAVINGS, and INVESTMENT
   are positive. `SUM(balance)` per customer is already a genuine net-worth figure, not a
   magnitude needing re-signing downstream.

4. **Digital interactions trace a recognizable funnel.** Events sharing a `session_id`
   chain as LOGIN → VIEW_BALANCE/VIEW_STATEMENT → PAYMENT/TRANSFER → LOGOUT (e.g. session
   `08b6e0c9-...`: LOGIN then VIEW_BALANCE for the same `customer_id 0cf89962-...`). "Last
   3 interactions" is a live read on where a customer sits in that funnel right now — a
   real next-best-action signal, not just an activity log.

5. **Cross-topic keys resolve cleanly.** No orphaned foreign keys observed between any of
   the four topics in-sample — the join-heavy snapshot design below can be built directly,
   with no entity-resolution step first.

6. **Risk band isn't uniformly low.** Most sampled customers are LOW risk, but MEDIUM/HIGH
   risk RETAIL customers do appear — e.g. Nadia Huertas Puente, RETAIL, `risk_band HIGH`,
   `relationship_manager null`. `risk_band` should stay a first-class, filterable field in
   the snapshot rather than buried in a profile blob.

---

## 4. Recommendation: `c360_snapshot` via Flink

### Design goal
One continuously-updated, compacted row per `customer_id`: profile fields, an account
rollup, and the three most recent digital interactions — so any downstream consumer gets
a real-time customer 360 view with a single key lookup instead of three joins.

### Key design decision: how to get "last 3"
Confluent Cloud Flink's aggregate function set does **not** include `ARRAY_AGG` —
`COLLECT` returns an unordered multiset, and `LISTAGG` only concatenates strings (both
confirmed against the current function reference before writing this). The portable way
to carry a fixed "last 3" into one row is the standard Top-N rank:

```sql
ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY ts DESC) AS rn
```

filtered to `rn <= 3`, then pivoted into fixed, ordered columns
(`interaction_1_*`/`interaction_2_*`/`interaction_3_*`) with
`MAX(CASE WHEN rn = n THEN … END)` — this guarantees "interaction_1 is always the most
recent" without relying on array ordering the engine doesn't promise.

### Staged build

**Stage 1 — latest customer profile** (dedupe the compacted topic; Flink infers it
append-only unless told otherwise)
```sql
CREATE VIEW customers_latest AS
SELECT customer_id, full_name, segment, risk_band,
       relationship_manager, email, phone
FROM (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY $rowtime DESC) AS rn
  FROM `corebank.customers`
) WHERE rn = 1;
```

**Stage 2 — per-customer account rollup**
```sql
CREATE VIEW accounts_summary AS
SELECT
  customer_id,
  COUNT(*)                    AS account_count,
  SUM(balance)                 AS net_balance,
  LISTAGG(product_type, ', ')  AS product_types
FROM (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY $rowtime DESC) AS rn
  FROM `corebank.accounts`
) WHERE rn = 1
GROUP BY customer_id;
```

**Stage 3 — last 3 digital interactions, pivoted flat**
```sql
CREATE VIEW interactions_ranked AS
SELECT customer_id, event_type, channel, ts,
  ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY ts DESC) AS rn
FROM `digital.interactions.avro`;

CREATE VIEW interactions_last3 AS
SELECT
  customer_id,
  MAX(CASE WHEN rn = 1 THEN event_type END) AS interaction_1_type,
  MAX(CASE WHEN rn = 1 THEN channel    END) AS interaction_1_channel,
  MAX(CASE WHEN rn = 1 THEN ts         END) AS interaction_1_ts,
  MAX(CASE WHEN rn = 2 THEN event_type END) AS interaction_2_type,
  MAX(CASE WHEN rn = 2 THEN channel    END) AS interaction_2_channel,
  MAX(CASE WHEN rn = 2 THEN ts         END) AS interaction_2_ts,
  MAX(CASE WHEN rn = 3 THEN event_type END) AS interaction_3_type,
  MAX(CASE WHEN rn = 3 THEN channel    END) AS interaction_3_channel,
  MAX(CASE WHEN rn = 3 THEN ts         END) AS interaction_3_ts
FROM interactions_ranked
WHERE rn <= 3
GROUP BY customer_id;
```

**Stage 4 — the sink topic** (declaring `PRIMARY KEY` is what makes this compacted/upsert,
matching `corebank.customers`/`corebank.accounts` rather than the event-log shape of the
other two source topics)
```sql
CREATE TABLE `c360_snapshot` (
  customer_id           STRING,
  full_name             STRING,
  segment               STRING,
  risk_band             STRING,
  relationship_manager  STRING,
  email                 STRING,
  phone                 STRING,
  account_count         BIGINT,
  net_balance           DOUBLE,
  product_types         STRING,
  interaction_1_type    STRING,
  interaction_1_channel STRING,
  interaction_1_ts      BIGINT,
  interaction_2_type    STRING,
  interaction_2_channel STRING,
  interaction_2_ts      BIGINT,
  interaction_3_type    STRING,
  interaction_3_channel STRING,
  interaction_3_ts      BIGINT,
  PRIMARY KEY (customer_id) NOT ENFORCED
)
DISTRIBUTED BY (customer_id) INTO 6 BUCKETS
WITH ('value.format' = 'avro-registry');
```

**Stage 5 — continuous population**
```sql
INSERT INTO `c360_snapshot`
SELECT
  c.customer_id, c.full_name, c.segment, c.risk_band,
  c.relationship_manager, c.email, c.phone,
  COALESCE(a.account_count, 0), COALESCE(a.net_balance, 0.0), a.product_types,
  i.interaction_1_type, i.interaction_1_channel, i.interaction_1_ts,
  i.interaction_2_type, i.interaction_2_channel, i.interaction_2_ts,
  i.interaction_3_type, i.interaction_3_channel, i.interaction_3_ts
FROM customers_latest c
LEFT JOIN accounts_summary   a ON c.customer_id = a.customer_id
LEFT JOIN interactions_last3 i ON c.customer_id = i.customer_id;
```

### Config recommendation for `c360_snapshot` itself
`cleanup.policy=compact` (implied by the declared `PRIMARY KEY`), infinite retention,
`value.format=avro-registry` — same governance posture as `corebank.customers` /
`corebank.accounts`, since this is itself a current-state master view. Worth tagging it
`c360` + `source` once built, the same way the other four topics are tagged.

### Operational notes / caveats
- **This is a design recommendation, not yet executed** — nothing above has been created
  or run against the cluster. Build it in stages: sink + Stage 1–2 first, confirm the
  profile+account rollup looks right, then add the interaction pivot.
- **Unbounded state.** Both the dedupe views (Stage 1–2) and the Top-N rank (Stage 3) keep
  per-key state indefinitely in a streaming job — trivial at hundreds-to-low-thousands of
  records, but state TTL should be planned before this runs against production volumes.
- **`LISTAGG` has no `DISTINCT`.** If a customer holds two accounts of the same
  `product_type`, `product_types` will list it twice. Acceptable for a first cut; dedupe
  product types before the `LISTAGG` if it matters downstream.
- **`digital.interactions.avro` is a derived replica, not an original source.** It's
  tagged `source` because it's the schema-enforced record consumers should read, but its
  data still originates in the schemaless `digital.interactions` topic one hop upstream.
- **Natural extension.** The same rank-and-pivot pattern from Stage 3 applies directly to
  `corebank.transactions` if a future revision of `c360_snapshot` should also carry a
  customer's last 3 transactions.

---

*Compiled from live reads against Confluent Cloud (`list-topics`, `get-topic-config`,
`list-schemas`, `consume-messages`, `search-topics-by-tag`) during this session. No
topics or Flink statements were created or modified in the course of producing this
analysis.*
