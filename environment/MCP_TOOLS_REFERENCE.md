# Confluent MCP Tools - Complete Reference

This document maps ALL available Confluent MCP tools to their required environment variables.

## ✅ Configured & Ready (45+ tools)

### 📊 Kafka & Topics (6 tools)

**Tools:**
- `list-topics` - List all Kafka topics
- `create-topics` - Create one or more topics
- `delete-topics` - Delete topics
- `produce-message` - Produce messages with Schema Registry support
- `consume-messages` - Consume messages from topics
- `alter-topic-config` - Modify topic configuration
- `get-topic-config` - Retrieve topic configuration

**Required Environment Variables:**
```bash
BOOTSTRAP_SERVERS=<broker-list>
KAFKA_API_KEY=<cluster-api-key>
KAFKA_API_SECRET=<cluster-api-secret>
KAFKA_CLUSTER_ID=<lkc-xxxxx>
KAFKA_ENV_ID=<env-xxxxx>
KAFKA_REST_ENDPOINT=<https://...>
```

---

### 🏷️ Tags & Catalog (7 tools)

**Tools:**
- `add-tags-to-topic` - Assign tags to Kafka topics
- `create-topic-tags` - Create new tag definitions
- `delete-tag` - Remove tag definitions
- `list-tags` - List all available tags
- `remove-tag-from-entity` - Remove tag from resource
- `search-topics-by-tag` - Find topics by tag
- `search-topics-by-name` - Find topics by name pattern

**Required Environment Variables:**
```bash
CONFLUENT_CLOUD_API_KEY=<cloud-api-key>
CONFLUENT_CLOUD_API_SECRET=<cloud-api-secret>
CONFLUENT_CLOUD_REST_ENDPOINT=https://api.confluent.cloud
```

---

### 🔧 Flink SQL & Catalog (10+ tools)

**Tools - SQL Operations:**
- `create-flink-statement` - Execute Flink SQL statements
- `list-flink-statements` - List all statements
- `read-flink-statement` - Get statement details
- `delete-flink-statements` - Remove statements
- `get-flink-statement-exceptions` - Debug failures

**Tools - Catalog:**
- `list-flink-catalogs` - List available catalogs
- `list-flink-databases` - List databases in catalog
- `list-flink-tables` - List tables in database
- `describe-flink-table` - Get table schema
- `get-flink-table-info` - Detailed table information

**Tools - Diagnostics:**
- `check-flink-statement-health` - Health check
- `detect-flink-statement-issues` - Issue detection
- `get-flink-statement-profile` - Performance profiling

**Required Environment Variables:**
```bash
FLINK_API_KEY=<flink-api-key>
FLINK_API_SECRET=<flink-api-secret>
FLINK_COMPUTE_POOL_ID=<lfcp-xxxxx>
FLINK_DATABASE_NAME=<database-name>
FLINK_ENV_ID=<env-xxxxx>
FLINK_ORG_ID=<org-uuid>           # ⭐ Required for ALL Flink tools
FLINK_REST_ENDPOINT=<https://...>
FLINK_ENV_NAME=<environment-name>
FLINK_CATALOG_NAME=default_catalog
FLINK_CLOUD=<AWS|GCP|AZURE>
FLINK_REGION=<region>
```

---

### 🔌 Connectors (4 tools)

**Tools:**
- `list-connectors` - List all connectors
- `read-connector` - Get connector details
- `create-connector` - Create new connector
- `delete-connector` - Remove connector

**Required Environment Variables:**
```bash
CONFLUENT_CLOUD_API_KEY=<cloud-api-key>
CONFLUENT_CLOUD_API_SECRET=<cloud-api-secret>
CONFLUENT_CLOUD_REST_ENDPOINT=https://api.confluent.cloud
```

**Note:** Also needs connector-specific config in `CONNECTORS_ENDPOINT`:
```bash
CONNECTORS_ENDPOINT=<kafka-rest-endpoint>
CONNECTORS_API_KEY=<kafka-api-key>
CONNECTORS_API_SECRET=<kafka-api-secret>
```

---

### 📋 Schema Registry (2 tools)

**Tools:**
- `list-schemas` - List all schemas
- `delete-schema` - Remove schema

