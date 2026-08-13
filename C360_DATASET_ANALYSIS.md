# C360 Dataset Analysis

Scope: the topics tagged `c360` + `source` — the governed source-of-truth set for the Customer 360 use case.

| Topic | Role |
|---|---|
| `corebank.customers` | Customer master data (identity, segment, risk, RM) |
| `corebank.accounts` | Account master data (product, status, balance) |
| `corebank.transactions` | Card/account transaction events |
| `digital.interactions.avro` | Governed Avro replica of digital channel events (login, transfer, payment, …) |

Environment: `env-16z003` (`customer-360-demo-environment`), cluster `lkc-38r9zy2` (`customer-360-cluster`).

Sampling method: each topic was consumed from `earliest` (~54–55 records per topic — for the compacted `customers`/`accounts` topics this appears close to the full distinct-key population of this demo dataset; for the two append-only event topics it's a bounded window, not the full history). All statistics below are derived from this sample and should be treated as directional, not exact population figures.

---

## 1. Topic Configuration

| Config | `corebank.customers` | `corebank.accounts` | `corebank.transactions` | `digital.interactions.avro` |
|---|---|---|---|---|
| Partitions | 6 | 6 | 12 | 12 |
| Replication factor | 3 | 3 | 3 | 3 |
| `cleanup.policy` | compact | compact | delete | delete |
| `retention.ms` | -1 (infinite) | -1 (infinite) | 2,592,000,000 (30d) | 2,592,000,000 (30d) |
| `min.insync.replicas` | 2 | 2 | 2 | 2 |
| `max.message.bytes` | 1,048,588 | 1,048,588 | 1,048,588 | 1,048,588 |
| Key | `customer_id` | `account_id` | `txn_id` | raw string (`event_id`) |
| Semantic shape | Upsert / current-state master | Upsert / current-state master | Append-only event log | Append-only event log |

**Read:** the two master-data topics are compacted with infinite retention — correct for "current truth about an entity" data. The two event topics are delete/30-day — correct for a rolling activity window, but it means **any snapshot or aggregate built on `corebank.transactions` or `digital.interactions.avro` only has 30 days of history to draw from**; a "customer lifetime" view would need a separate durable sink (e.g., Tableflow/Iceberg) alongside this Flink pipeline.

---

## 2. Data Schema

All four topics are Avro, Schema Registry-governed:

| Subject | Schema ID | Fields |
|---|---|---|
| `corebank.customers-value` | 100005 | `customer_id` string · `full_name` string · `segment` enum{RETAIL,PREMIER,PRIVATE} · `risk_band` enum{LOW,MEDIUM,HIGH} · `relationship_manager` nullable string (default null) · `email` string · `phone` string · `created_at` long (timestamp-millis) |
| `corebank.accounts-value` | 100006 | `account_id` string · `customer_id` string · `product_type` enum{CHECKING,SAVINGS,CREDIT_CARD,MORTGAGE,INVESTMENT} · `status` enum{ACTIVE,DORMANT,CLOSED} · `balance` double · `currency` string (default EUR) · `opened_at` long (timestamp-millis) |
| `corebank.transactions-value` | 100007 | `txn_id` string · `account_id` string · `amount` double · `currency` string (default EUR) · `mcc` string · `merchant_name` string · `channel` enum{ATM,POS,ONLINE,MOBILE} · `ts` long (timestamp-millis) |
| `digital.interactions.avro-value` | 100008 | `event_id` string · `customer_id` string · `event_type` string · `channel` string · `session_id` string · `ts` long |

**Join graph:**

```
corebank.customers (customer_id) ──┬──< corebank.accounts (customer_id → account_id)
                                    │                         │
                                    │                         └──< corebank.transactions (account_id)
                                    │
                                    └──< digital.interactions.avro (customer_id)
```

`corebank.transactions` has **no direct `customer_id`** — it only reaches the customer through `corebank.accounts.account_id`, a one-hop join. This is the key structural fact driving the recommendation in §4.

---

## 3. Business Insights (from ~54–55 record sample per topic)

**Customer base**
- Segment mix: **RETAIL ~67%, PREMIER ~26%, PRIVATE ~7%**.
- Risk mix: **LOW ~65%, MEDIUM ~30%, HIGH ~6%**.
- `relationship_manager` is populated for every PREMIER/PRIVATE customer sampled and null for every RETAIL customer — the RM-assignment rule holds cleanly across the larger sample (confirms the Step 2 finding at scale, not just in 10 records).
- A small number of RM names recur across many customers (e.g., "Francisco Romero Torres," "Carmen González Martín," "Miguel Sánchez Díaz") — consistent with a realistic RM:client ratio for Premier/Private banking.

**Accounts**
- Product mix: **CHECKING ~43%, SAVINGS ~28%, CREDIT_CARD ~17%, MORTGAGE ~11%, INVESTMENT ~2%**.
- Status: **ACTIVE ~94%, DORMANT ~4%, CLOSED ~2%**.
- Balance sign convention is completely consistent: **CREDIT_CARD and MORTGAGE are always negative** (liabilities), **CHECKING/SAVINGS/INVESTMENT are always positive** (assets) — every sampled record follows this rule with no exceptions, so `SUM(balance)` per customer is a valid "net position" metric without extra sign-correction logic.
- Several customers hold multiple accounts (e.g., one PREMIER customer with both SAVINGS + INVESTMENT); a per-customer account rollup is meaningful, not degenerate.

**Transactions**
- Channel mix: **MOBILE ~41%, ONLINE ~30%, POS ~20%, ATM ~9%** — mobile-first spend behavior.
- Merchant/MCC pairing is internally consistent across the full sample (grocery MCC 5411 ↔ Mercadona/Dia/Carrefour/Lidl/Alcampo/Eroski; fuel MCC 5541 ↔ Repsol/Cepsa/Galp/BP/Shell; pharmacy MCC 5912; transport MCC 4111 ↔ Renfe; utilities MCC 4900 ↔ Iberdrola/Naturgy/Vodafone), all Spain-localized.
- **Every single sampled transaction (54/54, and 10/10 in the earlier Step 2 sample — 64 total) is a debit (negative amount).** No credits/deposits/salary or incoming-transfer transactions appeared. This is a real data-completeness gap for a "360" view: it means any snapshot built from this topic can describe *spend* but not *inflow*, income, or net cash flow — worth flagging to whoever owns the data generator if the demo needs to show income-side behavior.

**Digital interactions**
- With a larger sample, the event-type space is richer than the Step 2 spot-check suggested: **LOGOUT ~27%, LOGIN ~18%, VIEW_BALANCE ~16%, PAYMENT ~15%, TRANSFER ~13%, VIEW_STATEMENT ~9%, UPDATE_PROFILE ~2%** (7 distinct types vs. the 3 seen in the earlier 10-record spot check — a good example of why sample size matters before drawing conclusions).
- Channel mix: **MOBILE ~53%, WEB ~36%, TABLET ~11%**.
- LOGIN/LOGOUT pairs frequently share a `session_id` with close timestamps (e.g., a LOGIN and LOGOUT 20 seconds apart for the same session) — session_id is a reliable session-boundary key if session-level analysis is ever needed.
- Cross-topic referential integrity holds in-sample: `customer_id` values seen in `digital.interactions.avro` (e.g., a PREMIER customer with an assigned RM) also appear in `corebank.customers`, and `account_id` values in `corebank.transactions` also appear in `corebank.accounts` — no orphan keys observed, which de-risks the joins proposed below.
- The channel vocabulary here (`WEB/MOBILE/TABLET`) still doesn't overlap with `corebank.transactions.channel` (`ATM/POS/ONLINE/MOBILE`) beyond `MOBILE` — flagged already in Step 2, still true at this sample size.

---

## 4. Recommendation: `c360_snapshot` via Flink

### Design goal
One upsert row per `customer_id` combining: customer master fields, an account rollup, recent transaction activity, and the **last 3 digital interactions** — kept continuously up to date as new events arrive on any of the 4 source topics.

### Key design decision: how to get "last 3"
Flink SQL has no `LIMIT`-per-group primitive directly usable inside a continuous aggregation, so the standard Top-N pattern is:

```sql
ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY ts DESC) AS rn
```
filtered to `rn <= 3`. This produces a retracting/upsert changelog (ranks shift as new events arrive), which Flink can legally re-aggregate downstream — this "Top-N feeding an aggregation" pattern is a supported, documented Flink SQL idiom.

For determinism, this design pivots the 3 ranked rows into fixed, ordered columns (`interaction_1_*`, `interaction_2_*`, `interaction_3_*`) with `MAX(CASE WHEN rn=n THEN … END)` rather than `ARRAY_AGG`, since Confluent Cloud Flink's `ARRAY_AGG` does not guarantee element order — a `MAX/CASE` pivot guarantees "interaction_1 is always the most recent" without relying on unordered array semantics.

### Recommended staged approach
A single mega-join across 4 changelog/stream sources is expensive and hard to debug. Recommend **3 small materialized statements feeding a final join**, each independently inspectable and restartable:

**Stage A — account rollup per customer**
```sql
CREATE TABLE accounts_by_customer (
  customer_id    STRING,
  account_count  BIGINT,
  total_balance  DOUBLE,
  accounts       ARRAY<ROW<account_id STRING, product_type STRING, status STRING, balance DOUBLE, currency STRING>>,
  PRIMARY KEY (customer_id) NOT ENFORCED
) WITH ('value.format' = 'avro-registry', 'kafka.cleanup-policy' = 'compact');

INSERT INTO accounts_by_customer
SELECT customer_id,
       COUNT(*)                                                              AS account_count,
       SUM(balance)                                                         AS total_balance,
       ARRAY_AGG(ROW(account_id, CAST(product_type AS STRING), CAST(status AS STRING), balance, currency)) AS accounts
FROM `corebank.accounts`
GROUP BY customer_id;
```

**Stage B — 30-day transaction activity per customer** (via the `account_id → customer_id` hop)
```sql
CREATE TABLE txn_activity_by_customer (
  customer_id     STRING,
  txn_count_30d   BIGINT,
  net_amount_30d  DOUBLE,
  last_txn_ts     TIMESTAMP(3),
  PRIMARY KEY (customer_id) NOT ENFORCED
) WITH ('value.format' = 'avro-registry', 'kafka.cleanup-policy' = 'compact');

INSERT INTO txn_activity_by_customer
SELECT a.customer_id,
       COUNT(*)                              AS txn_count_30d,
       SUM(t.amount)                         AS net_amount_30d,
       MAX(TO_TIMESTAMP_LTZ(t.ts, 3))         AS last_txn_ts
FROM `corebank.transactions` t
JOIN `corebank.accounts` a ON t.account_id = a.account_id
GROUP BY a.customer_id;
```
(`corebank.accounts` is an inferred **upsert** table since it's compacted and keyed by `account_id`, so this join between an append-only stream and an upsert table is a standard, supported enrichment join — no explicit temporal-join syntax needed.)

**Stage C — last 3 digital interactions per customer**
```sql
CREATE TABLE recent_digital_interactions (
  customer_id            STRING,
  interaction_1_type     STRING, interaction_1_channel STRING, interaction_1_ts TIMESTAMP(3),
  interaction_2_type     STRING, interaction_2_channel STRING, interaction_2_ts TIMESTAMP(3),
  interaction_3_type     STRING, interaction_3_channel STRING, interaction_3_ts TIMESTAMP(3),
  PRIMARY KEY (customer_id) NOT ENFORCED
) WITH ('value.format' = 'avro-registry', 'kafka.cleanup-policy' = 'compact');

INSERT INTO recent_digital_interactions
SELECT customer_id,
  MAX(CASE WHEN rn=1 THEN event_type END), MAX(CASE WHEN rn=1 THEN channel END), MAX(CASE WHEN rn=1 THEN TO_TIMESTAMP_LTZ(ts,3) END),
  MAX(CASE WHEN rn=2 THEN event_type END), MAX(CASE WHEN rn=2 THEN channel END), MAX(CASE WHEN rn=2 THEN TO_TIMESTAMP_LTZ(ts,3) END),
  MAX(CASE WHEN rn=3 THEN event_type END), MAX(CASE WHEN rn=3 THEN channel END), MAX(CASE WHEN rn=3 THEN TO_TIMESTAMP_LTZ(ts,3) END)
FROM (
  SELECT customer_id, event_type, channel, ts,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY ts DESC) AS rn
  FROM `digital.interactions.avro`
)
WHERE rn <= 3
GROUP BY customer_id;
```

**Stage D — final snapshot**
```sql
CREATE TABLE c360_snapshot (
  customer_id           STRING,
  full_name             STRING,
  segment               STRING,
  risk_band             STRING,
  relationship_manager  STRING,
  email                 STRING,
  phone                 STRING,
  account_count         BIGINT,
  total_balance         DOUBLE,
  accounts              ARRAY<ROW<account_id STRING, product_type STRING, status STRING, balance DOUBLE, currency STRING>>,
  txn_count_30d         BIGINT,
  net_amount_30d        DOUBLE,
  last_txn_ts           TIMESTAMP(3),
  interaction_1_type    STRING, interaction_1_channel STRING, interaction_1_ts TIMESTAMP(3),
  interaction_2_type    STRING, interaction_2_channel STRING, interaction_2_ts TIMESTAMP(3),
  interaction_3_type    STRING, interaction_3_channel STRING, interaction_3_ts TIMESTAMP(3),
  snapshot_updated_at   TIMESTAMP(3),
  PRIMARY KEY (customer_id) NOT ENFORCED
) WITH ('value.format' = 'avro-registry', 'kafka.cleanup-policy' = 'compact');

INSERT INTO c360_snapshot
SELECT
  c.customer_id, c.full_name, CAST(c.segment AS STRING), CAST(c.risk_band AS STRING),
  c.relationship_manager, c.email, c.phone,
  COALESCE(ac.account_count, 0), COALESCE(ac.total_balance, 0.0), ac.accounts,
  COALESCE(tx.txn_count_30d, 0), COALESCE(tx.net_amount_30d, 0.0), tx.last_txn_ts,
  di.interaction_1_type, di.interaction_1_channel, di.interaction_1_ts,
  di.interaction_2_type, di.interaction_2_channel, di.interaction_2_ts,
  di.interaction_3_type, di.interaction_3_channel, di.interaction_3_ts,
  CURRENT_TIMESTAMP
FROM `corebank.customers` c
LEFT JOIN accounts_by_customer ac ON c.customer_id = ac.customer_id
LEFT JOIN txn_activity_by_customer tx ON c.customer_id = tx.customer_id
LEFT JOIN recent_digital_interactions di ON c.customer_id = di.customer_id;
```

### Config recommendation for `c360_snapshot` itself
`cleanup.policy=compact`, infinite retention, `value.format=avro-registry` — same governance posture as `corebank.customers`/`corebank.accounts`, since this is itself a current-state master view. Tag it `c360` + `source` (it becomes a new governed source for downstream consumers like a C360 API or dashboard) once built.

### Operational notes / caveats
- This is a **recommendation, not yet executed** — given it provisions 4 new topics and 4 continuously-running (billed) Flink statements on the shared `customer-360-flink-pool`, it should be reviewed and run in stages rather than all at once.
- The transaction-side metrics are bounded by the 30-day retention on `corebank.transactions` — "last 30 days" is the practical ceiling, not a design choice.
- All sampled transactions were debits (see §3) — `net_amount_30d` will currently only ever be negative/spend-side until the source data includes credits.
- Multi-way joins across changelog tables retain state per key indefinitely by default; for a demo-scale dataset (~54 customers) this is trivial, but a production build should set `table.exec.state.ttl` appropriately.

---

## Next step
Want me to actually create and run the staged Flink statements (A → D) above, the same way we built `digital.interactions.avro` earlier in this session?
