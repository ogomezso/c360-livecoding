# Customer 360 Demo - Data Generation

Synthetic data generators for populating the Customer 360 demo with realistic Spanish banking data.

## Overview

This directory contains Python producers that generate realistic synthetic banking data for 4 Kafka topics:

- **corebank.customers** - Customer master data (Spanish names, segments, risk bands) - Avro
- **corebank.accounts** - Banking accounts linked to customers - Avro
- **corebank.transactions** - Transaction events (Spanish merchants, EUR, MCC codes) - Avro
- **digital.interactions** - Digital channel interactions (web/mobile/tablet) - **Plain JSON (schemaless)**

**Note**: The `digital.interactions` topic uses plain JSON without Schema Registry to demonstrate **Flink's schema inference capability**. Flink can dynamically infer and query JSON schemas without pre-registered schemas.

## Quick Start

### Option 1: Run during bootstrap (recommended)

```bash
cd ../..
make up        # or: scripts/bootstrap.sh
# Select 'Y' when prompted to generate demo data
```

### Option 2: Run standalone

```bash
cd ../..
make data      # or: scripts/generate-data.sh
```

### Option 3: Run Python directly

```bash
cd producers
python3 -m venv .venv
source .venv/bin/activate
pip install -r ../requirements.txt
python3 generate_all.py
```

## Data Characteristics

### Customers (200 default)

- **Names**: Realistic Spanish names using Faker `es_ES` locale
- **Segments**: 70% RETAIL, 20% PREMIER, 10% PRIVATE
- **Risk Bands**: 60% LOW, 30% MEDIUM, 10% HIGH
- **Relationship Managers**: Assigned to PREMIER and PRIVATE customers
- **Contact Info**: Spanish email addresses and phone numbers

Example:
```json
{
  "customer_id": "a1b2c3d4-...",
  "full_name": "María García López",
  "segment": "PREMIER",
  "risk_band": "LOW",
  "relationship_manager": "Carlos Fernández Ruiz",
  "email": "maria.garcia@example.es",
  "phone": "+34 912 345 678",
  "created_at": 1679568000000
}
```

### Accounts (400+ default, 1-5 per customer)

- **Product Distribution**:
  - 80% CHECKING
  - 50% SAVINGS
  - 30% CREDIT_CARD
  - 15% MORTGAGE
  - 10% INVESTMENT

- **Balances**: Realistic EUR amounts per product type
  - Checking: €100 - €15,000
  - Savings: €500 - €50,000
  - Credit Card: -€5,000 - €0 (negative = owed)
  - Mortgage: -€500,000 - -€50,000 (loan)
  - Investment: €5,000 - €250,000

- **Status**: 90%+ ACTIVE, some DORMANT/CLOSED

### Transactions (1,000+ default)

- **Merchants**: Realistic Spanish merchants across 8 categories
  - Grocery: Mercadona, Carrefour, Lidl
  - Dining: Spanish restaurants and tapas bars
  - Fuel: Repsol, Cepsa, BP
  - Retail: El Corte Inglés, Zara, H&M
  - Pharmacy: Spanish pharmacies
  - Utilities: Iberdrola, Telefónica, Vodafone
  - Transport: Renfe, Metro Madrid, Cabify
  - Entertainment: Netflix, Spotify, Cines Yelmo

- **MCC Codes**: Industry-standard merchant category codes
- **Amounts**: Realistic EUR ranges per category (€3 - €500 typical)
- **Channels**: 40% ONLINE, 30% MOBILE, 20% POS, 10% ATM
- **Timestamps**: Distributed over last 30 days

### Digital Interactions (800+ default) - **Schemaless JSON**

⚡ **This topic demonstrates Flink's schema inference!** Events are sent as plain JSON without Schema Registry.

- **Event Types**: LOGIN, VIEW_BALANCE, TRANSFER, PAYMENT, VIEW_STATEMENT, UPDATE_PROFILE, LOGOUT
- **Channels**: 50% MOBILE, 40% WEB, 10% TABLET
- **Sessions**: 2-6 events per session
- **Behavior**: 70% of sessions end with LOGOUT
- **Format**: Plain JSON (no Avro, no Schema Registry serialization)
- **Flink Capability**: Flink can infer the schema dynamically from JSON data

## Customization

### Adjust Data Volume

