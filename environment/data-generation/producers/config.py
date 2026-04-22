"""
Configuration for Kafka producers.
Loads credentials from environment variables and provides shared configuration.
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from .env.local if it exists
env_file = Path(__file__).parent.parent.parent / "terraform-confluent-aws" / ".env.local"
if env_file.exists():
    load_dotenv(env_file)

# Also try MCP .env location
mcp_env = Path.home() / ".confluent-mcp" / ".env"
if mcp_env.exists():
    load_dotenv(mcp_env)


def get_kafka_config():
    """Get Kafka producer configuration from environment."""

    # Try to get from MCP .env first
    kafka_api_key = os.getenv("KAFKA_API_KEY")
    kafka_api_secret = os.getenv("KAFKA_API_SECRET")
    bootstrap_servers = os.getenv("BOOTSTRAP_SERVERS")

    if not kafka_api_key or not kafka_api_secret or not bootstrap_servers:
        print("ERROR: Missing required Kafka credentials")
        print("Required environment variables:")
        print("  - KAFKA_API_KEY")
        print("  - KAFKA_API_SECRET")
        print("  - BOOTSTRAP_SERVERS")
        print("\nThese should be set in:")
        print(f"  - {env_file}")
        print(f"  - {mcp_env}")
        sys.exit(1)

    config = {
        'bootstrap.servers': bootstrap_servers,
        'security.protocol': 'SASL_SSL',
        'sasl.mechanisms': 'PLAIN',
        'sasl.username': kafka_api_key,
        'sasl.password': kafka_api_secret,
        'client.id': 'customer-360-data-generator',
        # Performance tuning
        'compression.type': 'snappy',
        'linger.ms': 100,
        'batch.size': 32768,
        'acks': 'all',
    }

    return config


def get_schema_registry_config():
    """Get Schema Registry configuration from environment."""

    schema_registry_url = os.getenv("SCHEMA_REGISTRY_URL")
    schema_registry_api_key = os.getenv("SCHEMA_REGISTRY_API_KEY")
    schema_registry_api_secret = os.getenv("SCHEMA_REGISTRY_API_SECRET")

    if not schema_registry_url or not schema_registry_api_key or not schema_registry_api_secret:
        print("ERROR: Missing required Schema Registry credentials")
        print("Required environment variables:")
        print("  - SCHEMA_REGISTRY_URL")
        print("  - SCHEMA_REGISTRY_API_KEY")
        print("  - SCHEMA_REGISTRY_API_SECRET")
        print("\nThese should be set by the Terraform configuration.")
        sys.exit(1)

    config = {
        'url': schema_registry_url,
        'basic.auth.user.info': f'{schema_registry_api_key}:{schema_registry_api_secret}'
    }

    return config


def load_avro_schema(schema_name):
    """Load an Avro schema from the schemas directory."""
    schema_file = Path(__file__).parent.parent / "schemas" / f"{schema_name}-value.avsc"

    if not schema_file.exists():
        print(f"ERROR: Schema file not found: {schema_file}")
        sys.exit(1)

    with open(schema_file, 'r') as f:
        return f.read()


# Validate configuration on import
def validate_config():
    """Validate that all required configuration is available."""
    try:
        get_kafka_config()
        get_schema_registry_config()
        print("✓ Configuration validated successfully")
        return True
    except SystemExit:
        return False


if __name__ == "__main__":
    # Test configuration when run directly
    print("Testing Kafka producer configuration...")
    print()

    if validate_config():
        print()
        print("Kafka Configuration:")
        kafka_cfg = get_kafka_config()
        print(f"  Bootstrap: {kafka_cfg['bootstrap.servers']}")
        print(f"  Client ID: {kafka_cfg['client.id']}")
        print()
        print("Schema Registry Configuration:")
        sr_cfg = get_schema_registry_config()
        print(f"  URL: {sr_cfg['url']}")
        print()
        print("All configurations loaded successfully!")
    else:
        print()
        print("Configuration validation failed!")
        sys.exit(1)
