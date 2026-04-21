# Customer 360 Demo - Quick Start Guide

## 🚀 One-Command Setup

```bash
./bootstrap.sh
```

That's it! This single command will:
1. ✅ Check prerequisites (Terraform, Node.js)
2. ✅ Prompt for Confluent Cloud credentials (if not set)
3. ✅ Deploy Kafka cluster + Flink compute pool to AWS
4. ✅ Provision Confluent MCP server locally
5. ✅ Configure MCP with cluster credentials
6. ✅ Validate the complete setup

**Time**: ~5-10 minutes total

## 📋 Prerequisites

- **Terraform** >= 1.5.0: `brew install terraform`
- **Node.js** >= 18: `brew install node`
- **Confluent Cloud Account**: https://confluent.cloud/
- **Cloud API Key**: https://confluent.cloud/settings/api-keys (with "Cloud resource management" scope)

## 🎯 What Gets Deployed

### Confluent Cloud (AWS eu-west-1)
- ✅ Standard Kafka cluster (auto-scaling 0-10 eCKU)
- ✅ Flink compute pool (auto-scaling 0-10 CFU)
- ✅ Service account with RBAC roles
- ✅ API keys for Kafka + Flink

### Local Machine
- ✅ Confluent MCP server (`~/.confluent-mcp/`)
- ✅ Credentials configured
- ✅ Ready for Claude Code integration

## 💰 Cost Estimate

- **Kafka**: ~$0.16/eCKU-hour (only when in use)
- **Flink**: ~$0.36/CFU-hour (only when active)
- **Idle**: $0 (both auto-scale to zero)

**Example**: 2 eCKU for 8 hours = **$2.56/day**

## 🔗 Claude Code Integration

After bootstrap completes:

```bash
./configure-claude-mcp.sh
```

This automatically:
1. ✅ Detects your Claude Code environment (VS Code/CLI/Desktop)
2. ✅ Adds MCP server configuration
3. ✅ Backs up existing settings

Then restart Claude Code and test: "List my Kafka topics"

## 🧹 Cleanup

**Complete cleanup** (removes everything):
```bash
./cleanup.sh
```

**Terraform only** (keeps MCP server):
```bash
cd terraform-confluent-aws
make destroy
```

## 📚 Detailed Documentation

- [Terraform Setup](terraform-confluent-aws/README.md)
- [MCP Server](mcp-confluent/)
- [Bootstrap Script Details](bootstrap.sh)

---

**Questions?** See individual README files in subdirectories for detailed documentation.
