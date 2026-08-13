#!/usr/bin/env bash
# Tag corebanking topics with c360 and source tags

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_DIR="$SCRIPT_DIR/environment/mcp-confluent"

cd "$MCP_DIR"

echo "================================================="
echo "Tagging Corebanking Topics"
echo "================================================="

# Source value - change this as needed
SOURCE_VALUE="${1:-corebank}"

echo ""
echo "Tags to add:"
echo "  - c360"
echo "  - source: $SOURCE_VALUE"
echo ""

# Load environment
set -a
source .env
set +a

# Topics to tag
TOPICS=("corebank.accounts" "corebank.customers" "corebank.transactions")

echo "Step 1: Creating tag definitions (if they don't exist)..."
echo ""

# Create c360 tag
npx -y @confluentinc/mcp-confluent --config config.yaml <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "create-topic-tags",
    "arguments": {
      "tags": [
        {
          "name": "c360",
          "description": "Customer 360 related topics"
        },
        {
          "name": "source",
          "description": "Source system identifier"
        }
      ]
    }
  }
}
EOF

echo ""
echo "Step 2: Adding tags to topics..."
echo ""

for topic in "${TOPICS[@]}"; do
  echo "Tagging topic: $topic"

  # Add both tags
  npx -y @confluentinc/mcp-confluent --config config.yaml <<EOF
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "add-tags-to-topic",
    "arguments": {
      "topic_name": "$topic",
      "tags": [
        {
          "tag_name": "c360"
        },
        {
          "tag_name": "source",
          "tag_value": "$SOURCE_VALUE"
        }
      ]
    }
  }
}
EOF

  echo "  ✓ Tagged $topic"
  echo ""
done

echo "================================================="
echo "Tagging complete!"
echo "================================================="
echo ""
echo "Verify with:"
echo "  Ask Claude Code: \"search topics by tag\" (uses the search-topics-by-tag MCP tool)"
