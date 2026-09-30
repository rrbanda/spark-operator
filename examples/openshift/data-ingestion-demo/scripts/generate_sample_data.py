#!/usr/bin/env python3
"""Generate synthetic data files that simulate NAS-landed raw files.

Creates:
  - transactions_batch_001.csv  (clean transaction records)
  - customers_batch_001.dat     (customer PII - includes restricted fields)
  - accounts_batch_001.csv      (account records with some schema violations)

Some records intentionally contain restricted PII fields (SSN, full name)
and schema violations to exercise the validation & classification logic.
"""

import csv
import os
import random
from datetime import datetime, timedelta

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "sample-data")

def random_ssn():
    return f"{random.randint(100,999)}-{random.randint(10,99)}-{random.randint(1000,9999)}"

def random_name():
    first = random.choice(["James","Mary","John","Patricia","Robert","Jennifer",
                           "Michael","Linda","David","Elizabeth","William","Barbara"])
    last = random.choice(["Smith","Johnson","Williams","Brown","Jones","Garcia",
                          "Miller","Davis","Rodriguez","Martinez","Wilson","Taylor"])
    return f"{first} {last}"

def random_account_id():
    return f"ACCT-{random.randint(100000, 999999)}"

def random_date(start_year=2024):
    start = datetime(start_year, 1, 1)
    delta = timedelta(days=random.randint(0, 365))
    return (start + delta).strftime("%Y-%m-%d")

def random_amount():
    return round(random.uniform(10.0, 50000.0), 2)


def generate_transactions(path, n=200):
    """Transactions: clean structured data with no PII."""
    headers = ["transaction_id", "account_id", "transaction_date",
               "amount", "currency", "transaction_type", "merchant", "status"]
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        for i in range(1, n + 1):
            writer.writerow([
                f"TXN-{i:06d}",
                random_account_id(),
                random_date(),
                random_amount(),
                random.choice(["USD", "EUR", "GBP"]),
                random.choice(["DEBIT", "CREDIT", "TRANSFER", "PAYMENT"]),
                random.choice(["Amazon", "Walmart", "Target", "Starbucks",
                               "Shell Gas", "United Airlines", "Netflix", "Uber"]),
                random.choice(["COMPLETED", "PENDING", "FAILED"]),
            ])
    print(f"  Created {path} ({n} records)")


def generate_customers(path, n=100):
    """Customers: includes restricted PII fields (SSN, full_name, dob).
    Uses pipe-delimited .dat format to simulate legacy file formats."""
    headers = ["customer_id", "full_name", "ssn", "date_of_birth",
               "email", "phone", "address", "city", "state", "zip_code",
               "risk_rating", "account_type"]
    with open(path, "w") as f:
        f.write("|".join(headers) + "\n")
        for i in range(1, n + 1):
            name = random_name()
            f.write("|".join([
                f"CUST-{i:05d}",
                name,
                random_ssn(),
                f"{random.randint(1950,2000)}-{random.randint(1,12):02d}-{random.randint(1,28):02d}",
                f"{name.split()[0].lower()}.{name.split()[1].lower()}@example.com",
                f"+1-{random.randint(200,999)}-{random.randint(100,999)}-{random.randint(1000,9999)}",
                f"{random.randint(100,9999)} {random.choice(['Main','Oak','Elm','Park','Broadway'])} St",
                random.choice(["New York", "Chicago", "Houston", "Phoenix", "Dallas"]),
                random.choice(["NY", "IL", "TX", "AZ", "TX"]),
                f"{random.randint(10000, 99999)}",
                random.choice(["LOW", "MEDIUM", "HIGH"]),
                random.choice(["CHECKING", "SAVINGS", "INVESTMENT", "CREDIT"]),
            ]) + "\n")
    print(f"  Created {path} ({n} records, pipe-delimited, contains PII)")


def generate_accounts(path, n=80):
    """Accounts: some rows have schema violations (missing fields, wrong types)."""
    headers = ["account_id", "customer_id", "account_type", "balance",
               "currency", "opened_date", "status", "branch_code"]
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        for i in range(1, n + 1):
            if i % 20 == 0:
                # Schema violation: missing fields
                writer.writerow([
                    random_account_id(), f"CUST-{random.randint(1,100):05d}",
                    "CHECKING", "", "USD",
                ])
            elif i % 15 == 0:
                # Schema violation: wrong type for balance
                writer.writerow([
                    random_account_id(), f"CUST-{random.randint(1,100):05d}",
                    "SAVINGS", "NOT_A_NUMBER", "USD",
                    random_date(2020), "ACTIVE", f"BR-{random.randint(100,999)}",
                ])
            else:
                writer.writerow([
                    random_account_id(), f"CUST-{random.randint(1,100):05d}",
                    random.choice(["CHECKING", "SAVINGS", "INVESTMENT", "CREDIT"]),
                    round(random.uniform(100.0, 500000.0), 2),
                    random.choice(["USD", "EUR", "GBP"]),
                    random_date(2020),
                    random.choice(["ACTIVE", "CLOSED", "FROZEN"]),
                    f"BR-{random.randint(100, 999)}",
                ])
    print(f"  Created {path} ({n} records, some with schema violations)")


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print("Generating sample banking data...")
    generate_transactions(os.path.join(OUTPUT_DIR, "transactions_batch_001.csv"))
    generate_customers(os.path.join(OUTPUT_DIR, "customers_batch_001.dat"))
    generate_accounts(os.path.join(OUTPUT_DIR, "accounts_batch_001.csv"))
    print("Done!")
