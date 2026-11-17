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

**AWS, optional** (Terraform, [`environment/terraform-tableflow-aws`](environment/terraform-tableflow-aws/)) — only for Tableflow

- S3 bucket, IAM role, and a Confluent provider integration

`<suffix>` is a random 8-character hex (for example `a1b2c3d4`) generated on the first build and kept until `make down`. It makes the environment and service-account names unique in the organization, and the Tableflow IAM role unique in the AWS account — see [§6.3](#63-running-more-than-one-demo).

**Time:** about 10–15 minutes, almost all of it waiting for Confluent Cloud to provision.

---

## 2. Prerequisites

| Tool | Needed for | Notes |
|---|---|---|
| `terraform` ≥ 1.5 | infrastructure | |
| `jq`, `curl` | every script | |
| `python3` ≥ 3.8 | data generation | the script creates its own venv |
| `mise` + Node 22 | the Confluent MCP server | `mise install node@22`. The server's native addon only ships binaries up to Node 22, so Node is pinned through `env.PATH` in the MCP config (not through a wrapper command, which would break the org MCP allowlist) |
| `confluent` CLI | Tableflow enable/disable | optional |
| `aws` CLI | Tableflow AWS side | optional; you must be authenticated (see §4.6) |
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
make up                              # check → infra → MCP env → data → wire Claude Code
make up AI=copilot                   # …wire GitHub Copilot instead
make up AI=all TABLEFLOW=1           # …wire every assistant and deploy the Tableflow AWS side
make status                          # confirm
```

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

The server runs as the bare `npx -y @confluentinc/mcp-confluent --oauth`, so **every assistant needs a one-time Confluent Cloud login** in the browser (Claude Code: on the first tool call; Copilot: when you start the server; Bob: Settings → MCP Servers → Authenticate). `make` can't do this step for you, and each assistant keeps its own login — so do it once per assistant **before a live session**, not on stage.

Two things follow from OAuth:

- Sign in to the **organization that owns the demo environment** if you belong to several.
- The login is *you*, not the demo's service account, and an OAuth connection has **no default environment or cluster** — the assistant chooses per tool call. Left alone it will happily list topics from another environment you can see (for example your personal one). `make ai-*` therefore also writes a small instruction file per tool, generated from Terraform, that gives the assistant the demo's organization, environment, cluster, Flink pool and catalog/database names and tells it to use only those:

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

### 4.6 Tableflow, optional — `make tableflow-*`

Tableflow materialises a topic as an Iceberg or Delta table in **your** S3 bucket. It needs the AWS side first.

```bash
aws sts get-caller-identity              # you must already be authenticated
make tableflow-up                        # S3 bucket + IAM role + provider integration
make tableflow-enable                    # c360_snapshot → Iceberg (TOPIC=… FORMAT=DELTA to change)
make tableflow-status                    # AWS side, trust policy, enabled topics
make tableflow-disable TOPIC=c360_snapshot
```

`tableflow-up` runs Terraform in two phases because Confluent only reveals its role ARN and external ID *after* the provider integration exists: phase 1 creates the bucket, role and integration; phase 2 writes those values back into the IAM trust policy. It is non-interactive, re-runnable (phase-2 values are preserved), and the same code `scripts/startup-demo.sh` uses. Authentication: a working `aws` session, or `AWS_PROFILE`, or — if neither — the first profile in `~/.aws/credentials`. Confluent employees: run your usual `assume <role>` first.

`tableflow-enable` is also what you would ask the assistant to do ("enable Tableflow on c360_snapshot"), so it works as a fallback during a live session. It uses your `confluent login`, or the Cloud API key Terraform already uses. Tableflow is only possible on topics that exist, so run it after the demo has created `c360_snapshot`.

### 4.7 Verify — `make status`

Shows the environment, whether all four source topics exist, and which assistants are wired. Then ask your assistant: *"Can you list all my Kafka topics?"*

---

## 5. Repository layout

```text
Makefile                 entry point — `make` lists every target
mk/NN-*.mk               one file per area (setup, infra, data, ai, tableflow); auto-included
scripts/                 every executable
  lib.sh                   shared helpers          status.sh        info / topics / verify / urls
  context.sh               pin assistants to the demo environment
  ai-mcp-config.sh         MCP wiring per tool     tableflow.sh     Tableflow up / enable / disable
  reset-demo.sh            `make reset`            startup-demo.sh  interactive status + bootstrap
  bootstrap.sh             guided first-time build cleanup-demo.sh  interactive reset / destroy menu
  generate-data.sh         `make data`             cleanup.sh       destroy Confluent + local files
  configure-claude-mcp.sh  VS Code / Desktop       reconfigure-mcp.sh  regenerate MCP config
environment/
  terraform-confluent-aws/   Confluent Cloud infrastructure
  terraform-tableflow-aws/   optional AWS side for Tableflow
  data-generation/           Python producers and Avro schemas
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
| Tableflow on those topics | disabled first, when the AWS side is deployed |

Kept: the cluster, Flink pool, service account, and every Terraform-managed topic (`corebank.*`, `digital.interactions`, the Datagen topics). If the Terraform-managed topic list can't be read, the script **refuses to run** rather than guess.

**Tags** live in the Schema Registry catalog and are not removed by the script. Ask your assistant: *"Delete the tags c360, source and data_product."*

### 6.2 Cost

The Kafka cluster and Flink pool bill while they exist. A reset keeps them. If the environment will sit idle, tear it down (§7) — rebuilding is ~15 minutes.

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
3. runs `terraform destroy` on the Tableflow AWS side, if it was deployed (and clears its state/vars).

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

Run `make` for the live list. Groups: **Demo flow** (`up`, `status`, `reset-plan`, `reset`, `down`) · **Setup** (`check`, `check-creds`) · **Infrastructure** (`infra`, `infra-plan`, `mcp-env`, `info`, `topics`, `verify`, `urls`, `open`) · **Data** (`data`) · **AI assistants** (`ai-claude`, `ai-copilot`, `ai-bob`, `ai-all`, `ai-status`, `ai-kill-mcp`, `context`) · **Tableflow** (`tableflow-up`, `-status`, `-enable`, `-disable`, `-destroy`).

### Variables (pass as `make target VAR=value`)

| Variable | Default | Used by |
|---|---|---|
| `AI` | `claude` | `up` — `claude`, `copilot`, `bob` or `all` |
| `TABLEFLOW` | `0` | `up` — `1` also deploys the AWS side |
| `TOPIC`, `FORMAT` | `c360_snapshot`, `ICEBERG` | `tableflow-enable` / `-disable` (`FORMAT` may be `DELTA`) |
| `CUSTOMERS`, `TRANSACTIONS`, `INTERACTIONS` | `200`, `1000`, `800` | `data` |
| `WHAT` | `kafka_cluster` | `open` — `environment`, `flink_console`, `topics`… (see `make urls`) |
| `YES`, `DRY_RUN` | unset | `reset` — skip the prompt / print the plan only |
| `MCP_NODE_VERSION` | `22` | MCP wiring |
| `TF_CC`, `TF_TF`, `MCP_ENV` | repo paths | override the Terraform directories / `.env` location |

### Environment hooks in the scripts

`ASSUME_YES=1` (`generate-data.sh`) skips its confirmation · `CLEANUP_OPTION=1|2` (`cleanup-demo.sh`) skips its menu · `PROJECT_ROOT` and `BOB_MCP_FILE` (`ai-mcp-config.sh`) redirect where the MCP config is written.
