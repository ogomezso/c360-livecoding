# Customer 360 Demo - Environment Setup

This directory contains automated provisioning for the Customer 360 live coding workshop infrastructure.

## 📁 Directory Structure

```
environment/
├── mcp-confluent/              # Confluent MCP Server setup
│   ├── provision-confluent-mcp.sh
│   ├── test-mcp-server.sh
│   ├── README.md
│   └── examples/
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

# Deploy (5-10 minutes)
make init
make apply

# Or use Terraform directly
terraform init
terraform apply
```

**What gets created:**
- ✅ Confluent Cloud Environment
- ✅ Enterprise Kafka Cluster (AWS eu-west-1, Multi-Zone, 2 CKUs)
- ✅ Flink Compute Pool (Serverless, 0-10 CFUs)
- ✅ Service Account with RBAC roles
- ✅ Kafka and Flink API Keys
- ✅ Schema Registry (included)

### 2. Set Up MCP Server

```bash
cd ../mcp-confluent

# Provision MCP server
./provision-confluent-mcp.sh

# Configure with Terraform outputs
cd ../terraform-confluent-aws
terraform output -raw mcp_server_env_config >> ~/.confluent-mcp/.env

# Test setup
cd ../mcp-confluent
./test-mcp-server.sh
```

**What gets configured:**
- ✅ MCP server directory structure
- ✅ Environment configuration with all credentials
- ✅ Startup and validation scripts
- ✅ Claude Code integration examples

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
| Kafka Cluster | 1 | Enterprise, Multi-AZ |
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

## 💰 Cost Estimate

**AWS eu-west-1 (Ireland)**

| Component | Configuration | Monthly Cost |
|-----------|---------------|--------------|
| Enterprise Cluster | 2 CKUs, Multi-Zone | ~$1,000 |
| Flink Pool | 0-10 CFUs (serverless) | ~$0.36/CFU-hour when active |
| Schema Registry | Included with cluster | $0 |

**💡 Cost Optimization Tips:**
- Flink auto-scales to 0 when idle ($0 cost)
- Use SINGLE_ZONE for dev/test (~50% savings)
- Reduce CKUs to 1 for development
- Destroy infrastructure when not in use

## 🎯 Typical Workshop Flow

### Day Before Workshop

```bash
# 1. Provision infrastructure
cd terraform-confluent-aws
make full-deploy  # ~10 minutes

# 2. Set up MCP server
cd ../mcp-confluent
./provision-confluent-mcp.sh
terraform -chdir=../terraform-confluent-aws output -raw mcp_server_env_config >> ~/.confluent-mcp/.env

# 3. Verify everything works
./test-mcp-server.sh
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
# List available tools
npx -y @confluentinc/mcp-confluent \
  -e ~/.confluent-mcp/.env \
  --list-tools

# Start server
~/.confluent-mcp/start-mcp-server.sh

# Validate setup
~/.confluent-mcp/validate-setup.sh
```

## 📚 Documentation

- **Terraform Setup**: [terraform-confluent-aws/README.md](terraform-confluent-aws/README.md)
- **MCP Server Setup**: [mcp-confluent/README.md](mcp-confluent/README.md)
- **MCP Examples**: [mcp-confluent/examples/README.md](mcp-confluent/examples/README.md)
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
# Check credentials in .env
cat ~/.confluent-mcp/.env | grep API_KEY

# Validate setup
cd mcp-confluent
./test-mcp-server.sh
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
- **MCP Issues**: Check [mcp-confluent/README.md](mcp-confluent/README.md)
- **Confluent Support**: https://support.confluent.io/
- **Community**: https://forum.confluent.io/

---

**Workshop**: Customer 360 Live Coding  
**Infrastructure**: Confluent Cloud (AWS eu-west-1)  
**Tooling**: Terraform + MCP + Claude Code
