# Customer 360 Demo - Environment Setup

This directory holds the infrastructure-as-code and data generators for the Customer 360 live coding workshop. Executables live in [`../scripts/`](../scripts/) and the end-to-end build and teardown procedure is in [`../BUILD_GUIDE.md`](../BUILD_GUIDE.md) — start there.

## 📁 Directory Structure

```
environment/
├── data-generation/            # Synthetic Spanish banking data producers
├── mcp-confluent/               # Credentials consumed by demo/producer scripts
│   └── .env                     # Terraform-exported Kafka/Flink creds (gitignored, NOT used by Claude's MCP connection)
├── terraform-tableflow-aws/    # Optional: S3 + IAM + provider integration for Tableflow
└── terraform-confluent-aws/    # Confluent Cloud infrastructure (Terraform)
    ├── main.tf
    ├── confluent.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    ├── Makefile
    └── README.md
```

## 🚀 Quick Start

### 1. Provision Confluent Cloud Infrastructure

```bash
cd terraform-confluent-aws

# Configure credentials
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Add your Confluent Cloud API keys

# Deploy
make init
make apply

# Or use Terraform directly
terraform init
terraform apply
```

**What gets created:**
- ✅ Confluent Cloud Environment
- ✅ Standard Kafka Cluster (AWS eu-west-1, Multi-Zone, auto-scaling 0-10 eCKUs)
- ✅ Flink Compute Pool (Serverless, 0-10 CFUs)
- ✅ Service Account with RBAC roles
- ✅ Kafka and Flink API Keys
- ✅ Schema Registry (included)

### 2. Set Up MCP Server

MCP setup is part of `scripts/bootstrap.sh` / `make up` (see [BUILD_GUIDE.md](../BUILD_GUIDE.md)) — it exports Terraform credentials to `mcp-confluent/.env` (for demo/producer scripts) and generates a project-level `.mcp.json` at the repo root using Confluent's OAuth login flow, which is what Claude Code actually connects through.

To regenerate `.mcp.json` after infrastructure changes without re-running the full bootstrap:

```bash
make ai-claude          # from the repo root; or scripts/reconfigure-mcp.sh
```

**What gets configured:**
- ✅ `mcp-confluent/.env` with Terraform-exported credentials (for demo scripts)
- ✅ Project `.mcp.json` (OAuth-based `@confluentinc/mcp-confluent`, pinned to a compatible Node version)
- ✅ Claude Code's stale per-project MCP approval state reset

## 📋 Prerequisites

### For Confluent Cloud Infrastructure

1. **Confluent Cloud Account**
   - Sign up: https://confluent.cloud/
   - Free trial available

2. **Confluent Cloud API Keys**
   - Create at: https://confluent.cloud/settings/api-keys
   - Scope: Organization/Cloud resource management

3. **Terraform** (>= 1.5.0)
   ```bash
   brew install terraform
   ```

### For MCP Server

1. **Node.js** (>= 18)
   ```bash
   brew install node
   ```

2. **Claude Code**
   - Desktop app or CLI
   - Download: https://claude.ai/code

## 🔗 Integration Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Terraform provisions Confluent Cloud infrastructure      │
│    ├── Environment, Kafka cluster, Flink pool               │
│    ├── Service account, API keys, RBAC roles                │
│    └── Outputs connection details                           │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ Export credentials
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. MCP server uses credentials to connect                   │
│    ├── Cloud API for management operations                  │
│    ├── Kafka API for topic operations                       │
│    └── Flink API for SQL statements                         │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ Exposes MCP tools
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Claude Code uses MCP tools for workshop                  │
│    ├── List topics and schemas                              │
│    ├── Sample data from topics                              │
│    ├── Generate and execute Flink SQL                       │
│    └── Debug and iterate on Customer 360 data product       │
└─────────────────────────────────────────────────────────────┘
```

## 📊 Resources Overview

### Terraform-Managed Resources

| Resource Type | Count | Purpose |
|--------------|-------|---------|
| Environment | 1 | Isolated workspace |
| Kafka Cluster | 1 | Standard, Multi-AZ |
| Flink Compute Pool | 1 | Serverless processing |
| Service Account | 1 | Application identity |
| API Keys | 2 | Kafka + Flink access |
| Role Bindings | 3 | RBAC permissions |

### MCP Server Tools (50+)

| Category | Example Tools |
|----------|---------------|
| Kafka | `list_topics`, `create_topic`, `produce_message` |
| Schemas | `register_schema`, `get_schema` |
| Flink | `execute_flink_sql`, `list_statements` |
| Management | `create_environment`, `create_cluster` |

## 🎯 Typical Workshop Flow

### Day Before Workshop

```bash
# 1. Provision infrastructure + MCP server in one shot (from the repo root)
make up                 # or: scripts/bootstrap.sh

