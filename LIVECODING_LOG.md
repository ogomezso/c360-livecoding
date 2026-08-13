# Live Coding Session Log

Running record of prompts, actions, and results for this session. Updated after each step.

- **Date:** 2026-08-11
- **Repo:** c360-livecoding
- **Branch:** main

---

## Step 0 — Set up session logging

**Prompt:** Record the sequence and results of the live coding session in document form (not visual).

**Actions:**

- Created this log file (`LIVECODING_LOG.md`) to track each step going forward.

**Result:** Logging in place. Will append one entry per step with: prompt, actions taken, key commands/output, and outcome.

---

## Step 1 — List Kafka topics

**Prompt:** Can you list all my Kafka topics?

**Actions:**

- Ran `mcp__confluent__list-environments` — 10 environments in the org, none obviously matching this project by name.
- Grepped repo for `env-`/`lkc-` references; found `environment/terraform-confluent-aws/confluent.tf` provisions a dedicated `confluent_environment.customer_360`.
- Read `terraform output -json` from `environment/terraform-confluent-aws` to get the actual provisioned IDs:
  - `environment_id = env-16z003` (`customer-360-demo-environment`)
  - `kafka_cluster_id = lkc-38r9zy2` (`customer-360-cluster`)
- Ran `mcp__confluent__list-topics` with those IDs.

**Result:** 8 topics in `customer-360-cluster`: `pageviews`, `clickstream`, `corebank.accounts`, `corebank.customers`, `corebank.transactions`, `digital.interactions`, `stock_trades`, `orders`.

---

## Step 2 — Detailed view of core/digital banking topics

**Prompt:** Give a detailed view of the core banking and digital banking topics: topic config, schema, data quality, data samples.

**Actions:**

- Ran `get-topic-config` for `corebank.accounts`, `corebank.customers`, `corebank.transactions`, `digital.interactions`.
- Ran `list-schemas` (prefix `corebank` and `digital`) against Schema Registry in `env-16z003`.
- Ran `consume-messages` (10 msgs, earliest) for each of the 4 topics.

**Result (key findings):**

- `corebank.accounts` / `corebank.customers`: 6 partitions, `cleanup.policy=compact`, infinite retention — compacted current-state topics. Registered Avro schemas (ids 100006 / 100005). No nulls/malformed data in samples; `relationship_manager` nullability correctly tied to customer `segment`.
- `corebank.transactions`: 12 partitions, `cleanup.policy=delete`, 30-day retention. Registered Avro schema (id 100007). `mcc` ↔ `merchant_name` pairs internally consistent; all 10 sampled amounts were debits (negative).
- `digital.interactions`: 12 partitions, `cleanup.policy=delete`, 30-day retention. **No schema registered — plain/schemaless JSON.** Flagged as the main data-quality/governance gap (no SR validation) plus a channel-taxonomy mismatch vs. `corebank.transactions` (`WEB/MOBILE/TABLET` vs `ATM/POS/ONLINE/MOBILE`).
- All 4 topics: replication factor 3, `min.insync.replicas=2`, `max.message.bytes=1048588`.

---

## Step 3 — Flink query to replicate digital.interactions as Avro

**Prompt:** Create a Flink query that replicates the `digital.interactions` topic with the same exact configuration but enforcing an AVRO schema, continuously replicating new data.

**Actions:**

