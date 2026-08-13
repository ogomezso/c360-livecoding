#!/usr/bin/env python3
"""
Customer 360 Data Generation Orchestrator
Runs all data producers in the correct sequence to populate demo topics.
"""
import sys
import time
import argparse
from datetime import datetime

# Import all producers
import producer_customers
import producer_accounts
import producer_transactions
import producer_interactions


def print_banner(title):
    """Print a section banner."""
    print()
    print("=" * 70)
    print(f"  {title}")
    print("=" * 70)
    print()


def print_summary(start_time):
    """Print final summary."""
    duration = time.time() - start_time
    minutes = int(duration // 60)
    seconds = int(duration % 60)

    print()
    print("=" * 70)
    print("  DATA GENERATION COMPLETE!")
    print("=" * 70)
    print()
    print(f"Total time: {minutes}m {seconds}s")
    print()
    print("Next steps:")
    print("  1. Verify topics with Claude MCP: 'List my Kafka topics'")
    print("  2. Sample data: Use MCP to check data in each topic")
    print("  3. Start building Flink SQL queries for customer_360_snapshot")
    print()


def main():
    """Main orchestrator function."""
    parser = argparse.ArgumentParser(
        description='Generate synthetic banking data for Customer 360 demo',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate with default values (200 customers)
  python generate_all.py

  # Generate with custom customer count
  python generate_all.py --customers 500

  # Generate more transactions
  python generate_all.py --transactions 2000

  # Quick demo with minimal data
  python generate_all.py --customers 50 --transactions 200
        """
    )

    parser.add_argument(
        '--customers',
        type=int,
        default=200,
        help='Number of customers to generate (default: 200)'
    )

    parser.add_argument(
        '--transactions',
        type=int,
        default=1000,
        help='Number of transactions to generate (default: 1000)'
    )

    parser.add_argument(
        '--interactions',
        type=int,
        default=800,
        help='Number of digital interactions to generate (default: 800)'
    )

    args = parser.parse_args()

    start_time = time.time()

    print_banner("Customer 360 Data Generator")
    print("This script will generate realistic Spanish banking data and populate:")
    print("  • corebank.customers")
    print("  • corebank.accounts")
    print("  • corebank.transactions")
    print("  • digital.interactions")
    print()
    print(f"Configuration:")
    print(f"  Customers: {args.customers}")
    print(f"  Transactions: {args.transactions}")
    print(f"  Interactions: {args.interactions}")
    print()

    try:
        # Step 1: Generate Customers
        print_banner("Step 1/4: Generating Customers")
        customer_ids = producer_customers.produce_customers(args.customers)
        print(f"\n✓ Generated {len(customer_ids)} customers")
        time.sleep(1)

        # Step 2: Generate Accounts
        print_banner("Step 2/4: Generating Accounts")
        account_ids = producer_accounts.produce_accounts(customer_ids)
        print(f"\n✓ Generated {len(account_ids)} accounts")
        time.sleep(1)

        # Step 3: Generate Transactions
        print_banner("Step 3/4: Generating Transactions")
        producer_transactions.produce_transactions(account_ids, args.transactions)
        print(f"\n✓ Generated {args.transactions} transactions")
        time.sleep(1)

        # Step 4: Generate Digital Interactions
        print_banner("Step 4/4: Generating Digital Interactions")
        producer_interactions.produce_interactions(customer_ids, args.interactions)
        print(f"\n✓ Generated ~{args.interactions} digital interactions")

        # Summary
        print_summary(start_time)

        return 0

    except KeyboardInterrupt:
        print("\n\n⚠️  Data generation interrupted by user")
        return 1
    except Exception as e:
        print(f"\n\n❌ Data generation failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
