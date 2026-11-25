"""
Demo changes: a small, scripted burst of NEW data to show a change flowing through the whole pipeline live.

For N customers it produces
  * three digital interactions (mobile LOGIN -> VIEW_BALANCE -> PAYMENT) to digital.interactions (plain JSON), and
  * one card purchase to corebank.transactions (Avro),
all timestamped "now". Every event is ALSO written, with a plain producer, to c360_live_activity (Avro): the topic behind the
live feed. No Flink sits in that path, so its Lightning Table shows the event within about a second, while the Customer 360
table (written by a Flink statement) catches up when Flink commits its transaction, about a minute later.

Who is picked: the customers that have real balances but NO digital activity yet, richest first. That is exactly
the top of the "digital-inactive customers worth re-engaging" query, so after the burst those customers leave that
list and jump to the top of "live activity", with their last three actions and last purchase filled in. Each run
therefore picks the next inactive customers. If there are fewer than N, the richest already-active ones fill in.

Reads accounts and interactions straight from Kafka (no Trino/Polaris needed), so it also works for other
engines, for example the Lightning queries.

    python demo_changes.py --customers 3
    python demo_changes.py --customers 3 --dry-run           # show who would be picked, produce nothing
    python demo_changes.py --ids <customer_id>,<customer_id> # pick the customers yourself
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import random
import sys
import time
import uuid

from confluent_kafka import Consumer, Producer, SerializingProducer, TopicPartition
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer, AvroSerializer
from confluent_kafka.serialization import MessageField, SerializationContext, StringSerializer

import config

INTERACTIONS_TOPIC = "digital.interactions"
ACCOUNTS_TOPIC = "corebank.accounts"
TRANSACTIONS_TOPIC = "corebank.transactions"
CUSTOMERS_TOPIC = "corebank.customers"
ACTIVITY_TOPIC = "c360_live_activity"

# (merchant, MCC, min, max) — the same everyday categories as the data generator
PURCHASES = [
    ("Mercadona", "5411", 25, 120), ("Zara", "5311", 30, 140), ("Repsol", "5541", 40, 90),
    ("Cervecería Santa Ana", "5812", 15, 70), ("Farmacia Central", "5912", 8, 45),
]


def consumer_for(group_prefix):
    cfg = config.get_kafka_config()
    keep = ("bootstrap.servers", "security.protocol", "sasl.mechanisms", "sasl.username", "sasl.password")
    conf = {k: cfg[k] for k in keep}
    # assign() below never joins the group; the id only has to exist
    conf.update({"group.id": f"{group_prefix}-{uuid.uuid4().hex[:8]}", "enable.auto.commit": False,
                 "auto.offset.reset": "earliest"})
    return Consumer(conf)


def read_topic(topic, decode):
    """Every record currently in the topic, decoded. Stops at the end of each partition (or after 5 idle seconds)."""
    consumer = consumer_for("c360-demo-changes")
    try:
        meta = consumer.list_topics(topic, timeout=30)
        assignments, ends = [], {}
        for partition in meta.topics[topic].partitions:
            low, high = consumer.get_watermark_offsets(TopicPartition(topic, partition), timeout=30)
            if high > low:
                assignments.append(TopicPartition(topic, partition, low))
                ends[partition] = high
        consumer.assign(assignments)
        records, done, idle = [], set(), 0
        while len(done) < len(ends) and idle < (2 if records else 5):   # compacted topics have offset gaps: do not wait long at the end
            msg = consumer.poll(1.0)
            if msg is None:
                idle += 1
                continue
            if msg.error():
                continue
            idle = 0
            if msg.value() is not None:
                records.append(decode(msg))
            if msg.offset() + 1 >= ends[msg.partition()]:
                done.add(msg.partition())
        return records
    finally:
        consumer.close()


def accounts_by_customer():
    """customer_id -> list of the latest version of each of its accounts."""
    registry = SchemaRegistryClient(config.get_schema_registry_config())
    deserialize = AvroDeserializer(registry)
    latest = {}
    for account in read_topic(ACCOUNTS_TOPIC, lambda m: deserialize(m.value(), SerializationContext(ACCOUNTS_TOPIC, MessageField.VALUE))):
        latest[account["account_id"]] = account
    by_customer = {}
    for account in latest.values():
        by_customer.setdefault(account["customer_id"], []).append(account)
    return by_customer


def customer_names():
    """customer_id -> (full_name, segment), for the live feed (a Lightning query cannot join)."""
    registry = SchemaRegistryClient(config.get_schema_registry_config())
    deserialize = AvroDeserializer(registry)
    latest = {}
    for c in read_topic(CUSTOMERS_TOPIC, lambda m: deserialize(m.value(), SerializationContext(CUSTOMERS_TOPIC, MessageField.VALUE))):
        latest[c["customer_id"]] = (c["full_name"], c["segment"])
    return latest


def activity_topic_exists():
    consumer = consumer_for("c360-demo-changes")
    try:
        return ACTIVITY_TOPIC in consumer.list_topics(timeout=30).topics
    finally:
        consumer.close()


def activity_events(plan, names, now_ms):
    """The same events as the Kafka topics above, flattened for the live feed."""
    events = []
    for cid, _assets, _why, interactions, txn in plan:
        name, segment = names.get(cid, ("(unknown customer)", ""))
        base = {"customer_id": cid, "full_name": name, "segment": segment}
        for e in interactions:
            events.append({**base, "event_id": e["event_id"], "kind": "INTERACTION", "action": e["event_type"],
                           "channel": e["channel"], "amount": None, "ts": e["ts"]})
        events.append({**base, "event_id": txn["txn_id"], "kind": "PURCHASE", "action": txn["merchant_name"],
                       "channel": txn["channel"], "amount": txn["amount"], "ts": txn["ts"]})
    return sorted(events, key=lambda e: e["ts"])


def customers_with_digital_activity():
    return {event["customer_id"] for event in read_topic(INTERACTIONS_TOPIC, lambda m: json.loads(m.value().decode("utf-8")))}


def assets_of(accounts):
    return sum(a["balance"] for a in accounts if a["status"] != "CLOSED" and a["balance"] > 0)


def pick_customers(count, forced_ids, accounts, active):
    if forced_ids:
        unknown = [c for c in forced_ids if c not in accounts]
        if unknown:
            sys.exit(f"ERROR: no accounts found for customer id(s): {', '.join(unknown)}")
        return [(c, assets_of(accounts[c]), accounts[c], "chosen by you") for c in forced_ids], accounts
    ranked = sorted(((assets_of(a), c) for c, a in accounts.items() if assets_of(a) > 0), reverse=True)
    inactive = [(a, c) for a, c in ranked if c not in active]
    picked = [(c, a, accounts[c], "digital-inactive") for a, c in inactive[:count]]
    if len(picked) < count:
        extra = [(c, a, accounts[c], "already active (no inactive customers left)") for a, c in ranked if c in active]
        picked += extra[: count - len(picked)]
    return picked, accounts


def interaction_burst(customer_id, now_ms):
    """LOGIN -> VIEW_BALANCE -> PAYMENT on mobile, one minute apart, the last one 'now'."""
    session = str(uuid.uuid4())
    events = []
    for offset_s, event_type in ((120, "LOGIN"), (60, "VIEW_BALANCE"), (0, "PAYMENT")):
        events.append({"event_id": str(uuid.uuid4()), "customer_id": customer_id, "event_type": event_type,
                       "channel": "MOBILE", "session_id": session, "ts": now_ms - offset_s * 1000})
    return events


def purchase_for(accounts, now_ms):
    usable = [a for a in accounts if a["status"] == "ACTIVE"]
    checking = [a for a in usable if a["product_type"] == "CHECKING"]
    account = (checking or usable or accounts)[0]
    merchant, mcc, low, high = random.choice(PURCHASES)
    return {"txn_id": str(uuid.uuid4()), "account_id": account["account_id"], "amount": -round(random.uniform(low, high), 2),
            "currency": "EUR", "mcc": mcc, "merchant_name": merchant, "channel": "MOBILE", "ts": now_ms}


def delivery_report(err, msg):
    if err is not None:
        print(f"  x delivery failed: {err}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Add a small burst of new demo data")
    parser.add_argument("--customers", type=int, default=3, help="how many customers get new activity (default 3)")
    parser.add_argument("--ids", default="", help="comma-separated customer ids to use instead of the automatic pick")
    parser.add_argument("--dry-run", action="store_true", help="show the plan, produce nothing")
    args = parser.parse_args()

    forced = [c.strip() for c in args.ids.split(",") if c.strip()]
    # the three topic reads are independent: do them at the same time (the click-to-first-event delay is mostly this)
    with ThreadPoolExecutor(max_workers=3) as pool:
        f_accounts = pool.submit(accounts_by_customer)
        f_active = pool.submit(customers_with_digital_activity) if not forced else None
        f_names = pool.submit(customer_names) if not args.dry_run else None
        f_exists = pool.submit(activity_topic_exists) if not args.dry_run else None
        accounts, active = f_accounts.result(), (f_active.result() if f_active else set())
        prefetched = (f_exists.result() if f_exists else False, f_names.result() if f_names else {})
    picked, _ = pick_customers(args.customers, forced, accounts, active)
    if not picked:
        sys.exit("ERROR: no customers with accounts found — has `make data` run?")

    # everything slow (reading topics) happened BEFORE the clock is read, so the events' timestamps are the moment they are produced
    feed, names = prefetched
    if not args.dry_run and not feed:
        print(f"\n(note: topic {ACTIVITY_TOPIC} is not available, so the live feed is skipped — make prebuilt-up creates it)")

    now_ms = int(time.time() * 1000)
    plan = [(cid, assets, why, interaction_burst(cid, now_ms), purchase_for(accts, now_ms)) for cid, assets, accts, why in picked]

    print(f"\n{'Dry run: ' if args.dry_run else ''}new activity for {len(plan)} customer(s)\n")
    for cid, assets, why, events, txn in plan:
        print(f"  {cid}  assets {assets:>10,.0f} EUR  ({why})")
        print(f"      interactions : {' -> '.join(e['event_type'] for e in events)} (MOBILE)")
        print(f"      purchase     : {txn['merchant_name']}  {txn['amount']:.2f} EUR")
    if args.dry_run:
        print("\n(dry run: nothing was produced)")
        return

    plain = Producer({k: v for k, v in config.get_kafka_config().items() if k not in ("compression.type", "linger.ms", "batch.size")})
    registry = SchemaRegistryClient(config.get_schema_registry_config())
    avro = AvroSerializer(registry, config.load_avro_schema("transactions"), lambda txn, ctx: txn)
    avro_conf = config.get_kafka_config()
    avro_conf["key.serializer"] = StringSerializer("utf_8")
    avro_conf["value.serializer"] = avro
    avro_producer = SerializingProducer(avro_conf)

    # the fast path first: a plain producer, no Flink
    fast = 0
    if feed:
        activity_conf = config.get_kafka_config()
        activity_conf["key.serializer"] = StringSerializer("utf_8")
        activity_conf["value.serializer"] = AvroSerializer(registry, config.load_avro_schema("activity"), lambda e, ctx: e)
        activity_producer = SerializingProducer(activity_conf)
        for event in activity_events(plan, names, now_ms):
            activity_producer.produce(topic=ACTIVITY_TOPIC, key=event["event_id"], value=event,
                                     on_delivery=lambda err, msg: err and print(f"  (live feed delivery failed: {err})"))
            activity_producer.poll(0)
            fast += 1
        activity_producer.flush()

    for cid, assets, why, events, txn in plan:
        for event in events:
            plain.produce(INTERACTIONS_TOPIC, key=event["event_id"].encode("utf-8"),
                          value=json.dumps(event).encode("utf-8"), on_delivery=delivery_report)
        avro_producer.produce(topic=TRANSACTIONS_TOPIC, key=txn["txn_id"], value=txn, on_delivery=delivery_report)
        plain.poll(0)
        avro_producer.poll(0)
    plain.flush()
    avro_producer.flush()
    print(f"\nProduced {sum(len(p[3]) for p in plan)} interactions and {len(plan)} purchases."
          + (f" {fast} events also went straight to {ACTIVITY_TOPIC} (the live feed)." if fast else ""))


if __name__ == "__main__":
    main()
