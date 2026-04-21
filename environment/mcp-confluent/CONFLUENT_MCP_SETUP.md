# Confluent MCP Server - Automated Setup Guide

This guide explains how to use the automated provisioning script to set up the Confluent MCP server.

## Quick Start

### 1. Run the Provisioning Script

```bash
./provision-confluent-mcp.sh
```

This will:
- ✅ Check Node.js and npm prerequisites (requires Node.js 18+)
- ✅ Create MCP directory at `~/.confluent-mcp`
- ✅ Generate `.env` configuration file with all available options
- ✅ Create helper scripts for starting and validating the server
- ✅ Create Claude Code integration example

### 2. Configure Your Credentials

Edit the generated `.env` file:

```bash
vim ~/.confluent-mcp/.env
# or
code ~/.confluent-mcp/.env
```

**Required credentials** (minimum):
```bash
# For Confluent Cloud management
CONFLUENT_CLOUD_API_KEY=your-api-key
CONFLUENT_CLOUD_API_SECRET=your-api-secret

# For Kafka cluster operations
KAFKA_API_KEY=your-kafka-key
KAFKA_API_SECRET=your-kafka-secret
KAFKA_CLUSTER_ID=lkc-xxxxx
KAFKA_REST_ENDPOINT=https://pkc-xxxxx.region.provider.confluent.cloud:443
```

**How to get your credentials:**

1. **Confluent Cloud API Keys** (Management Plane)
   - Visit: https://confluent.cloud/settings/api-keys
   - Create a Cloud API Key with appropriate permissions
   - These are used for managing environments, clusters, and API keys

2. **Kafka Cluster API Keys** (Data Plane)
   - In Confluent Cloud, navigate to your cluster
   - Go to "API Keys" section
   - Create a cluster-scoped API key
   - These are used for topic operations

### 3. Validate Your Setup

```bash
~/.confluent-mcp/validate-setup.sh
```

This will list all enabled MCP tools based on your configuration.

### 4. Start the MCP Server

```bash
~/.confluent-mcp/start-mcp-server.sh
```

## Advanced Usage

### Custom Installation Directory

```bash
./provision-confluent-mcp.sh --dir /path/to/custom/directory
```

### Different Transport Modes

The MCP server supports three transport modes:

#### STDIO (Default - for Claude Code)
```bash
./provision-confluent-mcp.sh --transport stdio
```

#### HTTP (for remote access)
```bash
./provision-confluent-mcp.sh --transport http
```

Then start with:
```bash
npx -y @confluentinc/mcp-confluent -e ~/.confluent-mcp/.env --transport http
```

Access at: `http://localhost:3000`

#### SSE (Server-Sent Events)
```bash
./provision-confluent-mcp.sh --transport sse
```

### Global npm Installation

```bash
./provision-confluent-mcp.sh --global
```

### Generate MCP API Key (for HTTP/SSE)

```bash
./provision-confluent-mcp.sh --generate-key
```

## Claude Code Integration

### Method 1: Using the Startup Script (Recommended)

1. Add to your Claude Code MCP settings:

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

2. Restart Claude Code

### Method 2: Direct npx Invocation

```json
{
  "mcpServers": {
    "confluent": {
      "command": "npx",
      "args": [
        "-y",
        "@confluentinc/mcp-confluent",
        "-e",
        "/Users/yourusername/.confluent-mcp/.env"
      ]
    }
  }
}
```

## Available Tools

The MCP server provides 50+ tools organized by category:

### Confluent Cloud Tools (require Cloud API credentials)
- **Environments**: Create, list, update, delete environments
- **Clusters**: Create, list, get status, delete clusters
- **API Keys**: Create, list, delete API keys
- **Billing**: List billing costs
- **Metrics/Telemetry**: Query operational metrics

### Kafka Tools (require Kafka API credentials)
- **Topics**: Create, list, delete, describe topics
- **Producers**: Produce messages to topics
- **Consumers**: Consume messages from topics
- **Consumer Groups**: List and describe consumer groups

### Schema Registry Tools (require Schema Registry credentials)
- **Schemas**: Register, list, get, delete schemas
- **Subjects**: Manage schema subjects
- **Compatibility**: Check schema compatibility

### Flink SQL Tools (require Flink credentials)
- **Compute Pools**: List, create, delete pools
- **Statements**: Execute, list, get Flink SQL statements
- **Databases/Catalogs**: Manage Flink databases and catalogs

### Tableflow Tools (require Tableflow credentials)
- **Topics**: Create, list Tableflow topics
- **Catalogs**: Manage Tableflow catalogs

### Connectors Tools (require Connector credentials)
- **Connectors**: Create, list, update, delete connectors
- **Connector Plugins**: List available connector plugins

## Environment Variables Reference

### Required Variables by Tool Category

