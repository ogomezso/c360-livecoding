"""
Digital Interactions Producer - Generates realistic digital banking events.
Produces to digital.interactions topic as PLAIN JSON (schemaless).
This demonstrates Flink's ability to infer schemas from JSON data.
"""
import sys
import random
import uuid
import json
from datetime import datetime, timedelta
from confluent_kafka import Producer

import config

# Event type probabilities (weights)
EVENT_TYPE_WEIGHTS = {
    'LOGIN': 0.30,
    'VIEW_BALANCE': 0.25,
    'TRANSFER': 0.15,
    'PAYMENT': 0.12,
    'VIEW_STATEMENT': 0.10,
    'UPDATE_PROFILE': 0.05,
    'LOGOUT': 0.03
}

# Channel distribution
CHANNEL_WEIGHTS = {
    'MOBILE': 0.50,
    'WEB': 0.40,
    'TABLET': 0.10
}


def select_event_type():
    """Select an event type based on weighted distribution."""
    event_types = list(EVENT_TYPE_WEIGHTS.keys())
    weights = list(EVENT_TYPE_WEIGHTS.values())
    return random.choices(event_types, weights=weights)[0]


def select_channel():
    """Select a digital channel based on weighted distribution."""
    channels = list(CHANNEL_WEIGHTS.keys())
    weights = list(CHANNEL_WEIGHTS.values())
    return random.choices(channels, weights=weights)[0]


def generate_session_events(customer_id, num_events):
    """Generate a sequence of events for a single session."""
    session_id = str(uuid.uuid4())
    channel = select_channel()

    # Start with LOGIN
    events = []
    base_time = datetime.now() - timedelta(days=random.uniform(0, 30))

    # First event is always LOGIN
    events.append({
        'event_id': str(uuid.uuid4()),
        'customer_id': customer_id,
        'event_type': 'LOGIN',
        'channel': channel,
        'session_id': session_id,
        'ts': int(base_time.timestamp() * 1000)
    })

    # Generate middle events (VIEW_BALANCE, TRANSFER, etc.)
    for i in range(1, num_events - 1):
        # Increment time by a few seconds to minutes
        base_time += timedelta(seconds=random.randint(10, 180))

        event_type = select_event_type()
        # Skip LOGIN/LOGOUT for middle events
        while event_type in ['LOGIN', 'LOGOUT']:
            event_type = select_event_type()

        events.append({
            'event_id': str(uuid.uuid4()),
            'customer_id': customer_id,
            'event_type': event_type,
            'channel': channel,
            'session_id': session_id,
            'ts': int(base_time.timestamp() * 1000)
        })

    # Last event might be LOGOUT (70% of sessions end with logout)
    base_time += timedelta(seconds=random.randint(10, 300))
    if random.random() < 0.70:
        events.append({
            'event_id': str(uuid.uuid4()),
            'customer_id': customer_id,
            'event_type': 'LOGOUT',
            'channel': channel,
            'session_id': session_id,
            'ts': int(base_time.timestamp() * 1000)
        })

    return events


def delivery_report(err, msg):
    """Kafka delivery callback."""
    if err is not None:
        print(f'✗ Message delivery failed: {err}')


def produce_interactions(customer_ids, num_interactions=800):
    """Produce digital interaction events to Kafka as plain JSON (schemaless)."""

    print(f"\n{'='*60}")
    print(f"Digital Interactions Producer (JSON - Schemaless)")
    print(f"{'='*60}\n")
    print(f"Target topic: digital.interactions")
    print(f"Format: Plain JSON (no Schema Registry)")
    print(f"Target interactions: ~{num_interactions}")
    print(f"Number of customers: {len(customer_ids)}")
    print()
    print("NOTE: This topic demonstrates Flink's schema inference capability.")
    print("      Events are sent as plain JSON without Schema Registry serialization.")
    print()

    # Producer configuration - plain Kafka producer (no serializers)
    producer_conf = config.get_kafka_config()

    # Create producer
    producer = Producer(producer_conf)

    # Statistics tracking
    event_type_counts = {et: 0 for et in EVENT_TYPE_WEIGHTS.keys()}
    channel_counts = {ch: 0 for ch in CHANNEL_WEIGHTS.keys()}
    total_events = 0
    num_sessions = 0

    print("Producing digital interactions...")
    print()

    try:
        # Generate sessions until we reach target number of interactions
        while total_events < num_interactions:
            # Randomly select a customer
            customer_id = random.choice(customer_ids)

            # Generate 2-6 events per session
            events_per_session = random.randint(2, 6)
            session_events = generate_session_events(customer_id, events_per_session)

            num_sessions += 1

            for event in session_events:
                # Track statistics
                event_type_counts[event['event_type']] += 1
                channel_counts[event['channel']] += 1
                total_events += 1

                # Serialize to JSON and encode to bytes
                key_bytes = event['event_id'].encode('utf-8')
                value_bytes = json.dumps(event).encode('utf-8')

                # Produce to Kafka
                producer.produce(
                    topic='digital.interactions',
                    key=key_bytes,
                    value=value_bytes,
                    on_delivery=delivery_report
                )

                # Poll to handle delivery callbacks
                producer.poll(0)

            # Progress indicator every 20 sessions
            if num_sessions % 20 == 0:
                print(f"Progress: {num_sessions} sessions, {total_events} events...")
                producer.flush()

        # Final flush
        print(f"\nFlushing remaining messages...")
        producer.flush()

        print()
        print(f"{'='*60}")
        print(f"✓ Successfully produced {total_events} interaction events (JSON)")
        print(f"{'='*60}\n")

        # Print statistics
        print(f"Number of sessions: {num_sessions}")
        print(f"Average events per session: {total_events / num_sessions:.2f}")
        print()

        print("Event Type Distribution:")
        for event_type, count in event_type_counts.items():
            pct = (count / total_events) * 100
            print(f"  {event_type}: {count} ({pct:.1f}%)")

        print()
        print("Channel Distribution:")
        for channel, count in channel_counts.items():
            pct = (count / total_events) * 100
            print(f"  {channel}: {count} ({pct:.1f}%)")

        print()
        print("💡 Flink Demo Tip:")
        print("   This topic uses plain JSON (no Schema Registry).")
        print("   Use Flink SQL to infer and query the schema dynamically!")
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
    print("Error: This producer requires customer IDs from producer_customers.py")
    print("Run generate_all.py instead to execute producers in the correct order.")
    sys.exit(1)