# 2. Verify Claude Code sees the MCP tools
# (open a new Claude Code session in the repo, ask it to list Kafka topics —
#  first tool call triggers the Confluent Cloud OAuth login)
```

### During Workshop

```bash
# 4. Create demo topics and schemas (via Claude Code + MCP)
# 5. Generate synthetic data
# 6. Build Customer 360 with Flink SQL
# 7. Iterate and debug with Claude
```

### After Workshop

```bash
# 8. Clean up
cd terraform-confluent-aws
make destroy  # Removes all resources
```

## 🔧 Useful Commands

### Terraform

```bash
# View outputs
make output

# Get specific value
terraform output -raw kafka_cluster_id

# Open console
make console

# Export MCP config
make export-mcp

# Check costs (approximate)
terraform plan
```

### MCP Server

```bash
# Regenerate .mcp.json (OAuth-based) after cluster changes (from the repo root)
make ai-claude          # or: scripts/reconfigure-mcp.sh

# Reset Claude Code's stale per-project MCP approval state manually
claude mcp reset-project-choices
```

## 📚 Documentation

- **Terraform Setup**: [terraform-confluent-aws/README.md](terraform-confluent-aws/README.md)
- **MCP Tools Reference**: [MCP_TOOLS_REFERENCE.md](MCP_TOOLS_REFERENCE.md)
- **Main Workshop**: [../README.md](../README.md)

## 🐛 Troubleshooting

### Terraform Issues

**Problem**: "Error creating cluster"
```bash
# Check Confluent Cloud status
curl https://status.confluent.cloud/

# Verify API key permissions
confluent kafka cluster list
```

**Problem**: "Insufficient permissions"
- Ensure API key has **Organization** scope
- Recreate at: https://confluent.cloud/settings/api-keys

### MCP Server Issues

**Problem**: "No tools available"
```bash
# Confirm .mcp.json exists at the repo root and check its contents
cat ../.mcp.json

# Regenerate it and reset stale approval state
../scripts/reconfigure-mcp.sh

# Claude Code only reads .mcp.json on session start — open a fresh
# terminal/window, don't just reload an existing one
```

**Problem**: "Connection timeout"
```bash
# Test Confluent Cloud connectivity
curl https://api.confluent.cloud/health

# Check if cluster is provisioned
terraform output kafka_cluster_bootstrap_endpoint
```

## 🔐 Security Notes

1. **Never commit credentials**
   - `.gitignore` blocks `*.tfvars` and `*.env`
   - Use environment variables in CI/CD

2. **Rotate API keys regularly**
   - Generate new keys monthly
   - Delete old keys after rotation

3. **Use separate environments**
   - Different API keys per environment (dev/staging/prod)

4. **Store state securely**
   - Consider remote state (S3, Terraform Cloud)
   - Enable state encryption

## 📞 Support

- **Terraform Issues**: Check [terraform-confluent-aws/README.md](terraform-confluent-aws/README.md)
- **MCP Issues**: Check [MCP_TOOLS_REFERENCE.md](MCP_TOOLS_REFERENCE.md)
- **Confluent Support**: https://support.confluent.io/
- **Community**: https://forum.confluent.io/

---

**Workshop**: Customer 360 Live Coding  
**Infrastructure**: Confluent Cloud (AWS eu-west-1)  
**Tooling**: Terraform + MCP + Claude Code
