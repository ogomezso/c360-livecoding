"""
Accounts Producer - Generates realistic banking account data linked to customers.
Produces to corebank.accounts topic with Avro serialization.
"""
import sys
import random
import uuid
from datetime import datetime, timedelta
from confluent_kafka import SerializingProducer
from confluent_kafka.serialization import StringSerializer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer

import config

# Product type probabilities and typical balance ranges (in EUR)
PRODUCT_CONFIG = {
    'CHECKING': {
        'probability': 0.80,  # 80% of customers have checking
        'min_balance': 100,
        'max_balance': 15000,
        'status_distribution': {'ACTIVE': 0.95, 'DORMANT': 0.04, 'CLOSED': 0.01}
    },
    'SAVINGS': {
        'probability': 0.50,  # 50% have savings
        'min_balance': 500,
        'max_balance': 50000,
        'status_distribution': {'ACTIVE': 0.90, 'DORMANT': 0.08, 'CLOSED': 0.02}
    },
    'CREDIT_CARD': {
        'probability': 0.30,  # 30% have credit cards
        'min_balance': -5000,  # Negative = owed amount
        'max_balance': 0,
        'status_distribution': {'ACTIVE': 0.85, 'DORMANT': 0.10, 'CLOSED': 0.05}
    },
    'MORTGAGE': {
        'probability': 0.15,  # 15% have mortgages
        'min_balance': -500000,  # Negative = outstanding loan
        'max_balance': -50000,
        'status_distribution': {'ACTIVE': 0.98, 'DORMANT': 0, 'CLOSED': 0.02}
    },
    'INVESTMENT': {
        'probability': 0.10,  # 10% have investments
        'min_balance': 5000,
        'max_balance': 250000,
        'status_distribution': {'ACTIVE': 0.92, 'DORMANT': 0.05, 'CLOSED': 0.03}
    }
}


def determine_account_status(product_type):
    """Determine account status based on product type distribution."""
    status_dist = PRODUCT_CONFIG[product_type]['status_distribution']
    rand = random.random()

    if rand < status_dist['ACTIVE']:
        return 'ACTIVE'
    elif rand < status_dist['ACTIVE'] + status_dist['DORMANT']:
        return 'DORMANT'
    else:
        return 'CLOSED'


def generate_account(customer_id, product_type):
    """Generate a single account record for a customer."""

    config_entry = PRODUCT_CONFIG[product_type]

    # Generate realistic balance
    balance = round(random.uniform(config_entry['min_balance'], config_entry['max_balance']), 2)

    # Determine status
    status = determine_account_status(product_type)

    # Generate account opening date (within customer's lifetime, assume created in past 5 years)
    days_ago = random.randint(0, 365 * 5)
    opened_at = datetime.now() - timedelta(days=days_ago)

    account = {
        'account_id': str(uuid.uuid4()),
        'customer_id': customer_id,
        'product_type': product_type,
        'status': status,
        'balance': balance,
        'currency': 'EUR',
        'opened_at': int(opened_at.timestamp() * 1000)  # milliseconds
    }

    return account


def generate_accounts_for_customer(customer_id):
    """Generate 1-5 accounts for a single customer based on product probabilities."""
    accounts = []

    for product_type, config_entry in PRODUCT_CONFIG.items():
        # Decide if customer has this product type
        if random.random() < config_entry['probability']:
            account = generate_account(customer_id, product_type)
            accounts.append(account)

    # Ensure at least one account (checking if nothing else)
    if not accounts:
        account = generate_account(customer_id, 'CHECKING')
        accounts.append(account)

    return accounts


def delivery_report(err, msg):
    """Kafka delivery callback."""
    if err is not None:
        print(f'✗ Message delivery failed: {err}')
    else:
        print(f'✓ Account produced to {msg.topic()} [{msg.partition()}] @ {msg.offset()}')


def produce_accounts(customer_ids):
    """Produce account records to Kafka for all customers."""

    print(f"\n{'='*60}")
    print(f"Accounts Producer")
    print(f"{'='*60}\n")
    print(f"Target topic: corebank.accounts")
    print(f"Number of customers: {len(customer_ids)}")
    print()

    # Load Avro schema
    schema_str = config.load_avro_schema('accounts')

    # Initialize Schema Registry client
    schema_registry_conf = config.get_schema_registry_config()
    schema_registry_client = SchemaRegistryClient(schema_registry_conf)

    # Create Avro serializer
    avro_serializer = AvroSerializer(
        schema_registry_client,
        schema_str,
        lambda account, ctx: account
    )

    # Producer configuration
    producer_conf = config.get_kafka_config()
    producer_conf['key.serializer'] = StringSerializer('utf_8')
    producer_conf['value.serializer'] = avro_serializer

    # Create producer
    producer = SerializingProducer(producer_conf)

    # Generate and produce accounts
    all_accounts = []
    product_counts = {product: 0 for product in PRODUCT_CONFIG.keys()}

    print("Producing accounts...")
    print()

    try:
        for idx, customer_id in enumerate(customer_ids):
            # Generate accounts for this customer
            accounts = generate_accounts_for_customer(customer_id)

            for account in accounts:
                all_accounts.append(account)
                product_counts[account['product_type']] += 1

                # Use account_id as the key for compaction
                producer.produce(
                    topic='corebank.accounts',
                    key=account['account_id'],
                    value=account,
                    on_delivery=delivery_report
                )

                # Poll to handle delivery callbacks
                producer.poll(0)

            # Progress indicator every 50 customers
            if (idx + 1) % 50 == 0:
                print(f"Progress: {idx + 1}/{len(customer_ids)} customers...")
                producer.flush()

        # Final flush
        print(f"\nFlushing remaining messages...")
        producer.flush()

        print()
        print(f"{'='*60}")
        print(f"✓ Successfully produced {len(all_accounts)} accounts for {len(customer_ids)} customers")
        print(f"{'='*60}\n")

        # Print statistics
        print(f"Average accounts per customer: {len(all_accounts) / len(customer_ids):.2f}")
        print()
        print("Product Type Distribution:")
        for product, count in product_counts.items():
            pct = (count / len(all_accounts)) * 100
            print(f"  {product}: {count} ({pct:.1f}%)")

        print()

        # Return account IDs for use by transaction producer
        return [a['account_id'] for a in all_accounts]

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    print("Error: This producer requires customer IDs from producer_customers.py")
    print("Run generate_all.py instead to execute producers in the correct order.")
    sys.exit(1)
