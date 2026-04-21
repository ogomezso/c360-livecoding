# Confluent MCP Server - Automated Provisioning

This directory contains a complete automated provisioning solution for the [Confluent MCP Server](https://github.com/confluentinc/mcp-confluent), which enables AI assistants to interact with Confluent Cloud and Confluent Platform through natural language.

## 📦 What's Included

### Main Scripts

| Script | Purpose |
|--------|---------|
| [`provision-confluent-mcp.sh`](./provision-confluent-mcp.sh) | Main provisioning script - sets up everything |
| [`test-mcp-server.sh`](./test-mcp-server.sh) | Comprehensive test suite to validate your setup |

### Documentation

| Document | Description |
|----------|-------------|
| [`CONFLUENT_MCP_SETUP.md`](./CONFLUENT_MCP_SETUP.md) | Complete setup guide with troubleshooting |
| [`examples/README.md`](./examples/README.md) | Configuration examples and common scenarios |

### Example Configurations

| File | Use Case |
|------|----------|
| [`examples/minimal-cloud-setup.env`](./examples/minimal-cloud-setup.env) | Confluent Cloud configuration |
| [`examples/local-kafka-setup.env`](./examples/local-kafka-setup.env) | Local Kafka development |
| [`examples/docker-compose.yml`](./examples/docker-compose.yml) | Docker deployment |

## 🚀 Quick Start

### 1. Run the Provisioning Script

```bash
./provision-confluent-mcp.sh
```

This will:
- ✅ Verify Node.js 18+ is installed
- ✅ Create `~/.confluent-mcp/` directory
- ✅ Generate `.env` configuration file
- ✅ Create startup and validation scripts
- ✅ Generate Claude Code integration example

### 2. Configure Credentials

```bash
# Edit the generated .env file
vim ~/.confluent-mcp/.env
```

**Minimum required (Confluent Cloud):**
```bash
CONFLUENT_CLOUD_API_KEY=your-key
CONFLUENT_CLOUD_API_SECRET=your-secret
KAFKA_API_KEY=your-kafka-key
KAFKA_API_SECRET=your-kafka-secret
KAFKA_CLUSTER_ID=lkc-xxxxx
KAFKA_REST_ENDPOINT=https://pkc-xxxxx.region.aws.confluent.cloud:443
```

Get your API keys at: https://confluent.cloud/settings/api-keys

### 3. Test Your Setup

```bash
./test-mcp-server.sh
```

This runs 10 automated tests including:
- Prerequisites check (Node.js, npm)
- Environment file validation
- Credential format verification
- Cloud connectivity test
- Available tools listing

### 4. Start the Server

```bash
~/.confluent-mcp/start-mcp-server.sh
```

Or integrate with Claude Code by adding to your MCP settings:

```json
{
  "mcpServers": {
    "confluent": {
      "command": "/Users/yourusername/.confluent-mcp/start-mcp-server.sh",
      "args": []
    }
  }
}
```

## 📚 What is MCP?

**Model Context Protocol (MCP)** is an open protocol that standardizes how AI assistants connect to external data sources and tools. The Confluent MCP Server implements this protocol to provide:

- 🔧 **50+ Tools** for Kafka, Flink SQL, Schema Registry, Connectors, and more
- 🌐 **Multiple Transports**: STDIO (for desktop apps), HTTP/SSE (for remote access)
- 🔐 **Secure Authentication**: API key-based auth for HTTP/SSE
- 📊 **Comprehensive Coverage**: Manage everything from environments to topics to Flink statements

## 🎯 Common Use Cases

### Use Case 1: Topic Management with Claude Code

```bash
# Provision and configure
./provision-confluent-mcp.sh

# Add credentials for Kafka cluster
vim ~/.confluent-mcp/.env

# Integrate with Claude Code
# Now you can ask Claude: "Create a topic called 'user-events' with 6 partitions"
```

### Use Case 2: Confluent Cloud Infrastructure

```bash
# Configure Cloud API credentials
# Now you can ask Claude:
# - "List all my Confluent Cloud environments"
# - "Create a new Basic cluster in AWS us-west-2"
# - "Generate an API key for my cluster"
```

### Use Case 3: Local Kafka Development

```bash
# Use local setup example
cp examples/local-kafka-setup.env ~/.confluent-mcp/.env

# Start local Kafka
cd examples
docker-compose up -d kafka schema-registry

# Test with MCP server
./test-mcp-server.sh
```

### Use Case 4: Flink SQL Operations

```bash
# Add Flink credentials to .env
FLINK_API_KEY=your-flink-key
FLINK_API_SECRET=your-flink-secret
FLINK_COMPUTE_POOL_ID=lfcp-xxxxx

# Now you can ask Claude:
# - "Execute a Flink SQL statement to join these two topics"
# - "List all my Flink compute pools"
```

## 🛠️ Advanced Options

### Custom Installation Directory

```bash
./provision-confluent-mcp.sh --dir /custom/path
```

### Different Transport Modes

```bash
# HTTP transport (for remote access)
./provision-confluent-mcp.sh --transport http

# Generate API key for HTTP
./provision-confluent-mcp.sh --generate-key
```

### Global npm Installation

```bash
./provision-confluent-mcp.sh --global
```

### Docker Deployment

```bash
cd examples
# Edit .env with your credentials
cp minimal-cloud-setup.env .env
vim .env

# Start in Docker
docker-compose up confluent-mcp-server
```

## 📖 Tool Categories

The MCP server provides tools across these categories:

| Category | Example Tools | Required Credentials |
|----------|---------------|---------------------|
| **Environments** | create-environment, list-environments | Cloud API Key |
| **Clusters** | create-cluster, list-clusters | Cloud API Key |
| **API Keys** | create-api-key, delete-api-key | Cloud API Key |
| **Topics** | create-topic, list-topics | Kafka API Key |
| **Messages** | produce-message, consume-messages | Kafka API Key |
| **Schemas** | register-schema, list-schemas | Schema Registry Key |
| **Flink SQL** | execute-flink-sql, list-statements | Flink API Key |
| **Connectors** | create-connector, list-connectors | Connector API Key |
| **Metrics** | query-metrics, list-available-metrics | Cloud or Telemetry Key |
| **Billing** | list-billing-costs | Cloud API Key |

Run `~/.confluent-mcp/validate-setup.sh` to see which tools are available based on your configuration.

## 🔍 Validation & Testing

### Quick Health Check

```bash
./test-mcp-server.sh
```

### Manual Validation

```bash
# List available tools
npx -y @confluentinc/mcp-confluent \
  -e ~/.confluent-mcp/.env \
  --list-tools

# Test Cloud API connection
source ~/.confluent-mcp/.env
curl -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  https://api.confluent.cloud/org/v2/environments
```

## 🐛 Troubleshooting

### Issue: No tools showing up

**Solution:**
```bash
# Check what's configured
~/.confluent-mcp/validate-setup.sh

# Verify credentials are set
cat ~/.confluent-mcp/.env | grep -E "API_KEY|API_SECRET"
```

### Issue: Node.js version error

**Solution:**
```bash
# Install Node.js 18+
nvm install 18
nvm use 18

# Or download from https://nodejs.org/
```

### Issue: Authentication failed

**Solution:**
```bash
# Verify credentials format (no quotes)
# WRONG: KAFKA_API_KEY="abc123"
# RIGHT: KAFKA_API_KEY=abc123

# Test credentials
source ~/.confluent-mcp/.env
curl -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  https://api.confluent.cloud/org/v2/environments
```

See [CONFLUENT_MCP_SETUP.md](./CONFLUENT_MCP_SETUP.md) for complete troubleshooting guide.

## 📝 Files Created by Provisioning Script

After running `provision-confluent-mcp.sh`, you'll have:

```
~/.confluent-mcp/
├── .env                        # Your configuration (EDIT THIS)
├── start-mcp-server.sh        # Startup script
├── validate-setup.sh          # Validation script
└── claude-mcp-config.json     # Claude Code integration example
```

## 🔗 Resources

- **GitHub**: https://github.com/confluentinc/mcp-confluent
- **npm Package**: https://www.npmjs.com/package/@confluentinc/mcp-confluent
- **MCP Protocol**: https://modelcontextprotocol.io/
- **Confluent Cloud**: https://confluent.cloud/
- **API Keys**: https://confluent.cloud/settings/api-keys

## 🤝 Integration Examples

### Claude Code (Desktop/CLI)

Add to `~/.claude/mcp.json` or project `.claude/mcp.json`:

```json
{
  "mcpServers": {
    "confluent": {
      "command": "/Users/yourusername/.confluent-mcp/start-mcp-server.sh"
    }
  }
}
```

### Cursor IDE

Add to `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "confluent": {
      "command": "npx",
      "args": ["-y", "@confluentinc/mcp-confluent", "-e", "/path/to/.env"]
    }
  }
}
```

### VS Code (with Copilot Agent Mode)

Add to `.vscode/mcp.json`:

```json
{
  "mcpServers": {
    "confluent": {
      "command": "npx",
      "args": ["-y", "@confluentinc/mcp-confluent", "-e", "${workspaceFolder}/.env"]
    }
  }
}
```

## 📄 License

These provisioning scripts are provided as-is for use with the Confluent MCP server.

The Confluent MCP Server itself is maintained by Confluent Inc.

## 🆘 Support

- **MCP Server Issues**: https://github.com/confluentinc/mcp-confluent/issues
- **Confluent Community**: https://forum.confluent.io/
- **Documentation**: See [CONFLUENT_MCP_SETUP.md](./CONFLUENT_MCP_SETUP.md)

---

**Ready to get started?** Run `./provision-confluent-mcp.sh` now! 🚀