- Checked how Flink infers the schemaless source: `describe-flink-table`/`get-flink-table-info` on `digital.interactions` showed only raw `key`/`val` `VARBINARY` columns (no SR schema).
- Looked up compute pool (`lfcp-v7rgq35`), org id, and the exact `CREATE TABLE` WITH-options syntax via `search-product-docs`/`get-product-doc-page` (Confluent's "Convert the Serialization Format of a Topic" guide).
- Ran `create-flink-statement` (`create-digital-interactions-avro`) to `CREATE TABLE` the `digital.interactions.avro` table with explicit columns (event_id, customer_id, event_type, channel, session_id, ts) and WITH options matching the source config: `'kafka.cleanup-policy'='delete'`, `'kafka.retention.time'='2592000000 ms'`, `'kafka.max-message-size'='1048588 bytes'`, `DISTRIBUTED BY HASH(key) INTO 12 BUCKETS`, `'value.format'='avro-registry'`, `'key.format'='raw'`.
- Ran `create-flink-statement` (`insert-digital-interactions-avro`), a long-running `INSERT INTO ... SELECT` that parses the raw JSON via `JSON_VALUE(CAST(val AS STRING), '$.field')` and streams continuously from `digital.interactions`.
- Verified with `check-flink-statement-health` (both statements healthy — CREATE completed, INSERT running with 0 exceptions), `get-topic-config`, `list-schemas`, and `consume-messages` on the new topic.

**Result:** New topic `digital.interactions.avro` created with config matching the source exactly (12 partitions, replication 3, `cleanup.policy=delete`, 30-day retention, `min.insync.replicas=2`, same max message size). Avro schema registered (subject `digital.interactions.avro-value`, id 100008). The streaming `INSERT INTO` job is `RUNNING` and actively producing correctly-decoded Avro records — confirmed by consuming 5 sample messages. This closes the schema-governance gap flagged in Step 2 for a governed replica of the topic.

---

## Step 4 — Tag primary topics with `c360` and `source`

**Prompt:** Tag all primary topics with 'source' and 'c360' tags.

**Actions:**

- Found an existing (stale) `tag-corebank-topics.sh` script in the repo defining `c360`/`source` tags for only the 3 `corebank.*` topics — used as context, not executed (it targets a removed `mcp-confluent` server setup).
- Asked the user to confirm topic scope for "primary" — they specified: `corebank.accounts`, `corebank.customers`, `corebank.transactions`, and `digital.interactions.avro` (the governed Avro replica from Step 3) — explicitly excluding the raw schemaless `digital.interactions`.
- Checked `list-tags` (none existed yet) and resolved each topic's qualified entity name via `search-topics-by-name`.
- Created tag definitions via `create-topic-tags`: `c360` and `source`.
- Assigned both tags to all 4 topics via `add-tags-to-topic` (8 assignments total).
- Verified via `search-topics-by-tag` for both `c360` and `source` — each returns exactly the 4 intended topics with `classificationNames: ["c360","source"]`.

**Result:** `corebank.accounts`, `corebank.customers`, `corebank.transactions`, and `digital.interactions.avro` are now tagged `c360` + `source` in Schema Registry/Stream Catalog.

---

## Step 5 — Tag `digital.interactions` with `c360` and `raw`

**Prompt:** (repeat of the tagging prompt, then) tag `digital.interactions` as `c360` and `raw`.

**Actions:**

- Re-verified Step 4's tagging was unchanged (`search-topics-by-tag c360` still returns the same 4 topics) before doing anything new.
- Created the `raw` tag definition via `create-topic-tags` (`c360` already existed).
- Resolved the exact qualified name via `search-topics-by-name` (careful to pick `...digital.interactions`, not the `...digital.interactions.avro` match it also returned).
- Assigned `c360` + `raw` via `add-tags-to-topic`; verified via `search-topics-by-tag raw`.

**Result:** `digital.interactions` (the raw schemaless topic) is now tagged `c360` + `raw`, distinguishing it from the governed `digital.interactions.avro` replica tagged `c360` + `source`.

---

## Step 6 — List topics ordered by tag

**Prompt:** Can you list my topics ordered by tag?

**Actions:**

- Ran `list-tags` to get the full tag definition list (`c360`, `source`, `raw`).
- Ran `search-topics-by-tag` for each of the 3 tags, plus `list-topics` to identify any untagged topics by difference.

**Result:** Grouped listing presented to the user — `c360` (5 topics: the 3 `corebank.*` + both `digital.interactions` variants), `source` (4: the 3 `corebank.*` + `digital.interactions.avro`), `raw` (1: `digital.interactions`), and 4 untagged topics (`pageviews`, `clickstream`, `stock_trades`, `orders`) unrelated to the C360 demo.

---

## Step 7 — C360 Dataset Analysis document

**Prompt:** Build a Dataset Analysis of the `c360`+`source` tagged topics covering topic configuration, data schema, sampling, business insights, and recommendations for a `c360_snapshot` Flink topic covering real-time C360 data including the last 3 digital interactions.

**Actions:**

- Consumed ~54–55 records each from `corebank.customers`, `corebank.accounts`, `corebank.transactions`, and `digital.interactions.avro` (up from the 10-record spot checks in Step 2) to get statistically sturdier distributions.
- Manually tallied segment/risk-band mix, RM-assignment consistency, account product/status mix and balance-sign convention, transaction channel/MCC consistency, and digital-interaction event-type/channel mix.
- Designed a staged Flink SQL recommendation for `c360_snapshot`: three intermediate materialized tables (account rollup, 30-day transaction activity via a join through `corebank.accounts`, and a Top-N-via-`ROW_NUMBER()` pivot for a deterministic "last 3 digital interactions") feeding one final joined upsert table — rather than one large multi-way join.
- Wrote the full analysis to a new file, `C360_DATASET_ANALYSIS.md`, in the repo root.

**Result:** New deliverable `C360_DATASET_ANALYSIS.md` covering all 4 requested sections. Key findings surfaced: 100% of sampled transactions were debits (no income-side data), digital-interaction event types are richer than the earlier 10-record sample suggested (7 types, not 3), and balance-sign convention (asset vs. liability products) is fully consistent. The `c360_snapshot` design was presented as a recommendation only — not executed, pending user confirmation (it would provision 4 new topics + 4 continuously-running Flink statements).

---

## Step 8 — Implement the `c360_snapshot` Flink pipeline

**Prompt:** OK, let's go! Implement the c360 snapshot for me.

**Actions:**

- Ran `describe-flink-table` on `corebank.accounts`, `corebank.customers`, `corebank.transactions`, `digital.interactions.avro` first to confirm real Flink column types (all plain `VARCHAR`/`DOUBLE`/`TIMESTAMP_LTZ(3)` — no enum casting needed, and `corebank.transactions.ts` is already `TIMESTAMP_LTZ(3)`, correcting an assumption in the design doc).
- Created + launched Stages A–C from the design doc in parallel: `accounts_by_customer`, `txn_activity_by_customer` (joined through `corebank.accounts`), `recent_digital_interactions` (Top-N via `ROW_NUMBER()`, pivoted into `interaction_1/2/3_*` columns) — each its own `CREATE TABLE` + long-running `INSERT INTO`.
- First attempt at the final `c360_snapshot` join **FAILED**: `CURRENT_TIMESTAMP` isn't allowed as an output column on a query that produces retractions (Flink requires deterministic values for update messages). Fixed by dropping the `snapshot_updated_at` column — dropped and recreated the table (no data had been written yet).
- Re-ran the join; Flink accepted it but flagged 2 CRITICAL advisories (primary-key/upsert-key mismatch, and unbounded state growth without a TTL on the Top-N aggregations) — both are running healthy regardless, but noted as a pre-production TODO.
- Verified via `check-flink-statement-health` (all 7 statements — 3 CREATE, 4 INSERT — `RUNNING`/`COMPLETED`, no exceptions).
- Verified real output: `get-topic-config` + `list-schemas` on `c360_snapshot` (compacted, Avro key+value schemas registered), then `consume-messages` — caught the pipeline's upsert self-healing live: customer `43f68157-197d-4fd8-a37f-1d98a3284e6c`'s first row showed `account_count: 0` (written before the join's other side caught up), corrected moments later to `account_count: 2` with real interaction data.
- Tagged the new `c360_snapshot` topic `c360` + `source` via `add-tags-to-topic`, matching the established convention.

**Result:** 4 new topics live and streaming: `accounts_by_customer`, `txn_activity_by_customer`, `recent_digital_interactions`, and `c360_snapshot` (the final governed, compacted, Avro upsert view). Spot-checked a fully-joined record: 1 account (€5,827.29 balance), 3 transactions in the last 30 days (net –€236.71), and 2 of the last-3 digital interactions populated (LOGIN → LOGOUT, `interaction_3` correctly `null` — that customer only has 2 events in the dataset). The `c360_snapshot` design from Step 7 is now real, running infrastructure.

---

## Step 9 — Retag `c360_snapshot` as a data product, and confirm the pipeline end-to-end

**Prompt:** (list c360 topics) → tag `c360_snapshot` with `c360` + `data_product` → `c360_snapshot` is not a source topic, remove that tag → list c360 topics again.

**Actions:**

- Ran `search-topics-by-tag c360` to list current state before making changes — confirmed the 6 `c360`-tagged topics from Step 8, including `c360_snapshot` still carrying `source`.
- Created a new tag definition `data_product` via `create-topic-tags` (`c360` already existed), then assigned `c360` + `data_product` to `c360_snapshot` via `add-tags-to-topic` — the `c360` assignment was a harmless no-op (already present), `data_product` was new.
- User pointed out `c360_snapshot` is a derived/joined view, not a primary source — removed the `source` tag from it specifically via `remove-tag-from-entity` (the `source` tag definition and its use on the other 4 topics was left untouched).
- Re-ran `search-topics-by-tag c360` twice (after the add, and after the removal) to confirm each change landed correctly and nothing else was affected.

**Result:** `c360_snapshot` now correctly reflects its role in the pipeline — tagged `c360` + `data_product` only (no `source`). The other 5 `c360`-tagged topics (`corebank.accounts`, `corebank.customers`, `corebank.transactions`, `digital.interactions` [`raw`], `digital.interactions.avro` [`source`]) are unchanged. Combined with Step 8's live `consume-messages` check of a fully-joined record, this confirms the whole pipeline — from raw/governed sources through the 3 intermediate aggregates to the final `c360_snapshot` data product — is both running and correctly tagged end-to-end.

---
