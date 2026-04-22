"""
Transactions Producer - Generates realistic banking transaction data.
Produces to corebank.transactions topic with Avro serialization.
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

# Merchant categories with MCC codes and Spanish merchant examples
MERCHANT_CATEGORIES = {
    'grocery': {
        'mcc': '5411',
        'merchants': ['Mercadona', 'Carrefour', 'Lidl', 'Alcampo', 'Dia', 'Eroski'],
        'min_amount': 15.0,
        'max_amount': 150.0,
        'weight': 0.25
    },
    'dining': {
        'mcc': '5812',
        'merchants': ['Restaurante El Bulli', 'Cervecería Santa Ana', 'Tapas La Latina', 'Mesón Rincón', 'Taberna del Puerto'],
        'min_amount': 12.0,
        'max_amount': 120.0,
        'weight': 0.20
    },
    'fuel': {
        'mcc': '5541',
        'merchants': ['Repsol', 'Cepsa', 'BP', 'Shell', 'Galp'],
        'min_amount': 30.0,
        'max_amount': 90.0,
        'weight': 0.15
    },
    'retail': {
        'mcc': '5311',
        'merchants': ['El Corte Inglés', 'Zara', 'H&M', 'Mango', 'Fnac', 'Media Markt'],
        'min_amount': 20.0,
        'max_amount': 300.0,
        'weight': 0.15
    },
    'pharmacy': {
        'mcc': '5912',
        'merchants': ['Farmacia López', 'Farmacia Central', 'Farmacia del Sol', 'Farmacia Moderna'],
        'min_amount': 8.0,
        'max_amount': 65.0,
        'weight': 0.10
    },
    'utilities': {
        'mcc': '4900',
        'merchants': ['Iberdrola', 'Endesa', 'Naturgy', 'Telefónica', 'Vodafone', 'Orange'],
        'min_amount': 35.0,
        'max_amount': 150.0,
        'weight': 0.08
    },
    'transport': {
        'mcc': '4111',
        'merchants': ['Renfe', 'Metro Madrid', 'EMT', 'Cabify', 'Uber'],
        'min_amount': 3.0,
        'max_amount': 45.0,
        'weight': 0.05
    },
    'entertainment': {
        'mcc': '7832',
        'merchants': ['Cines Yelmo', 'Teatro Real', 'Spotify', 'Netflix', 'Amazon Prime'],
        'min_amount': 8.0,
        'max_amount': 50.0,
        'weight': 0.02
    }
}

# Channel distributions
CHANNEL_WEIGHTS = {
    'ONLINE': 0.40,
    'MOBILE': 0.30,
    'POS': 0.20,
    'ATM': 0.10
}


def select_merchant_category():
    """Select a merchant category based on weighted distribution."""
    categories = list(MERCHANT_CATEGORIES.keys())
    weights = [MERCHANT_CATEGORIES[cat]['weight'] for cat in categories]
    return random.choices(categories, weights=weights)[0]


def select_channel():
    """Select a transaction channel based on weighted distribution."""
    channels = list(CHANNEL_WEIGHTS.keys())
    weights = list(CHANNEL_WEIGHTS.values())
    return random.choices(channels, weights=weights)[0]


def generate_transaction(account_id):
    """Generate a single transaction record."""

    # Select merchant category and specific merchant
    category = select_merchant_category()
    category_data = MERCHANT_CATEGORIES[category]
    merchant_name = random.choice(category_data['merchants'])
    mcc = category_data['mcc']

    # Generate amount (negative for debit)
    amount = round(random.uniform(category_data['min_amount'], category_data['max_amount']), 2)
    amount = -amount  # Debit transaction (negative)

    # Select channel
    channel = select_channel()

    # Generate timestamp (within last 30 days for demo)
    days_ago = random.uniform(0, 30)
    seconds_ago = days_ago * 24 * 60 * 60
    ts = datetime.now() - timedelta(seconds=seconds_ago)

    transaction = {
        'txn_id': str(uuid.uuid4()),
        'account_id': account_id,
        'amount': amount,
        'currency': 'EUR',
        'mcc': mcc,
        'merchant_name': merchant_name,
        'channel': channel,
        'ts': int(ts.timestamp() * 1000)  # milliseconds
    }

    return transaction


def delivery_report(err, msg):
    """Kafka delivery callback."""
    if err is not None:
        print(f'✗ Message delivery failed: {err}')


def produce_transactions(account_ids, num_transactions=1000):
    """Produce transaction records to Kafka."""

    print(f"\n{'='*60}")
    print(f"Transactions Producer")
    print(f"{'='*60}\n")
    print(f"Target topic: corebank.transactions")
    print(f"Number of transactions: {num_transactions}")
    print(f"Number of accounts: {len(account_ids)}")
    print()

    # Load Avro schema
    schema_str = config.load_avro_schema('transactions')

    # Initialize Schema Registry client
    schema_registry_conf = config.get_schema_registry_config()
    schema_registry_client = SchemaRegistryClient(schema_registry_conf)

    # Create Avro serializer
    avro_serializer = AvroSerializer(
        schema_registry_client,
        schema_str,
        lambda txn, ctx: txn
    )

    # Producer configuration
    producer_conf = config.get_kafka_config()
    producer_conf['key.serializer'] = StringSerializer('utf_8')
    producer_conf['value.serializer'] = avro_serializer

    # Create producer
    producer = SerializingProducer(producer_conf)

    # Statistics tracking
    category_counts = {cat: 0 for cat in MERCHANT_CATEGORIES.keys()}
    channel_counts = {ch: 0 for ch in CHANNEL_WEIGHTS.keys()}
    total_amount = 0.0

    print("Producing transactions...")
    print()

    try:
        for i in range(num_transactions):
            # Randomly select an account
            account_id = random.choice(account_ids)

            # Generate transaction
            transaction = generate_transaction(account_id)

            # Track statistics
            for cat, data in MERCHANT_CATEGORIES.items():
                if transaction['mcc'] == data['mcc']:
                    category_counts[cat] += 1
                    break
            channel_counts[transaction['channel']] += 1
            total_amount += abs(transaction['amount'])

            # Use txn_id as the key
            producer.produce(
                topic='corebank.transactions',
                key=transaction['txn_id'],
                value=transaction,
                on_delivery=delivery_report
            )

            # Poll to handle delivery callbacks
            producer.poll(0)

            # Progress indicator every 100 transactions
            if (i + 1) % 100 == 0:
                print(f"Progress: {i + 1}/{num_transactions} transactions...")
                producer.flush()

        # Final flush
        print(f"\nFlushing remaining messages...")
        producer.flush()

        print()
        print(f"{'='*60}")
        print(f"✓ Successfully produced {num_transactions} transactions")
        print(f"{'='*60}\n")

        # Print statistics
        print(f"Total transaction volume: €{total_amount:,.2f}")
        print(f"Average transaction: €{total_amount / num_transactions:.2f}")
        print()

        print("Category Distribution:")
        for category, count in category_counts.items():
            pct = (count / num_transactions) * 100
            print(f"  {category}: {count} ({pct:.1f}%)")

        print()
        print("Channel Distribution:")
        for channel, count in channel_counts.items():
            pct = (count / num_transactions) * 100
            print(f"  {channel}: {count} ({pct:.1f}%)")

        print()

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    print("Error: This producer requires account IDs from producer_accounts.py")
    print("Run generate_all.py instead to execute producers in the correct order.")
    sys.exit(1)