**Required Environment Variables:**
```bash
SCHEMA_REGISTRY_ENDPOINT=<https://...>
SCHEMA_REGISTRY_API_KEY=<sr-api-key>
SCHEMA_REGISTRY_API_SECRET=<sr-api-secret>
```

---

### 🌍 Environments & Clusters (3 tools)

**Tools:**
- `list-environments` - List all environments
- `read-environment` - Get environment details
- `list-clusters` - List Kafka clusters

**Required Environment Variables:**
```bash
CONFLUENT_CLOUD_API_KEY=<cloud-api-key>
CONFLUENT_CLOUD_API_SECRET=<cloud-api-secret>
CONFLUENT_CLOUD_REST_ENDPOINT=https://api.confluent.cloud
```

---

### 📈 Metrics & Billing (3 tools)

**Tools:**
- `query-metrics` - Query telemetry metrics
- `list-available-metrics` - List metric definitions
- `list-billing-costs` - Retrieve billing data

**Required Environment Variables:**
```bash
TELEMETRY_ENDPOINT=https://api.telemetry.confluent.cloud
TELEMETRY_API_KEY=<cloud-api-key>     # Falls back to CONFLUENT_CLOUD_API_KEY
TELEMETRY_API_SECRET=<cloud-api-secret> # Falls back to CONFLUENT_CLOUD_API_SECRET
```

---

### 📊 Tableflow & Tableflow Catalog (10+ tools)

**Tools - Topic Management:**
- `create-tableflow-topic` - Create Tableflow-enabled topic
- `list-tableflow-topics` - List Tableflow topics
- `read-tableflow-topic` - Get topic details
- `update-tableflow-topic` - Modify topic settings
- `delete-tableflow-topic` - Remove topic
- `list-tableflow-regions` - List available regions

**Tools - Catalog Integration:**
- `create-tableflow-catalog-integration` - Create catalog connection
- `list-tableflow-catalog-integrations` - List integrations
- `read-tableflow-catalog-integration` - Get integration details
- `update-tableflow-catalog-integration` - Modify integration
- `delete-tableflow-catalog-integration` - Remove integration

**Required Environment Variables:**
```bash
TABLEFLOW_API_KEY=<kafka-api-key>         # Uses same credentials as Kafka
TABLEFLOW_API_SECRET=<kafka-api-secret>   # Uses same credentials as Kafka
TABLEFLOW_CATALOG_NAME=default_catalog
```

**Note:** Tableflow uses the same Kafka cluster API credentials. Automatically configured by Terraform.

---

## Summary

| Category | Tools | Status | Notes |
|----------|-------|--------|-------|
| Kafka & Topics | 6 | ✅ Ready | Fully configured |
| Tags & Catalog | 7 | ✅ Ready | All tag tools available |
| Flink SQL & Catalog | 10+ | ✅ Ready | Includes diagnostics |
| Connectors | 4 | ✅ Ready | Managed connectors |
| Schema Registry | 2 | ✅ Ready | Schema operations |
| Environments & Clusters | 3 | ✅ Ready | Organization-wide |
| Metrics & Billing | 3 | ✅ Ready | Telemetry & costs |
| **Tableflow & Catalog** | 10+ | ✅ Ready | Uses Kafka credentials |

**Total: 45+ tools ready out-of-the-box**

---

## Verification

After configuring, restart Claude Code and verify tool availability:

```bash
# In Claude Code, ask:
"List all available Confluent MCP tools"

# Or check specific categories:
"Can you add tags to topics?"
"Can you run Flink SQL queries?"
"Can you list Kafka topics?"
```

---

## Troubleshooting

### Tools Not Showing Up?

1. **Check configuration:**
   ```bash
   cat ~/.confluent-mcp/.env | grep -E "FLINK_ORG_ID|SCHEMA_REGISTRY_ENDPOINT|CONFLUENT_CLOUD_API_KEY"
   ```

2. **Reconfigure:**
   ```bash
   cd environment
   ./reconfigure-mcp.sh
   ```

3. **Restart Claude Code** (required to reload tools)

### Missing Specific Tool Category?

Check the required environment variables in this document and ensure they're set in `~/.confluent-mcp/.env`.

---

## References

- [Confluent MCP GitHub](https://github.com/confluentinc/mcp-confluent)
- [MCP Tools Documentation](https://github.com/confluentinc/mcp-confluent/blob/main/README.md)
- [Confluent Cloud Console](https://confluent.cloud)