```bash
make data CUSTOMERS=500 TRANSACTIONS=2000 INTERACTIONS=1500
# or: scripts/generate-data.sh 500 2000 1500   (customers, transactions, interactions)
```

Or with Python:
```bash
python3 generate_all.py --customers 500 --transactions 2000 --interactions 1500
```

### Modify Data Characteristics

Edit the producer files in `producers/`:

- `producer_customers.py` - Adjust segment/risk distributions
- `producer_accounts.py` - Change product probabilities, balance ranges
- `producer_transactions.py` - Add merchants, adjust MCC codes, amounts
- `producer_interactions.py` - Modify event type distributions

### Change Schemas

Edit Avro schemas in `schemas/`:

- `customers-value.avsc`
- `accounts-value.avsc`
- `transactions-value.avsc`

**Note**: `digital.interactions` uses plain JSON (no schema file) to demonstrate Flink's schema inference.

Avro schemas are auto-registered with Schema Registry on first produce.

## Architecture

### Data Flow

```
generate-data.sh
  ├─ Setup Python venv
  ├─ Load Kafka credentials
  └─ Run generate_all.py
       ├─ producer_customers.py → corebank.customers
       ├─ producer_accounts.py → corebank.accounts (uses customer_ids)
       ├─ producer_transactions.py → corebank.transactions (uses account_ids)
       └─ producer_interactions.py → digital.interactions (uses customer_ids)
```

### Dependencies

- **confluent-kafka[avro]** - Kafka producer with Avro serialization
- **faker** - Realistic fake data generation (es_ES locale)
- **python-dotenv** - Environment variable loading

### Configuration

Producers read Kafka credentials from, in order:
1. `../mcp-confluent/.env` (populated by `bootstrap.sh`/`reconfigure-mcp.sh`)
2. `~/.confluent-mcp/.env` (legacy global location, if present)
3. `../terraform-confluent-aws/.env.local` (Terraform output)

Required variables:
- `KAFKA_API_KEY`
- `KAFKA_API_SECRET`
- `BOOTSTRAP_SERVERS`
- `KAFKA_REST_ENDPOINT`

## Validation

### Using Claude MCP

```
List my Kafka topics
Sample records from corebank.customers
Sample records from corebank.accounts
Sample records from corebank.transactions
Sample records from digital.interactions
```

### Using Confluent Cloud Console

1. Navigate to your Kafka cluster
2. Go to Topics
3. Click each topic and view Messages

### Using Flink SQL

```sql
SELECT * FROM `corebank.customers` LIMIT 10;
SELECT * FROM `corebank.accounts` LIMIT 10;
SELECT * FROM `corebank.transactions` LIMIT 10;
SELECT * FROM `digital.interactions` LIMIT 10;
```

## Troubleshooting

### "Missing required Kafka credentials"

Ensure you've run `bootstrap.sh` or manually configured credentials in:
- `../mcp-confluent/.env`
- `../terraform-confluent-aws/.env.local`

### "Connection refused" or timeout errors

- Verify Kafka cluster is running: Check Confluent Cloud console
- Confirm API keys are valid: `terraform output -raw kafka_api_key`
- Check bootstrap servers: `echo $BOOTSTRAP_SERVERS`

### Schema Registry errors

- Ensure Schema Registry URL is accessible
- Verify API credentials have Schema Registry permissions
- Check that topics exist (created by Terraform in `../terraform-confluent-aws/topics.tf`)

### Low data quality

- Increase customer count for better distribution
- Adjust weights in producer files for different patterns
- Generate multiple times and average results

## Re-generating Data

To refresh data during demos:

```bash
# Option 1: Quick refresh (delete and regenerate)
make data

# Option 2: Just add more data (won't delete existing)
cd producers
python3 generate_all.py --customers 100 --transactions 500
```

**Note**: Customers and Accounts topics use compacted storage (keyed by ID), so re-generating with same IDs will update existing records. Transactions and Interactions append new events.

## Integration with Demo

This data serves as the source for the Customer 360 data product built with Flink SQL:

1. **Explore** topics and schemas with Claude MCP
2. **Design** `customer_360_snapshot` schema with Claude
3. **Generate** Flink SQL DDL for source tables
4. **Create** aggregation logic joining all 4 topics
5. **Validate** results with sample queries

See main [README.md](../../README.md) for the complete demo flow.
