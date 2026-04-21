# Confluent MCP Server - Configuration Examples

This directory contains example configurations for different deployment scenarios.

## Quick Start Examples

### Example 1: Confluent Cloud (Most Common)

Use this if you're connecting to Confluent Cloud:

```bash
# Copy the minimal cloud setup example
cp examples/minimal-cloud-setup.env ~/.confluent-mcp/.env

# Edit and add your credentials
vim ~/.confluent-mcp/.env

# Validate
~/.confluent-mcp/validate-setup.sh

# Start
~/.confluent-mcp/start-mcp-server.sh
```

**What you need:**
- Confluent Cloud account
- Cloud API Key (from https://confluent.cloud/settings/api-keys)
- Kafka Cluster with API Key

### Example 2: Local Kafka (Development)

Use this for local development with Docker Compose:

```bash
# Start local Kafka
cd examples
docker-compose up -d kafka schema-registry

# Wait for services to be ready
sleep 10

# Copy the local setup example
cp local-kafka-setup.env ~/.confluent-mcp/.env

# Start MCP server
~/.confluent-mcp/start-mcp-server.sh
```

**What you need:**
- Docker and Docker Compose
- No Confluent Cloud account required

### Example 3: MCP Server in Docker

Run the MCP server itself in Docker with HTTP transport:

```bash
# Edit the .env file with your credentials
cp minimal-cloud-setup.env .env
vim .env

# Start the MCP server in Docker
docker-compose up confluent-mcp-server

# Access at http://localhost:3000
curl http://localhost:3000/health
```

## Configuration Files

### `minimal-cloud-setup.env`
Minimal configuration for Confluent Cloud with:
- Cloud API credentials (management plane)
- Kafka cluster credentials (data plane)
- Basic MCP server settings

**Use case**: Production-ready Confluent Cloud setup

### `local-kafka-setup.env`
Configuration for local/self-managed Kafka with:
- Local bootstrap servers
- Local Schema Registry endpoint
- No cloud credentials required

**Use case**: Local development and testing

### `docker-compose.yml`
Complete Docker Compose setup including:
- Confluent MCP Server with HTTP/SSE transport
- Local Kafka broker (Confluent Local)
- Schema Registry
- Health checks and networking

**Use case**: Fully containerized development environment

## Testing Your Setup

### Test Cloud Connection

```bash
# Set your credentials
export CONFLUENT_CLOUD_API_KEY=your-key
export CONFLUENT_CLOUD_API_SECRET=your-secret

# Test connection
curl -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  https://api.confluent.cloud/org/v2/environments | jq
```

### Test Local Kafka

```bash
# Start local Kafka
docker-compose up -d kafka

# Wait for startup
sleep 10

# Create a test topic
docker exec kafka-local kafka-topics \
  --bootstrap-server localhost:9092 \
  --create --topic test-topic --partitions 1 --replication-factor 1

# List topics
docker exec kafka-local kafka-topics \
  --bootstrap-server localhost:9092 \
  --list
```

### Test MCP Server

```bash
# List enabled tools
npx -y @confluentinc/mcp-confluent -e ~/.confluent-mcp/.env --list-tools

# Expected output shows available tools based on your configuration
```

## Common Scenarios

### Scenario 1: I only want to manage topics

**Minimum config needed:**
```bash
KAFKA_API_KEY=your-kafka-key
KAFKA_API_SECRET=your-kafka-secret
KAFKA_CLUSTER_ID=lkc-xxxxx
KAFKA_REST_ENDPOINT=https://pkc-xxxxx.region.aws.confluent.cloud:443
```

**Available tools**: create-topic, list-topics, delete-topic, produce-message, consume-messages

### Scenario 2: I want to manage Confluent Cloud infrastructure

**Minimum config needed:**
```bash
CONFLUENT_CLOUD_API_KEY=your-cloud-key
CONFLUENT_CLOUD_API_SECRET=your-cloud-secret
```

**Available tools**: create-environment, list-environments, create-cluster, list-clusters, create-api-key, delete-api-key

### Scenario 3: I need Schema Registry

**Additional config needed:**
```bash
SCHEMA_REGISTRY_ENDPOINT=https://psrc-xxxxx.region.aws.confluent.cloud
SCHEMA_REGISTRY_API_KEY=your-sr-key
SCHEMA_REGISTRY_API_SECRET=your-sr-secret
```

**Additional tools**: register-schema, list-schemas, get-schema, delete-schema

### Scenario 4: I want to use Flink SQL

**Additional config needed:**
```bash
FLINK_API_KEY=your-flink-key
FLINK_API_SECRET=your-flink-secret
FLINK_COMPUTE_POOL_ID=lfcp-xxxxx
FLINK_DATABASE_NAME=default
FLINK_CATALOG_NAME=default
```

**Additional tools**: execute-flink-sql, list-flink-statements, create-flink-compute-pool

## Deployment Patterns

### Pattern 1: Claude Code Desktop (STDIO)

**Configuration:**
```json
{
  "mcpServers": {
    "confluent": {
      "command": "npx",
      "args": ["-y", "@confluentinc/mcp-confluent", "-e", "/path/to/.env"],
      "env": {}
    }
  }
}
```

**Transport**: stdio (default)
**Best for**: Local development with Claude Code

### Pattern 2: Remote HTTP Server

**Start server:**
```bash
# Generate API key
npx @confluentinc/mcp-confluent --generate-key

# Add to .env
echo "MCP_API_KEY=mcp_xxxxx" >> ~/.confluent-mcp/.env

# Start with HTTP
npx -y @confluentinc/mcp-confluent \
  -e ~/.confluent-mcp/.env \
  --transport http
```

**Client connection:**
```bash
# Include API key in header
curl -H "cflt-mcp-api-Key: mcp_xxxxx" \
  http://localhost:3000/mcp
```

**Best for**: Remote access, multiple clients, service deployment

### Pattern 3: Docker Production Deployment

**docker-compose.yml:**
```yaml
services:
  mcp-server:
    image: node:18-alpine
    command: >
      sh -c "npm install -g @confluentinc/mcp-confluent &&
             npx @confluentinc/mcp-confluent -e /app/.env --transport http"
    volumes:
      - ./production.env:/app/.env:ro
    ports:
      - "3000:3000"
    restart: always
```

**Best for**: Production deployments, containerized environments

## Troubleshooting Examples

### Problem: No tools showing up

```bash
# Check what's configured
npx -y @confluentinc/mcp-confluent -e ~/.confluent-mcp/.env --list-tools

# If empty, verify credentials
cat ~/.confluent-mcp/.env | grep -E "API_KEY|API_SECRET"

# Test connection
curl -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
  https://api.confluent.cloud/org/v2/environments
```

### Problem: Connection timeout

```bash
# Check endpoint URLs
cat ~/.confluent-mcp/.env | grep ENDPOINT

# Verify connectivity
curl -v https://api.confluent.cloud/health

# Test Kafka REST endpoint
curl -v https://pkc-xxxxx.region.aws.confluent.cloud:443
```

### Problem: Authentication failed

```bash
# Verify API key format (should not have quotes or extra spaces)
cat ~/.confluent-mcp/.env | grep CONFLUENT_CLOUD_API_KEY

# Test credentials directly
curl -u "key:secret" https://api.confluent.cloud/org/v2/environments

# Regenerate if needed at https://confluent.cloud/settings/api-keys
```

## Next Steps

1. Choose the example that matches your use case
2. Copy and customize the configuration
3. Run the validation script
4. Integrate with Claude Code or your MCP client
5. Explore the available tools

For more details, see the main [CONFLUENT_MCP_SETUP.md](../CONFLUENT_MCP_SETUP.md) guide.
