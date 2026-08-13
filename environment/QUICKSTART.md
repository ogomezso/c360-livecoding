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
- ✅ Credentials exported to `mcp-confluent/.env` (used by demo/producer scripts)
- ✅ Project `.mcp.json` generated at the repo root (OAuth-based, for Claude Code CLI)
- ✅ Ready for Claude Code integration

## 🔗 Claude Code Integration

`bootstrap.sh` already generates `.mcp.json` for the Claude Code CLI — no extra step needed there. Open a **new** terminal/session in the repo (Claude Code only reads `.mcp.json` on session start) and test: "List my Kafka topics". The first tool call triggers an interactive Confluent Cloud OAuth login.

If you also use the VS Code extension or the Claude Desktop app, those read from global settings instead of the project `.mcp.json`, so configure them separately:

```bash
./configure-claude-mcp.sh --vscode    # VS Code global settings
./configure-claude-mcp.sh --desktop   # Claude Desktop app
```

Changed clusters since the last bootstrap? Regenerate `.mcp.json` without re-provisioning infra:

```bash
./reconfigure-mcp.sh
```

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
- [MCP Tools Reference](MCP_TOOLS_REFERENCE.md)
- [Bootstrap Script Details](bootstrap.sh)

---

**Questions?** See individual README files in subdirectories for detailed documentation.
