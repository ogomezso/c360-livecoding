"""
Customer Producer - Generates realistic Spanish banking customer data.
Produces to corebank.customers topic with Avro serialization.
"""
import sys
import time
import random
import uuid
from datetime import datetime, timedelta
from faker import Faker
from confluent_kafka import SerializingProducer
from confluent_kafka.serialization import StringSerializer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer

import config

# Initialize Faker with Spanish locale for realistic Spanish names
fake = Faker('es_ES')

# Relationship managers for premier/private customers
RELATIONSHIP_MANAGERS = [
    "María García López",
    "Carlos Fernández Ruiz",
    "Isabel Martínez Sánchez",
    "Javier Rodríguez Pérez",
    "Ana López González",
    "Miguel Sánchez Díaz",
    "Carmen González Martín",
    "Francisco Romero Torres"
]


def generate_customer():
    """Generate a single customer record."""

    # Determine segment (70% retail, 20% premier, 10% private)
    segment_rand = random.random()
    if segment_rand < 0.70:
        segment = "RETAIL"
    elif segment_rand < 0.90:
        segment = "PREMIER"
    else:
        segment = "PRIVATE"

    # Determine risk band (60% low, 30% medium, 10% high)
    risk_rand = random.random()
    if risk_rand < 0.60:
        risk_band = "LOW"
    elif risk_rand < 0.90:
        risk_band = "MEDIUM"
    else:
        risk_band = "HIGH"

    # Relationship manager only for premier/private
    rm = None
    if segment in ["PREMIER", "PRIVATE"]:
        rm = random.choice(RELATIONSHIP_MANAGERS)

    # Generate customer creation date (sometime in the past 5 years)
    days_ago = random.randint(0, 365 * 5)
    created_at = datetime.now() - timedelta(days=days_ago)

    customer = {
        'customer_id': str(uuid.uuid4()),
        'full_name': fake.name(),
        'segment': segment,
        'risk_band': risk_band,
        'relationship_manager': rm,
        'email': fake.email(),
        'phone': fake.phone_number(),
        'created_at': int(created_at.timestamp() * 1000)  # milliseconds
    }

    return customer


def delivery_report(err, msg):
    """Kafka delivery callback."""
    if err is not None:
        print(f'✗ Message delivery failed: {err}')
    else:
        print(f'✓ Customer produced to {msg.topic()} [{msg.partition()}] @ {msg.offset()}')


def produce_customers(num_customers=200):
    """Produce customer records to Kafka."""

    print(f"\n{'='*60}")
    print(f"Customer Producer")
    print(f"{'='*60}\n")
    print(f"Target topic: corebank.customers")
    print(f"Number of customers: {num_customers}")
    print(f"Locale: Spanish (es_ES)")
    print()

    # Load Avro schema
    schema_str = config.load_avro_schema('customers')

    # Initialize Schema Registry client
    schema_registry_conf = config.get_schema_registry_config()
    schema_registry_client = SchemaRegistryClient(schema_registry_conf)

    # Create Avro serializer
    avro_serializer = AvroSerializer(
        schema_registry_client,
        schema_str,
        lambda customer, ctx: customer  # to_dict function (already a dict)
    )

    # Producer configuration
    producer_conf = config.get_kafka_config()
    producer_conf['key.serializer'] = StringSerializer('utf_8')
    producer_conf['value.serializer'] = avro_serializer

    # Create producer
    producer = SerializingProducer(producer_conf)

    # Generate and produce customers
    customers_produced = []

    print("Producing customers...")
    print()

    try:
        for i in range(num_customers):
            customer = generate_customer()
            customers_produced.append(customer)

            # Use customer_id as the key for compaction
            producer.produce(
                topic='corebank.customers',
                key=customer['customer_id'],
                value=customer,
                on_delivery=delivery_report
            )

            # Poll to handle delivery callbacks
            producer.poll(0)

            # Progress indicator every 50 customers
            if (i + 1) % 50 == 0:
                print(f"Progress: {i + 1}/{num_customers} customers...")
                producer.flush()

        # Final flush
        print(f"\nFlushing remaining messages...")
        producer.flush()

        print()
        print(f"{'='*60}")
        print(f"✓ Successfully produced {len(customers_produced)} customers")
        print(f"{'='*60}\n")

        # Print some statistics
        segments = {'RETAIL': 0, 'PREMIER': 0, 'PRIVATE': 0}
        risk_bands = {'LOW': 0, 'MEDIUM': 0, 'HIGH': 0}

        for c in customers_produced:
            segments[c['segment']] += 1
            risk_bands[c['risk_band']] += 1

        print("Segment Distribution:")
        for seg, count in segments.items():
            pct = (count / len(customers_produced)) * 100
            print(f"  {seg}: {count} ({pct:.1f}%)")

        print()
        print("Risk Band Distribution:")
        for risk, count in risk_bands.items():
            pct = (count / len(customers_produced)) * 100
            print(f"  {risk}: {count} ({pct:.1f}%)")

        print()

        # Save customer IDs for use by other producers
        return [c['customer_id'] for c in customers_produced]

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    # Run standalone
    import argparse

    parser = argparse.ArgumentParser(description='Generate customer data for Customer 360 demo')
    parser.add_argument('--count', type=int, default=200, help='Number of customers to generate (default: 200)')
    args = parser.parse_args()

    produce_customers(args.count)