| Tool Category | Required Variables |
|--------------|-------------------|
| Cloud Management | `CONFLUENT_CLOUD_API_KEY`, `CONFLUENT_CLOUD_API_SECRET` |
| Kafka | `KAFKA_API_KEY`, `KAFKA_API_SECRET`, `KAFKA_CLUSTER_ID`, `KAFKA_REST_ENDPOINT` |
| Schema Registry | `SCHEMA_REGISTRY_ENDPOINT`, `SCHEMA_REGISTRY_API_KEY`, `SCHEMA_REGISTRY_API_SECRET` |
| Flink | `FLINK_API_KEY`, `FLINK_API_SECRET`, `FLINK_COMPUTE_POOL_ID` |
| Tableflow | `TABLEFLOW_API_KEY`, `TABLEFLOW_API_SECRET` |
| Metrics | `TELEMETRY_API_KEY`, `TELEMETRY_API_SECRET` (or Cloud API credentials) |

**Note**: Only tools with configured credentials will be enabled.

## Troubleshooting

### "Missing required environment variables"

**Problem**: Tools are not showing up or getting authentication errors.

**Solution**: 
1. Check your `.env` file has the required credentials
2. Run the validation script: `~/.confluent-mcp/validate-setup.sh`
3. Ensure the environment variables are correctly formatted (no extra spaces)

### "Node.js version must be 18 or higher"

**Problem**: Your Node.js version is too old.

**Solution**:
```bash
# Using nvm (recommended)
nvm install 18
nvm use 18

# Or download from nodejs.org
```

### Authentication errors on HTTP/SSE transports

**Problem**: Getting 401 errors when using HTTP or SSE transport.

**Solution**: Generate and configure an MCP API key:
```bash
./provision-confluent-mcp.sh --generate-key
```

### Tools not appearing

**Problem**: Expected tools are not listed.

**Solution**:
1. Verify the required environment variables are set for those tools
2. Run: `npx -y @confluentinc/mcp-confluent -e ~/.confluent-mcp/.env --list-tools`
3. Check the environment variable reference above

### Claude Code not connecting

**Problem**: Claude Code can't connect to the MCP server.

**Solution**:
1. Ensure you're using `stdio` transport (default)
2. Check the MCP server path in Claude Code settings
3. Restart Claude Code after configuration changes
4. Check Claude Code logs for error messages

## Useful Commands

### List all available tools
```bash
npx -y @confluentinc/mcp-confluent -e ~/.confluent-mcp/.env --list-tools
```

### Start with specific transport
```bash
# STDIO (default)
npx -y @confluentinc/mcp-confluent -e ~/.confluent-mcp/.env --transport stdio

# HTTP
npx -y @confluentinc/mcp-confluent -e ~/.confluent-mcp/.env --transport http

# Multiple transports
npx -y @confluentinc/mcp-confluent -e ~/.confluent-mcp/.env --transport http,sse,stdio
```

### View help
```bash
npx -y @confluentinc/mcp-confluent --help
```

### Check version
```bash
npx -y @confluentinc/mcp-confluent --version
```

## Docker Deployment (Optional)

If you prefer to run the MCP server in Docker:

```bash
# Build custom image with your .env
cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
RUN npm install -g @confluentinc/mcp-confluent
COPY .env /app/.env
EXPOSE 3000
CMD ["npx", "@confluentinc/mcp-confluent", "-e", "/app/.env", "--transport", "http"]
EOF

# Build and run
docker build -t confluent-mcp .
docker run -p 3000:3000 --env-file ~/.confluent-mcp/.env confluent-mcp
```

## Security Best Practices

1. **Never commit `.env` files** to version control
   - Add `.env` to `.gitignore`
   
2. **Use least-privilege API keys**
   - Create separate API keys for different purposes
   - Use cluster-scoped keys when possible
   
3. **Rotate credentials regularly**
   - Periodically regenerate API keys
   - Update `.env` file accordingly

4. **Enable authentication for HTTP/SSE**
   - Always use `MCP_API_KEY` for non-stdio transports
   - Never disable authentication in production
   - Use `MCP_AUTH_DISABLED=true` only for local development

5. **Bind to localhost only**
   - Keep `MCP_HOST=127.0.0.1` (default)
   - Don't expose to `0.0.0.0` unless absolutely necessary

## Resources

- **GitHub Repository**: https://github.com/confluentinc/mcp-confluent
- **npm Package**: https://www.npmjs.com/package/@confluentinc/mcp-confluent
- **MCP Protocol**: https://modelcontextprotocol.io/
- **Confluent Cloud**: https://confluent.cloud/
- **Confluent Documentation**: https://docs.confluent.io/

## Support

For issues or questions:
- GitHub Issues: https://github.com/confluentinc/mcp-confluent/issues
- Confluent Community: https://forum.confluent.io/

## License

This provisioning script is provided as-is for use with the Confluent MCP server.
