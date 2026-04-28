#!/bin/bash
set -euo pipefail

# Reconfigure MCP Server with Complete Environment Variables
# This script updates the MCP .env file with ALL required variables
# to enable all available tools including tag management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform-confluent-aws"
MCP_HOME="${MCP_HOME:-$HOME/.confluent-mcp}"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Reconfiguring Confluent MCP Server${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo -e "${YELLOW}Error: Terraform directory not found: $TERRAFORM_DIR${NC}"
    exit 1
fi

# Check if MCP home exists
if [ ! -d "$MCP_HOME" ]; then
    echo -e "${YELLOW}Error: MCP home directory not found: $MCP_HOME${NC}"
    echo "Run bootstrap.sh first to set up the MCP server"
    exit 1
fi

cd "$TERRAFORM_DIR"

echo -e "${BLUE}[1/3]${NC} Extracting credentials from Terraform..."

if ! terraform output -raw mcp_server_env_config > /tmp/mcp_config.tmp 2>/dev/null; then
    echo -e "${YELLOW}Error: Failed to extract credentials from Terraform${NC}"
    echo "Make sure you've run 'terraform apply' successfully"
    exit 1
fi

echo -e "${GREEN}✓${NC} Credentials extracted"

echo -e "${BLUE}[2/3]${NC} Backing up existing configuration..."

if [ -f "$MCP_HOME/.env" ]; then
    cp "$MCP_HOME/.env" "$MCP_HOME/.env.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${GREEN}✓${NC} Backup created"
else
    echo -e "${YELLOW}!${NC} No existing .env file found"
fi

echo -e "${BLUE}[3/3]${NC} Writing new configuration..."

cat /tmp/mcp_config.tmp > "$MCP_HOME/.env"
rm /tmp/mcp_config.tmp

echo -e "${GREEN}✓${NC} Configuration updated"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}MCP Server Reconfigured Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration file: $MCP_HOME/.env"
echo ""
echo -e "${GREEN}✅ ALL 45+ MCP Tools Enabled:${NC}"
echo ""
echo "📊 Kafka & Topics (6 tools)"
echo "   list-topics, create-topics, delete-topics, produce-message, consume-messages, etc."
echo ""
echo "🏷️  Tags & Catalog (7 tools) ⭐"
echo "   add-tags-to-topic, create-topic-tags, list-tags, search-topics-by-tag, etc."
echo ""
echo "🔧 Flink SQL & Catalog (10+ tools) ⭐"
echo "   create-flink-statement, list-flink-catalogs, list-flink-tables, etc."
echo ""
echo "🔌 Connectors (4 tools)"
echo "   list-connectors, create-connector, read-connector, delete-connector"
echo ""
echo "📋 Schema Registry (2 tools)"
echo "   list-schemas, delete-schema"
echo ""
echo "🌍 Environments & Clusters (3 tools)"
echo "   list-environments, read-environment, list-clusters"
echo ""
echo "📈 Metrics & Billing (3 tools)"
echo "   query-metrics, list-available-metrics, list-billing-costs"
echo ""
echo "📊 Tableflow & Catalog (10+ tools) ⭐"
echo "   create-tableflow-topic, list-tableflow-topics, list-tableflow-catalog-integrations, etc."
echo ""
echo -e "${YELLOW}⚠️  RESTART REQUIRED${NC}"
echo "   Restart Claude Code to load all 45+ MCP tools"
echo ""

# Show quick verification command
cd "$TERRAFORM_DIR"
if terraform output mcp_tools_status >/dev/null 2>&1; then
    echo -e "${BLUE}Full tool status:${NC}"
    terraform output -raw mcp_tools_status | head -20
    echo "   ..."
    echo ""
fi
cd - > /dev/null
