# Build Guide — Customer 360 Live-Coding Environment

How to **build**, **operate** and **tear down** the environment behind the Customer 360 demo.
The demo itself — the prompts, the flow, the architecture — is in the [README](README.md).

| You want to… | Run |
|---|---|
| Build everything | `make up` |
| Check you are demo-ready | `make status` |
| Wipe what a live session built, keep the infrastructure | `make reset` |
| Remove everything and stop the billing | `make down` |

`make` with no arguments lists every target. Everything below is what those commands do, step by step, so you can run or debug each piece on its own.

---

## 1. What gets deployed

**Confluent Cloud** (Terraform, [`environment/terraform-confluent-aws`](environment/terraform-confluent-aws/))

- Environment (`customer-360-demo-environment-<suffix>`), Standard Kafka cluster (AWS `eu-west-1`, multi-zone) and Schema Registry
- Flink compute pool (serverless, 0–10 CFU)
- Service account (`customer-360-sa-<suffix>`) with RBAC, plus Kafka, Schema Registry and Flink API keys
- The four C360 source topics: `corebank.customers`, `corebank.accounts`, `corebank.transactions`, `digital.interactions`
- Four Datagen sample topics: `clickstream`, `orders`, `pageviews`, `stock_trades`

**On your machine**

- `environment/mcp-confluent/.env` — API keys for the helper scripts (not used by the AI assistant's own MCP login)
- MCP configuration for your AI assistant(s): Claude Code, GitHub Copilot, IBM Bob
- Synthetic Spanish banking data produced into the source topics

**AWS** (Terraform, [`environment/terraform-tableflow-aws`](environment/terraform-tableflow-aws/)) — storage for Tableflow, prepared by default so the assistant can switch Tableflow on during the demo (skip with `make up TABLEFLOW=0`)

- S3 bucket, IAM role, and a Confluent provider integration

**Open lakehouse** (built with Tableflow; `POLARIS=0` skips it) — SQL over the Tableflow tables with open-source engines, all local except two small AWS identities

- A local [kind](https://kind.sigs.k8s.io/) cluster running Apache Polaris (federating the Tableflow Iceberg REST catalog) and Trino
- In AWS (same Terraform stack): a read-only IAM role and an IAM user whose access key lets Polaris assume it
- In Confluent: one Tableflow API key (organization level), created through your `confluent login`

**Lightning Tables** (built with the lakehouse; `LIGHTNING=0` skips it) — real-time SQL on the *current state* of a topic, and a front end that shows it

- A read-only service account (`customer-360-live-<suffix>`, `DeveloperRead` only) with a Global API key: the only credential the front end queries with
- The Customer 360 live view, a small web app on the same kind cluster that queries the Lightning Table **over JDBC** (a read-only secret for queries; a separate write secret used only by its "Make something happen" button)
- Lightning Tables are enabled **by the build** on the two topics the build creates itself (the twin and the live feed, below). Not deployed by the build: the Lightning Table of `c360_snapshot`, because that topic is created live by the demo prompts. You enable it right afterwards (README, Prompt 11); setup takes several minutes

**The pre-built twin** (built with everything above; `PREBUILT=0` skips it) — a second, ready-made Customer 360 table for the second half of the demo

- `c360_snapshot_prebuilt`: the same 32-column, one-row-per-customer table the live prompts build into `c360_snapshot`, created at build time from the SQL in [`environment/prebuilt/`](environment/prebuilt/) by two Flink statements that keep it up to date, with **Tableflow (Iceberg) and a Lightning Table already enabled on it**
- `c360_live_activity`: a small Avro topic for the live event feed, written by a plain producer (no Flink) when the button or `make demo-changes` runs, with its own Lightning Table — the *fast* lane of the demo's "two speeds" (§4.8)

`<suffix>` is a random 8-character hex (for example `a1b2c3d4`) generated on the first build and kept until `make down`. It makes the environment and service-account names unique in the organization, and the Tableflow IAM role unique in the AWS account — see [§6.3](#63-running-more-than-one-demo).

**Time:** about 10–15 minutes of provisioning, then a further few minutes before the two Lightning Tables are ACTIVE (about 6) and up to about 15 before the twin's first Iceberg commit shows in Trino. Those waits overlap the end of the build, so `make up` returns before they finish: check `make lightning-status` and `make prebuilt-status`.

---

## 2. Prerequisites

| Tool | Needed for | Notes |
|---|---|---|
| `terraform` ≥ 1.5 | infrastructure | |
| `jq`, `curl` | every script | |
| `python3` ≥ 3.8 | data generation | the script creates its own venv |
| `mise` + Node 22 | the Confluent MCP server | `mise install node@22`. The server's native addon only ships binaries up to Node 22, so Node is pinned through `env.PATH` in the MCP config (not through a wrapper command, which would break the org MCP allowlist) |
| `confluent` CLI | Tableflow enable/disable, and `make reset` | required for the default build; optional with `TABLEFLOW=0` |
| `aws` CLI | Tableflow storage | required for the default build; you must be authenticated first (see §4.6); optional with `TABLEFLOW=0` |
| `docker`, `kind`, `kubectl`, `helm`, `envsubst` | Polaris + Trino (§4.7) | required for the default build; Docker must be running; optional with `POLARIS=0` or `TABLEFLOW=0` |
| An AI assistant | the demo | Claude Code, VS Code + GitHub Copilot, or IBM Bob |

You also need a **Confluent Cloud account** and a **Cloud API key** with the *Cloud resource management* scope: <https://confluent.cloud/settings/api-keys>.

```bash
make check        # verifies everything above and tells you what is missing
```

### Credentials

Terraform needs the Cloud API key and secret. `make` never prompts; it reads them from, in order:

1. the environment — `export TF_VAR_confluent_cloud_api_key=… TF_VAR_confluent_cloud_api_secret=…`
2. `environment/terraform-confluent-aws/.env.local` (gitignored) containing those two `export` lines
3. `environment/terraform-confluent-aws/terraform.tfvars` (gitignored)

```bash
make check-creds  # tells you which one it found, or what to do
```

To change names, region or Flink size, copy `terraform.tfvars.example` to `terraform.tfvars` in `environment/terraform-confluent-aws/` and edit it before building.

---

## 3. Fast path

```bash
make up                              # check → preflights → infra → MCP env → Tableflow storage → data → pre-built twin + live feed → Polaris + Trino → live view → wire Claude Code
make up AI=copilot                   # …wire GitHub Copilot instead
make up AI=all                       # …wire every assistant (Claude Code, Copilot and Bob)
make up AI=claude && make ai-bob     # …Claude Code and Bob only (AI takes ONE value; add the second tool afterwards)
make up POLARIS=0                    # …without Polaris + Trino (no Docker needed)
make up TABLEFLOW=0                  # …without Tableflow, and therefore without Polaris (no AWS login needed)
make status                          # confirm
make prebuilt-status                 # twin, live feed, Tableflow and both Lightning Tables (the last two take minutes to turn ACTIVE)
```

With Tableflow on (the default) your AWS login is checked **first**, so a missing login fails in seconds instead of after ten minutes of provisioning. The Polaris and Lightning preflights run before anything exists, so on a first build they only check tools, Docker, the logins and Lightning's regional availability; they repeat the full check when Polaris and the live view are deployed.

`make up` is just these steps in order, each run as its own `make` so a failure stops the run where it happened. Re-running is safe — Terraform is idempotent and the config writers only change a file when its content would change. One exception: `make data` produces *more* records every time it runs.

---

## 4. Step by step

### 4.1 Check tools — `make check`

Fails (non-zero) if a required tool, or Node 22 under `mise`, is missing.

### 4.2 Provision Confluent Cloud — `make infra`

Runs `terraform init` and `terraform apply -auto-approve` in `environment/terraform-confluent-aws`.

```bash
make infra-plan   # preview first
make infra
make info         # environment, cluster, Flink pool, console URLs
```

By hand: `cd environment/terraform-confluent-aws && terraform init && terraform apply`.

### 4.3 Export API keys for the helper scripts — `make mcp-env`

Writes `environment/mcp-confluent/.env` (mode 600) from the Terraform outputs. A previous file is saved as `.env.backup` only if the content changed. The data generator and reset script read credentials from Terraform outputs and from this file.

### 4.4 Produce data — `make data`

Creates a Python virtualenv, then produces synthetic Spanish banking data (EUR, MCC codes) into the source topics.

```bash
make data                                              # 200 customers, 1000 transactions, 800 interactions
make data CUSTOMERS=500 TRANSACTIONS=2000 INTERACTIONS=1500
make verify                                            # exits non-zero if a source topic is missing
```

### 4.5 Connect your AI assistant — `make ai-*`

One MCP server definition, one adapter per tool. Each adapter **merges** the `confluent` server into the tool's existing config (other servers are kept), writes a `.bak` only when something changes, and refuses to touch a file that isn't valid JSON.

| Target | Writes | Then |
|---|---|---|
| `make ai-claude` | `./.mcp.json` | Open a **new** Claude Code session — it only reads `.mcp.json` at start. VS Code: fully quit and reopen. |
| `make ai-copilot` | `./.vscode/mcp.json` | In VS Code run **MCP: List Servers**, start and trust `confluent`; use Copilot Chat in **Agent** mode. |
| `make ai-bob` | `~/.bob/settings/mcp.json` | Restart Bob, then **Settings → MCP Servers → Authenticate** `confluent`. |
| `make ai-all` | all three | |
| `make context` | `CLAUDE.md`, `.github/copilot-instructions.md`, `.bob/rules/c360-environment.md` | pins every assistant to this demo's environment (see below); each `make ai-*` already does it for its own tool |
| `make ai-status` | — | shows which assistants have the server configured **and** an up-to-date environment context |

`make up AI=<tool>` wires **one** tool (`claude`, `copilot`, `bob`, or `all` for every one of them). For a pair, build with one and add the other: `make up AI=claude && make ai-bob`.

The server runs as the bare `npx -y @confluentinc/mcp-confluent --oauth`, so **every assistant needs a one-time Confluent Cloud login** in the browser (Claude Code: on the first tool call; Copilot: when you start the server; Bob: Settings → MCP Servers → Authenticate). `make` can't do this step for you, and each assistant keeps its own login — so do it once per assistant **before a live session**, not on stage.

Two things follow from OAuth:

- Sign in to the **organization that owns the demo environment** if you belong to several.
- The login is *you*, not the demo's service account, and an OAuth connection has **no default environment or cluster** — the assistant chooses per tool call. Left alone it will happily list topics from another environment you can see (for example your personal one). `make ai-*` therefore also writes a small instruction file per tool, generated from Terraform, that gives the assistant the demo's organization, environment, cluster, Flink pool and catalog/database names and tells it to use only those — and, when Tableflow storage is deployed, the bucket, the provider integration and the exact `create-tableflow-topic` payload:

  | Assistant | Reads |
  |---|---|
  | Claude Code | `CLAUDE.md` |
  | GitHub Copilot | `.github/copilot-instructions.md` |
  | IBM Bob | `.bob/rules/` |

  These files are generated, gitignored, and merged between markers so your own text in the same file is kept. They are **guidance, not enforcement**: restart the assistant session after they change, and re-run `make context` after any rebuild (`make ai-status` flags a stale one). `make down` removes them. For hard enforcement you would use a direct, API-key MCP connection scoped to the demo cluster instead of OAuth.

Verify it works by asking: *"Is the Confluent MCP server available?"* A healthy answer lists the available tools (Bob reported 66). Then ask *"List my Kafka topics"* and check the answer shows `corebank.*` and the cluster `customer-360-cluster` — not another environment's topics.

Also useful:

- `make ai-kill-mcp` — stray `mcp-confluent` processes slow the VS Code extension down.
- The Claude **VS Code extension / Claude Desktop** read global settings rather than `./.mcp.json`: `scripts/configure-claude-mcp.sh --vscode` or `--desktop`.
- After a rebuild gives you a new cluster: `make ai-claude` (or `scripts/reconfigure-mcp.sh`) refreshes the config and clears Claude Code's stale approve/reject state.

### 4.6 Tableflow storage — prepared at build, enabled during the demo

Tableflow materialises a topic as an Iceberg (or Delta) table in **your** S3 bucket. The build prepares everything it needs; the demo then only has to switch it on for `c360_snapshot`, which you ask your assistant to do (README, Phase 7).

What `make up` does for Tableflow (on by default; `TABLEFLOW=0` skips all of it):

1. `make tableflow-preflight` — checks your AWS login and the `confluent` CLI **before** anything is provisioned.
2. `make tableflow-up` — builds the S3 bucket, IAM role, Confluent provider integration and the IAM trust policy (two Terraform phases, below).
3. `make context` (automatic) — tells each assistant the bucket, the provider integration ID and the exact `create-tableflow-topic` payload, so it enables Tableflow on the prepared storage instead of inventing its own.

```bash
aws sts get-caller-identity              # you must already be authenticated before make up
make tableflow-status                    # AWS side, trust policy, topics with Tableflow enabled
```

If the assistant struggles during a live session, the scripted equivalent is a fallback: `make tableflow-enable` (`TOPIC=…`, `FORMAT=DELTA` to change) and `make tableflow-disable TOPIC=…`. It uses your `confluent login`, or the Cloud API key Terraform already uses.

`tableflow-up` runs Terraform in two phases because Confluent only reveals its role ARN and external ID *after* the provider integration exists: phase 1 creates the bucket, role and integration; phase 2 writes those values back into the IAM trust policy. It is non-interactive, re-runnable (phase-2 values are preserved), and the same code `scripts/startup-demo.sh` uses. Authentication: a working `aws` session, or `AWS_PROFILE`, or — if neither — the first profile in `~/.aws/credentials`. Confluent employees: run your usual `assume <role>` first.

**Permissions.** The provider integration belongs to the user behind the Cloud API key Terraform uses; the assistant acts as the user who signed in to MCP over OAuth. If they are the same person (the usual case) nothing more is needed. If not, that user needs the `Assigner` or `ResourceOwner` role on the provider integration — see [Grant Role-Based Access for Tableflow](https://docs.confluent.io/cloud/current/topics/tableflow/operate/tableflow-rbac.html).

**Write mode.** `c360_snapshot` is created with a primary key, so it is a compacted topic and Tableflow materialises it in *upsert* mode (latest row per key; see [write modes](https://docs.confluent.io/cloud/current/topics/tableflow/concepts/write-modes.html)). Tableflow fixes the mode the first time it materialises a topic and it cannot be changed afterwards: to change it, delete the Tableflow topic and the Kafka topic and recreate both. Enable Tableflow once the topic has its final definition — which is where Phase 7 sits.

### 4.7 Query the Iceberg tables with SQL — Polaris + Trino

Tableflow writes standard Iceberg files to your bucket; this step adds the open-source side so you can **query them with SQL** during the demo: Apache Polaris (an Iceberg REST catalog) federates the Tableflow catalog, and Trino reads it. The same pattern as the `workshop-tableflow-polaris` project, driven by `make`:

```text
Tableflow (Iceberg in your S3)  ──IRC──▶  Polaris (federated catalog "tableflow")  ──REST──▶  Trino
                                          assumes a READ-ONLY AWS role and vends short-lived,
                                          table-scoped credentials: Trino holds no storage keys
```

```bash
make polaris-preflight                 # Docker, kind, kubectl, helm, AWS + Confluent logins (fails fast)
make polaris-up                        # part of make up whenever Tableflow is (skip with POLARIS=0)
make polaris-status                    # pods, and the tables Trino can see
make trino-query SQL='SHOW SCHEMAS FROM polaris'
make trino-shell                       # interactive Trino
make c360-queries                      # list the ready-made Customer 360 demo queries (Q=3 runs one, Q=all runs them all)
```

The demo queries live in `environment/polaris/queries/NN-name.sql` (a `-- title:` and `-- ask:` header, `__SCHEMA__` for the cluster-id schema); add a file there and it appears in the list. In `make trino-query`, write `$$` for a literal `$` (for Iceberg metadata tables such as `"c360_snapshot$$snapshots"`); calling `./scripts/polaris.sh query '…'` directly, or piping the SQL on stdin (`./scripts/polaris.sh query <<'SQL' … SQL`), needs no escaping — the form to prefer for SQL with string literals.

`make polaris-up` is idempotent and does, in order: (1) Terraform adds the read-only role, an IAM user and its access key to the Tableflow stack (`polaris.auto.tfvars`); (2) creates a Tableflow API key with your `confluent login`; (3) creates the kind cluster `c360-<suffix>`; (4) deploys Polaris and registers the federated catalog plus a read-only principal; (5) installs Trino with one Iceberg catalog, `polaris`; (6) refreshes the assistant context so Claude/Bob know how to query.

Query the demo data product (the schema is the Kafka cluster id; the table appears after Tableflow is enabled and has committed once, about 5 minutes):

```bash
make trino-query SQL='SELECT customer_id, segment, net_balance FROM polaris."lkc-xxxxxx".c360_snapshot LIMIT 5'
```

Good to know:

- **Secrets** (Polaris root secret, reader credentials, the Tableflow API key) live in `environment/polaris/.state/` (gitignored, mode 600) and are passed to Kubernetes through stdin, never on a command line. The AWS access key is in the Terraform state, like the other keys in this repo.
- **Polaris keeps its state in memory.** If its pod restarts the catalog is gone; run `make polaris-up` again to rebuild it.
- **Latency:** Kafka → `c360_snapshot` takes seconds, but Tableflow commits to Iceberg in batches of about 5 minutes, so Trino sees changes a few minutes later. Upsert tables are stored with position deletes; Trino applies them, so counts are correct.
- **Cost / footprint:** nothing runs in the cloud except the two IAM identities. Locally it needs a few GB of Docker memory (Trino is set to a 2 GB heap).
- **Remove it:** `make polaris-down` (kind cluster, Tableflow API key, AWS reader identities). `make down` does this too.

**Making something happen during the demo — `make demo-changes`.** Not part of the build: run it live to add a small burst of new data (a mobile `LOGIN → VIEW_BALANCE → PAYMENT` session plus one card purchase, timestamped now, for `CHANGES` customers, default 3) and watch it travel raw topic → Avro replica → `c360_snapshot` → Tableflow → Iceberg. It picks the richest customers with no digital activity yet (the top of the "digital-inactive" query), so each run uses the next ones; `DRY_RUN=1` previews the pick and `IDS=<id>,<id>` chooses the customers yourself. It reads accounts and interactions straight from Kafka and writes with the Kafka credentials `make data` uses, so it needs no query engine and serves any later iteration that wants a visible change (for example the Lightning queries). It adds records to the source topics: `make reset` does not remove them, since those topics are Terraform-managed.

### 4.8 Real-time queries — Lightning Tables and the live front end

A **Lightning Table** makes the current state of a Kafka topic queryable with low-latency SQL (about a second after the record is committed to the topic — see "Two speeds" below for what that means when Flink writes the topic), from the Console, the Query API, the CLI, JDBC or MCP — with no consumer to write and no database to run. It is the real-time counterpart of Tableflow: Lightning serves *now*, Tableflow + Polaris + Trino serve history and analytics. Sources: [Lightning Tables](https://docs.confluent.io/cloud/current/lightning-tables/overview.html), [query API](https://docs.confluent.io/cloud/current/lightning-tables/query/api.html), [SQL reference](https://docs.confluent.io/cloud/current/lightning-tables/query/sql-reference.html).

What the build does (`make lightning-up`, part of `make up`; `LIGHTNING=0` skips it):

1. creates a **read-only service account** (`DeveloperRead` on topics and Schema Registry) and a **Global API key** for it;
2. builds the app image (a JRE plus the Confluent JDBC driver, downloaded from the Confluent Maven repository and checksum-verified) and deploys the **Customer 360 live view** on the kind cluster, with two Kubernetes secrets: the read-only key (queries) and the Kafka/Schema Registry credentials (only the "Make something happen" button uses them);
3. tells the assistants how to enable and query Lightning (`make context`).

The Lightning Tables themselves are enabled earlier in the build, by `make prebuilt-up` (§4.9): one on the twin and one on the live-feed topic. They take about 6 minutes to become ACTIVE, so the live view may show "still being set up" at first.

During the demo:

```bash
make lightning-enable            # after c360_snapshot exists (README Prompt 11); takes several minutes
make lightning-status            # is the Lightning Table ready?
make lightning-query LSQL='SELECT full_name, segment FROM c360_snapshot WHERE customer_id = '"'"'<id>'"'"''
make c360-live                   # opens the live front end at http://localhost:8088 (APP_PORT to change)
make lightning-disable           # delete the Lightning Table of TOPIC (default c360_snapshot) when you are done (see Cost below)
make lightning-disable TOPIC=c360_live_activity          # the feed's table
make lightning-disable TOPIC=c360_snapshot_prebuilt      # the twin's table
make lightning-down              # remove the front end, the identity and the API key (tables stay)
```

Good to know:

- **Two speeds — the latency trade-off the demo accepts.** A Lightning Table sees a record once it is *committed* to its topic. A topic written by a plain producer commits immediately: queryable in about a second (Confluent's published target is under 100 ms p50 on a busy topic; about 1 s on a quiet one, which is what the demo measures). A topic written by a **Flink statement** commits only on Flink's checkpoint: Confluent Cloud Flink gives exactly-once by default, writes to Kafka in transactions that commit about every 60 s, and a Lightning Table (like any `read_committed` consumer) cannot see the rows before that. So a change shows up in the Customer 360 table **0–60 s** after it happens, and every further Flink statement chained behind it adds up to another interval. The demo therefore runs two lanes: `c360_live_activity` (fast, raw events, written by `make demo-changes` / the button with a plain producer) and `c360_snapshot_prebuilt` (aggregated by Flink, up to a minute behind), and the live view shows both with a progress box. What we give up, knowingly: the fast lane has no aggregation and no joins (Lightning is one table per query), so it carries only the customer's name and segment; the aggregated lane is a minute behind. Options **not** taken: `kafka.consumer.isolation-level = 'read-uncommitted'` (it only affects Flink's own reads, so it would not make Lightning faster, and it allows duplicates between Flink statements); a shorter Flink checkpoint interval (not configurable today; Confluent is evaluating more frequent commits). Sources: [Delivery guarantees and latency in Confluent Cloud for Flink](https://docs.confluent.io/cloud/current/flink/concepts/delivery-guarantees.html), Confluent's Lightning Tables freshness tests (internal).
- **Natural language (MCP).** The build also adds a second MCP server, `confluent-rtce`, to every assistant that already has `confluent` (Claude Code, Copilot, Bob): the Real-Time Context Engine endpoint `https://mcp.<region>.aws.confluent.cloud/mcp/v1/context-engine/organizations/<org>/environments/<env>/kafka-clusters/<cluster>`, authenticated with the **read-only** Global API key (HTTP Basic), so there is no sign-in. The assistant uses its three tools — `listTopics`, `getMetadata`, `queryData` (max 200 rows, 20 s timeout) — and the generated context file tells it when to prefer Lightning (current state) over Trino (aggregates, joins, history). `make ai-status` shows `+ rtce` per assistant; `make lightning-down` removes the entry. The key is written into those config files (gitignored; Bob's is global at `~/.bob/settings/mcp.json`, with a `.bak`), so treat them as credentials — the key can only read. Open a **new** session after building: assistants read MCP config at start.
- **Names — Lightning Tables vs the Real-Time Context Engine (RTCE).** They are the same thing at different layers. A *Lightning Table* is the managed, low-latency table you enable per topic; *Lightning queries* are SQL against it (Console, API, CLI, JDBC). The *Real-Time Context Engine* was the original name of the product (GA May 2026, for AI agents) and is now the **MCP interface** to Lightning Tables; Confluent is renaming it to Lightning Tables across the company, which is why the CLI and API still say `rtce` (`confluent rtce rtce-topic create`, `/rtce/v1/rtce-topics`). One table per topic, enabled and billed once, same permissions and API keys for every path.
- **Cost — Lightning Tables are billed.** About $0.105 per CCU-hour, metered every minute: while data flows into the topic a table bills at least 1 CCU (roughly $75 a month, so a few cents per demo hour); with no data and no queries it scales to zero and you pay only storage (source: Confluent's internal Lightning Tables pricing page; check current pricing). A default build therefore has **two** Lightning Tables (the twin and the live feed), and three once Prompt 11 enables `c360_snapshot`. Both bill only while data flows into their topics: for the twin right after the build, while its Flink statement fills it, and then only briefly after each button press; for the feed only after each press. An idle table scales to zero and costs storage only. Run `make lightning-disable TOPIC=<topic>` for each when you are done, or `make prebuilt-down` to remove the twin and the feed entirely. `make down` removes them with the cluster.
- **How the app queries: JDBC.** The live view uses the Confluent JDBC driver (`io.confluent.jdbc:confluent-jdbc:1.0.0`, driver class `io.confluent.jdbc.avatica.ConfluentJdbcDriver`, Java 17+). The URL is `jdbc:confluent:lightning://sql.<region>.aws.confluent.cloud?environment-id=<env>&lkc-id=<cluster>` and the Global API key and secret are the connection's `user` and `password` — never in the URL. In a JDBC client's schema browser the catalog is the environment, the schema is the Kafka cluster and each Lightning Table is a table. The driver is a Java library, so the Python server starts a JVM in-process (JPype) and calls plain JDBC (`DriverManager` → `Statement` → `ResultSet`; tables listed with `DatabaseMetaData.getTables`). Connections are read-only and autocommit. **Any JDBC client works the same way:** point DBeaver, DataGrip or sqlline at that URL with the read-only key (`make lightning-status` prints the key id; the secret is in `environment/lightning-app/.state/lightning.env`). `make lightning-query` and the live view's terminal siblings use the HTTP Query API instead.
- **Requirements:** AWS cluster in a supported region (`eu-west-1` is), a topic with a schema (Avro/Protobuf/JSON Schema), and `CloudClusterAdmin`/`ResourceOwner` to enable a table. `make lightning-preflight` checks the region.
- **SQL limits:** one table per query; key lookups, `WHERE`, `ORDER BY`, `LIMIT` only — no joins, aggregates, subqueries or DDL. That is why the data product is precomputed into `c360_snapshot`.
- **Upsert vs append:** a compacted topic (primary key) becomes an *upsert* table (current row per key); the demo's `c360_snapshot` and the twin are of this kind. The live feed `c360_live_activity` has no primary key semantics and is an *append* table: every event is a row, which is why its page query is `ORDER BY ts DESC LIMIT 8`.
- **What the build can and cannot enable:** it enables Lightning on the topics it creates itself — the twin and the live feed. It cannot do it for `c360_snapshot`, which does not exist until the prompts create it; that is why Prompt 11 follows the deploy, and why the several minutes of setup overlap with the next phases.
- **Secrets:** the API key lives in `environment/lightning-app/.state/` (gitignored, mode 600) and reaches Kubernetes through stdin. Lightning is available over the public endpoint; the Console and CLI do not work over a private network.
- **CLI version:** the installed CLI enables tables with `confluent rtce rtce-topic create`; newer versions add `confluent lightning query`. `make lightning-query` calls the same API either way.

### 4.9 The pre-built twin — `c360_snapshot_prebuilt`

The demo builds the Customer 360 data product **live** with the assistant (README Phases 1–4). That part is non-deterministic by nature — the assistant may name or shape columns differently from run to run — and Tableflow and Lightning need minutes to warm up. The second half of the demo (Trino, Lightning, the live front end) needs known columns and a table that is ready *now*. So the build also creates a **twin**: `c360_snapshot_prebuilt`, "the one prepared earlier".

What `make up` does for it (`make prebuilt-up`; `PREBUILT=0` skips it; it runs after `make data`, before Polaris and Lightning):

1. creates the table (`environment/prebuilt/01-table.sql`: 32 columns, primary key `customer_id`, compacted, Avro) and starts the continuous `INSERT` (`02-populate.sql`) as two Flink statements, `c360-prebuilt-table` and `c360-prebuilt-populate`. It reads the raw `digital.interactions` topic directly and parses the JSON itself, so it neither needs nor collides with the Avro replica the live prompts create;
2. enables **Tableflow** (Iceberg) on it, in the prepared bucket;
3. enables a **Lightning Table** on it (billed; see §4.8) — skipped with `LIGHTNING=0`;
4. creates the **live-feed topic** `c360_live_activity` (3 partitions, Avro schema `environment/data-generation/schemas/activity-value.avsc`, registered at build time so the Lightning Table can be enabled before any data exists) and enables a second Lightning Table on it. No Flink touches this topic: `make demo-changes` and the button write each new event to it with a plain producer, which is why it is the fast lane (§4.8, "Two speeds"). It is billed like any Lightning Table (about 1 CCU while events flow; storage only when idle).

```bash
make prebuilt-status      # the two statements, the topics, Tableflow and both Lightning Tables
make prebuilt-up          # (re)build it; safe to repeat
make prebuilt-down        # remove it: Lightning, Tableflow, statements, topics (twin and live feed), schemas
```

How the rest of the system treats it:

- **Default table.** The ready-made Trino queries (`make c360-queries`), the live front end (`make c360-live`) and the assistants' context use the twin whenever it exists. Point them at the live-built table with `DEMO_TOPIC=c360_snapshot` (for example `make lightning-up DEMO_TOPIC=c360_snapshot` redeploys the app on it, `make c360-queries DEMO_TOPIC=c360_snapshot Q=all` queries it).
- **`make reset` leaves it alone** — its statements (`c360-prebuilt-*`), topic and schemas are protected — so a reset gives you a clean live session with the twin still warm. `make down` removes it first, with everything else.
- **Not tagged**, so the tag-based prompts don't list it as a `c360` topic. It does appear in a plain "list my topics", so name it in your narration.
- **Cost.** Two Flink statements keep running (a small share of the pool's CFUs) and its Lightning Table bills about 1 CCU while data flows (see §4.8). `make prebuilt-down` or `make lightning-disable TOPIC=c360_snapshot_prebuilt` stops that.
- **`make demo-changes` feeds all of it**: new interactions and purchases reach the source topics (so the live table and the twin alike, through Flink) and, directly, the live feed `c360_live_activity`. If that topic does not exist the script says so and carries on without it.
- **Known warnings.** Flink flags the `INSERT` for a missing state TTL and an upsert key it cannot derive. Both are harmless at 200 customers; set a state TTL before production volumes.

### 4.10 Verify — `make status`

Shows the environment, whether all four source topics exist, and which assistants are wired. Then ask your assistant: *"Can you list all my Kafka topics?"*

---

## 5. Repository layout

```text
Makefile                 entry point — `make` lists every target
mk/NN-*.mk               one file per area (setup, infra, data, prebuilt, ai, tableflow, polaris, lightning); auto-included
scripts/                 every executable
  lib.sh                   shared helpers          status.sh        info / topics / verify / urls
  context.sh               pin assistants to the demo environment
  ai-mcp-config.sh         MCP wiring per tool     tableflow.sh     Tableflow up / enable / disable
  polaris.sh               Polaris + Trino on kind (part of the default build)
  lightning.sh             Lightning Tables: identity, live front end, enable, query
  prebuilt.sh              the pre-built twin and the live-feed topic: Flink statements, Tableflow, Lightning
  reset-demo.sh            `make reset`            startup-demo.sh  interactive status + bootstrap
  bootstrap.sh             guided first-time build cleanup-demo.sh  interactive reset / destroy menu
  generate-data.sh         `make data`             cleanup.sh       destroy Confluent + local files
  configure-claude-mcp.sh  VS Code / Desktop       reconfigure-mcp.sh  regenerate MCP config
environment/
  terraform-confluent-aws/   Confluent Cloud infrastructure
  terraform-tableflow-aws/   AWS side for Tableflow (default; TABLEFLOW=0 skips it)
  polaris/                   Kubernetes manifests for Polaris and Trino; .state/ is gitignored
  prebuilt/                  the twin's two Flink statements (01-table.sql, 02-populate.sql); .state/ is gitignored
  lightning-app/             the real-time Customer 360 front end (server, page, Dockerfile, manifest); .state/ is gitignored
  data-generation/           Python producers (incl. demo_changes.py: the button / `make demo-changes`) and Avro schemas (incl. activity-value.avsc, the live feed)
  mcp-confluent/             generated .env (gitignored)
.agents/skills/ + skills-lock.json   agent skills managed by the skills tool; the lock file must stay at the root
.mcp.json                            generated; Claude Code only looks for it at the root
```

The guided scripts (`startup-demo.sh`, `bootstrap.sh`, `cleanup-demo.sh`, `cleanup.sh`) predate the Makefile and prompt interactively; they still work and share the same underlying scripts. Prefer `make` for repeatable runs.

---

## 6. Operating the environment

### 6.1 Reset between runs — `make reset`

Brings the environment back to "freshly built" so you can run the live session again, without paying to re-provision.

```bash
make reset-plan   # show exactly what would be deleted; changes nothing
make reset        # shows the plan, asks to confirm, deletes
make reset YES=1  # no prompt
```

What counts as *built by the session* is **derived from the live environment**, not from a list of names, so it still works when a session names things differently:

| Deleted | How it is found |
|---|---|
| Every Flink statement | Terraform creates none, so all of them belong to the session |
| Every topic Terraform does not manage | live topic list minus Terraform state; internal `_*` topics and connector `error-/dlq-/success-` topics are skipped |
| Their `-value` / `-key` schema subjects (soft and hard delete) | derived from the topics above |
| Tableflow on those topics | disabled first (including any the assistant enabled), when the AWS side is deployed |

Kept: the cluster, Flink pool, service account, every Terraform-managed topic (`corebank.*`, `digital.interactions`, the Datagen topics) and **the pre-built twin** (§4.9: its `c360-prebuilt-*` statements, topic and schemas, the live-feed topic `c360_live_activity`, plus the statements Tableflow issues itself). If the Terraform-managed topic list can't be read, the script **refuses to run** rather than guess.

The Iceberg files Tableflow wrote stay in the S3 bucket after a reset; they are removed with the bucket by `make down`.

**Tags** live in the Schema Registry catalog and are not removed by the script. Ask your assistant: *"Delete the tags c360, source and data_product."*

### 6.2 Cost

The Kafka cluster and Flink pool bill while they exist. A reset keeps them. If the environment will sit idle, tear it down (§7) — rebuilding is ~15 minutes. The Lightning Tables (§4.8) are billed separately while data flows into their topics, and a default build creates two (the twin and the live feed) — see §4.8 for what each costs and how to switch them off between demos.

### 6.3 Running more than one demo

Several people — or several demos of your own — can share one Confluent organization (and one AWS account for Tableflow) without clashing, because every deployment gets its own suffix.

- **One clone or `git worktree` per concurrent demo.** Terraform state and the generated files (`.mcp.json`, `CLAUDE.md`, the MCP `.env`) live in the checkout, so one checkout holds one deployment. Do not try to run two from the same folder.
- **Suffix:** random by default. To choose it, set it before the first build: `TF_VAR_name_suffix=ogomez make up` (or `name_suffix` in `terraform.tfvars`). It must be empty or 1–24 lowercase letters, digits and hyphens.
- **Pointing the assistant at the right one:** each clone's `make context` writes that clone's environment and cluster IDs into its own `CLAUDE.md`, Copilot and Bob files, so an assistant opened in a clone uses that clone's environment.
- Changing the suffix on an *existing* deployment renames the environment and service account in place, but replaces the Tableflow IAM role. Pick it before the first build.

---

## 7. Teardown

**Recommended sequence**

```bash
make reset-plan          # optional: see what the session left behind
make down                # asks you to type 'destroy'
```

`make down` (option 2 of `scripts/cleanup-demo.sh`) then:

1. removes session-built resources (the same logic as `make reset`, non-fatal), so Terraform doesn't trip over objects it doesn't manage;
2. runs `terraform destroy` on the Confluent infrastructure;
3. runs `terraform destroy` on the Tableflow AWS side, if it was deployed (and clears its state/vars). The bucket is emptied and deleted together with whatever Tableflow wrote into it (`bucket_force_destroy`, on by default; set it to `false` to protect the data).

If you built the pre-built twin (§4.9), `make down` first switches off Tableflow and the Lightning Tables (the twin's and the live feed's), removes its statements and deletes the twin and `c360_live_activity` topics with their schemas (`scripts/prebuilt.sh down`), so the cluster can be deleted cleanly. Only that part: `make prebuilt-down`.

If you built the Lightning front end (§4.8), `make down` also removes it first (`scripts/lightning.sh down`: the app, the read-only service account and its API key; Lightning Tables go away with the cluster). Only that part: `make lightning-down`.

If you built the open lakehouse (§4.7), `make down` first removes the kind cluster and the Tableflow API key (`scripts/polaris.sh down --no-aws`); the AWS reader identities go with the Tableflow stack. Only that part: `make polaris-down`.

Only the AWS side: `make tableflow-destroy` (asks you to type `yes`). Only Confluent plus local credentials and MCP files: `scripts/cleanup.sh` (several typed confirmations).

**Local leftovers** — nothing here is billable, but it goes stale once the cluster is gone:

| File | Why it's stale | Remove |
|---|---|---|
| `CLAUDE.md`, `.github/copilot-instructions.md`, `.bob/rules/c360-environment.md` | name an environment that no longer exists | removed automatically by `make down` (`scripts/context.sh sync`); your own text in those files is kept |
| `environment/mcp-confluent/.env*` | points at a deleted cluster | regenerated by the next `make mcp-env` |
| `./.mcp.json`, `./.vscode/mcp.json` | harmless (gitignored, no cluster details), but Claude Code caches approvals | delete them, or `make ai-claude` / `make ai-copilot` to refresh |
| `~/.bob/settings/mcp.json` | global; holds your other servers | `jq 'del(.mcpServers.confluent)' ~/.bob/settings/mcp.json > ~/.bob/settings/mcp.json.new && mv ~/.bob/settings/mcp.json.new ~/.bob/settings/mcp.json` |
| `environment/terraform-confluent-aws/.env.local` | your API key | **`make down` deletes it** — export `TF_VAR_confluent_cloud_api_key/secret` or recreate the file before the next `make up` |

**Verify nothing is left running:** `make info` should say the infrastructure is not deployed, and the Confluent Cloud console should show no `customer-360-demo-environment-…`.

**Manual cleanup** if a script fails part-way:

```bash
confluent flink statement list   --environment <env-id>
confluent flink statement delete <name> --environment <env-id>
confluent kafka topic delete <topic> --cluster <cluster-id> --environment <env-id>
confluent schema-registry schema delete --subject <topic>-value --version all --permanent --environment <env-id>
```

---

## 8. Troubleshooting the build

| Symptom | Fix |
|---|---|
| `make check-creds` fails / Terraform `error authorizing Confluent Cloud Client` | Provide an **organization-level** Cloud API key (not cluster-scoped) — see §2. |
| `make check` says Node 22 missing | `mise install node@22`. Newer Node versions break the MCP server's native addon. |
| Assistant says it has no Confluent tools | `make ai-status`; re-run the right `make ai-*`; open a **new** session (Claude Code and Copilot read config at start); then make a tool call to trigger the OAuth login. VS Code: fully quit (Cmd+Q) and reopen. |
| Claude Code silently drops the server | The org allowlist only accepts the bare `npx -y @confluentinc/mcp-confluent --oauth` command. Don't wrap it in `mise exec` or pin a version — `make ai-claude` writes the compatible form. |
| Assistant lists topics from the **wrong environment** (e.g. your personal one) | Run `make ai-status`: if context is *missing* or *STALE*, run `make context`, then start a **new** session / task. OAuth has no default environment, so the assistant needs the context file. |
| VS Code is slow after many sessions | `make ai-kill-mcp` |
| Copilot doesn't list `confluent` | Check `./.vscode/mcp.json` exists; run **MCP: List Servers** and start/trust it; Agent mode only. |
| Bob shows "Needs authentication" | Settings → MCP Servers → Authenticate. Bob needs a restart after `make ai-bob`. |
| `make data` fails with *Topic does not exist* | `make verify`; if topics are missing run `make infra`. Credentials come from `environment/mcp-confluent/.env` — run `make mcp-env`. |
| `make verify` fails after `make down` | Expected — there is nothing deployed. |
| `make tableflow-up`: *AWS auth failed* | Authenticate (`assume <role>`, `aws sso login --profile <p>`, or `aws configure`) and re-run. |
| Tableflow topics fail; trust policy says *deny-all* | Phase 2 didn't finish. Re-run `make tableflow-up`; check with `make tableflow-status`. |
| `make tableflow-enable`: *not deployed* | Run `make tableflow-up` first. |
| `make up` stops at the AWS check | By design — it fails before provisioning. Authenticate (§4.6) or build without Tableflow: `make up TABLEFLOW=0`. |
| `make up` stops at `check-creds` / Terraform authorization after a `make down` | `make down` deletes `environment/terraform-confluent-aws/.env.local` (your Cloud API key). Export `TF_VAR_confluent_cloud_api_key/secret` or recreate the file (§2). |
| Tableflow topic goes `FAILED`/suspended with *Unable to assume the IAM role…* although the trust policy has the Confluent role and external ID | Confluent also needs `sts:TagSession` in the trust policy (included since this fix). On an older deployment run `make tableflow-up` to apply it, wait ~1 minute for IAM to propagate, then resume the topic in the Confluent Cloud UI (the CLI has no resume) or disable it and enable it again (safe while the write mode is unset). |
| The assistant can't enable Tableflow, or tries to create its own bucket | `make ai-status` — the context must be *current* and mention Tableflow; run `make context` and start a **new** session. If it reports an authorization error, see *Permissions* in §4.6. |
| `terraform destroy` on the Tableflow side fails with *BucketNotEmpty* | Only for a bucket created before `bucket_force_destroy` existed: `terraform -chdir=environment/terraform-tableflow-aws apply` once to set it, then destroy again. |
| `make polaris-up`: *Docker is not running* / *not logged in to the Confluent CLI* | Start Docker; run `confluent login` (the Tableflow API key is created with your user session, not the Cloud API key). |
| `make lightning-up`: *Lightning Tables are not available in AWS …* | Your cluster's region is not supported yet: `confluent rtce region list --cloud aws`. Build with `make up LIGHTNING=0`. |
| `lightning-enable` fails with a permissions error | The identity running the CLI needs `CloudClusterAdmin` or `ResourceOwner` on the topic. |
| The live view says *waiting for the Lightning Table* | Enabling takes about 6 minutes after the build: `make lightning-status` until the twin shows ACTIVE. (If the view is pointed at `c360_snapshot`, that topic must also exist with a schema.) |
| The live feed panel says *still being set up* or stays empty | `c360_live_activity` must be ACTIVE in `make lightning-status` (about 6 minutes after `make prebuilt-up`) and it is empty until the first button press or `make demo-changes`. If the topic is missing: `make prebuilt-up`. |
| After *Make something happen* the Customer 360 panels take up to a minute to change | By design, not a fault: that table is written by a Flink statement, which commits about once a minute, and Lightning reads only committed data (§4.8, *Two speeds*). The live feed above it should update within about a second. |
| `make demo-changes` prints *topic c360_live_activity is not available* | The live feed was not built (or was removed): `make prebuilt-up`. The change itself still ran. |
| `lightning-query` / the live view return *HTTP 401/403* | A new Global API key can take a couple of minutes to become active; if it persists, the service account lacks `DeveloperRead`: re-run `make lightning-up`. |
| `make prebuilt-up` fails creating the table or the INSERT | `make prebuilt-status` shows which; details: `confluent flink statement describe c360-prebuilt-populate --environment <env> --cloud aws --region <region>`. The source topics must exist (`make data`). |
| The twin's Trino table is missing | Tableflow needs a few minutes after the build to commit: `make tableflow-status`, then `make trino-query SQL='SHOW TABLES FROM polaris."<cluster>"'`. |
| The live view / queries show `c360_snapshot`, not the twin | The twin did not exist when they were deployed: `make prebuilt-up`, then `make lightning-up` (the app) — the queries pick it up automatically. Or set `DEMO_TOPIC` yourself. |
| The assistant has no `confluent-rtce` tools | `make ai-status` must show `+ rtce` (if not: `make lightning-up`, then `make ai-<tool>`); open a **new** session; check the server is connected (Claude Code `/mcp`, Copilot *MCP: List Servers*, Bob *Settings → MCP Servers*). It only returns tables once the Lightning Table is enabled (`make lightning-status`). If an organization policy blocks the HTTP server, fall back to `make lightning-query`. |
| The Lightning query is rejected | Only single-table reads are supported: remove joins, `COUNT`/`SUM`/`GROUP BY` and subqueries (use Trino for those). |
| `trino-query` says *not running* | `make polaris-up`. Polaris keeps its state in memory: if its pod restarted, re-run it to rebuild the catalog. |
| Trino shows the schema but no tables | Tableflow must be enabled on the topic and have committed once (about 5 minutes): `make tableflow-status`. |
| Trino query fails with *access denied* / *credentials* | Polaris could not assume the read-only role: check `make polaris-status` shows the role, wait a minute for IAM to propagate, then retry. |
| `make reset` says it can't read the Terraform topic list | Terraform state is missing or unreadable here. It refuses on purpose; fix the state or delete manually (§7). |
| Terraform state lock / drift | `terraform -chdir=environment/terraform-confluent-aws refresh`; as a last resort delete via the console and `make down`. |

Demo-time problems (Flink statements stuck in `PENDING`, an empty `c360_snapshot`, schema errors) are in the README's [Troubleshooting](README.md#-troubleshooting).

---

## 9. Extending

**A new capability** — for example Lightning Tables — add `mk/60-lightning.mk`:

```make
##@ Lightning Tables
.PHONY: lightning-enable

lightning-enable: ## Enable a Lightning Table on TOPIC
	@./scripts/lightning.sh enable $(TOPIC)
```

Files in `mk/` are included automatically, sorted by name. A `##@ Title` line starts a section and a trailing `## text` puts the target in `make help`. Keep targets thin and put the logic in `scripts/`, which can `source scripts/lib.sh` for `info`/`ok`/`warn`/`die`, `tf_out`, and `load_cc_creds`.

**A new AI assistant** — in `scripts/ai-mcp-config.sh` add a `<tool>_file` / `<tool>_key` pair and a `case` branch; add a target in `mk/40-ai.mk`; add it to `ai-all`.

**Shared knobs** sit at the top of the `Makefile` and can be overridden per run: `make up AI=bob`, `make tableflow-enable TOPIC=orders FORMAT=DELTA`.

---

## 10. Reference

### Targets

Run `make` for the live list. Groups: **Demo flow** (`up`, `status`, `reset-plan`, `reset`, `down`) · **Setup** (`check`, `check-creds`) · **Infrastructure** (`infra`, `infra-plan`, `mcp-env`, `info`, `topics`, `verify`, `urls`, `open`) · **Data** (`data`) · **AI assistants** (`ai-claude`, `ai-copilot`, `ai-bob`, `ai-all`, `ai-status`, `ai-kill-mcp`, `context`) · **Tableflow** (`tableflow-up`, `-status`, `-enable`, `-disable`, `-destroy`) · **Open lakehouse** (`polaris-up`, `polaris-status`, `trino-query`, `c360-queries`, `trino-shell`, `polaris-down`) · **Pre-built twin** (`prebuilt-up`, `prebuilt-status`, `prebuilt-down`) · **Lightning** (`lightning-up`, `lightning-enable`, `lightning-status`, `lightning-query`, `c360-live`, `lightning-down`) · **Data** (`data`, `demo-changes`).

### Variables (pass as `make target VAR=value`)

| Variable | Default | Used by |
|---|---|---|
| `AI` | `claude` | `up` — ONE of `claude`, `copilot`, `bob` or `all` (every tool). For two tools: `make up AI=claude && make ai-bob` |
| `TABLEFLOW` | `1` | `up` — `0` skips the Tableflow AWS side (and the AWS login check) |
| `POLARIS` | follows `TABLEFLOW` (`1`) | `up` — `0` skips Polaris + Trino on kind (and the Docker checks) |
| `PREBUILT`, `PREBUILT_TOPIC` | `1` (when Tableflow or Lightning is on), `c360_snapshot_prebuilt` | `up` — `PREBUILT=0` skips the pre-built twin **and the live feed** (`c360_live_activity`) |
| `DEMO_TOPIC` | the twin if it exists, else `c360_snapshot` | which table the queries, the live view and the context use |
| `LIGHTNING` | follows `POLARIS` (`1`) | `up` — `0` skips the Lightning identity and live front end |
| `SQL`, `LSQL` | `SHOW SCHEMAS FROM polaris`, `SHOW TABLES` | `trino-query`, `lightning-query` |
| `TOPIC`, `FORMAT` | `c360_snapshot`, `ICEBERG` | `tableflow-enable` / `-disable` (`FORMAT` may be `DELTA`) |
| `CUSTOMERS`, `TRANSACTIONS`, `INTERACTIONS` | `200`, `1000`, `800` | `data` |
| `CHANGES`, `IDS`, `DRY_RUN` | `3`, unset, unset | `demo-changes` — how many customers, which ones, preview only |
| `WHAT` | `kafka_cluster` | `open` — `environment`, `flink_console`, `topics`… (see `make urls`) |
| `YES`, `DRY_RUN` | unset | `reset` — skip the prompt / print the plan only |
| `MCP_NODE_VERSION` | `22` | MCP wiring |
| `TF_CC`, `TF_TF`, `MCP_ENV` | repo paths | override the Terraform directories / `.env` location |

### Environment hooks in the scripts

`APP_PORT` (`lightning.sh`, default `8088`) is the local port of the live view · `POLARIS_PORT` (`polaris.sh`, default `18181`) is the local port used to configure Polaris · `TRINO_CHART_VERSION` pins the Trino Helm chart · `ASSUME_YES=1` (`generate-data.sh`) skips its confirmation · `CLEANUP_OPTION=1|2` (`cleanup-demo.sh`) skips its menu · `PROJECT_ROOT` and `BOB_MCP_FILE` (`ai-mcp-config.sh`) redirect where the MCP config is written.
