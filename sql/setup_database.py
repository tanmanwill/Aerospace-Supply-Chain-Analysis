print("Starting database setup...")

import sqlite3
import pandas as pd
from pathlib import Path

# Define project paths
PROJECT_DIR = Path(__file__).resolve().parent.parent
CLEAN_DIR = PROJECT_DIR / "data" / "cleaned"
DB_PATH = PROJECT_DIR / "aerospace_supply_chain.db"

# Connect to SQLite
conn = sqlite3.connect(DB_PATH)

# Enable foreign key enforcement
conn.execute("PRAGMA foreign_keys = ON;")

print("Connected to SQLite successfully.")
print(f"Database path: {DB_PATH}")


# Create relational database tables
conn.executescript("""
CREATE TABLE IF NOT EXISTS suppliers (
    SupplierID TEXT PRIMARY KEY,
    SupplierName TEXT NOT NULL,
    Location TEXT,
    SupplierCategory TEXT,
    ReliabilityRating REAL
);

CREATE TABLE IF NOT EXISTS components (
    ComponentID TEXT PRIMARY KEY,
    ComponentName TEXT NOT NULL,
    Category TEXT,
    UnitCost REAL,
    SafetyStock INTEGER,
    LeadTimeDays INTEGER,
    SupplierID TEXT,
    CurrentStock INTEGER,
    FOREIGN KEY (SupplierID)
        REFERENCES suppliers(SupplierID)
);

CREATE TABLE IF NOT EXISTS purchase_orders (
    OrderID TEXT PRIMARY KEY,
    SupplierID TEXT NOT NULL,
    ComponentID TEXT NOT NULL,
    OrderDate TEXT,
    QuantityOrdered INTEGER,
    UnitPrice REAL,
    TotalCost REAL,
    ExpectedDeliveryDate TEXT,
    FOREIGN KEY (SupplierID)
        REFERENCES suppliers(SupplierID),
    FOREIGN KEY (ComponentID)
        REFERENCES components(ComponentID)
);

CREATE TABLE IF NOT EXISTS shipments (
    ShipmentID TEXT PRIMARY KEY,
    OrderID TEXT NOT NULL UNIQUE,
    ActualDeliveryDate TEXT,
    QuantityReceived INTEGER,
    ShippingCost REAL,
    DefectiveUnits INTEGER,
    DeliveryStatus TEXT,
    FOREIGN KEY (OrderID)
        REFERENCES purchase_orders(OrderID)
);

CREATE TABLE IF NOT EXISTS inventory_movements (
    MovementID TEXT PRIMARY KEY,
    ComponentID TEXT NOT NULL,
    MovementDate TEXT,
    MovementType TEXT,
    Quantity INTEGER,
    OrderID TEXT,
    StockAfterMovement INTEGER,
    FOREIGN KEY (ComponentID)
        REFERENCES components(ComponentID),
    FOREIGN KEY (OrderID)
        REFERENCES purchase_orders(OrderID)
);
""")

print("All five database tables created!")



# Tables must be imported in dependency order
table_order = [
    "suppliers",
    "components",
    "purchase_orders",
    "shipments",
    "inventory_movements"
]

# Load all CSV files before changing the database
dataframes = {
    table: pd.read_csv(
        CLEAN_DIR / f"{table}.csv",
        dtype={"OrderID": "string"}
    )
    for table in table_order
}

# Use one transaction for the refresh
try:
    with conn:
        # Delete child tables first
        for table in reversed(table_order):
            conn.execute(f"DELETE FROM {table}")

        # Insert parent tables first
        for table in table_order:
            df = dataframes[table]

            columns = list(df.columns)
            column_sql = ", ".join(
                f'"{col}"' for col in columns
            )
            placeholders = ", ".join(
                ["?"] * len(columns)
            )

            sql = (
                f'INSERT INTO "{table}" '
                f'({column_sql}) VALUES ({placeholders})'
            )

            records = [
                tuple(
                    None if pd.isna(value) else value
                    for value in row
                )
                for row in df.itertuples(
                    index=False, name=None
                )
            ]

            conn.executemany(sql, records)

            print(
                f"Imported {len(df):,} rows into {table}"
            )

    print("\nDatabase import completed successfully!")

except Exception as error:
    print("\nDatabase import failed:", error)
    raise


print("\nDatabase Row Counts:")

for table in table_order:
    count = conn.execute(
        f"SELECT COUNT(*) FROM {table}"
    ).fetchone()[0]

    print(f"{table}: {count:,}")

# Check foreign key integrity
foreign_key_errors = conn.execute(
    "PRAGMA foreign_key_check;"
).fetchall()

print(
    "\nForeign key violations:",
    len(foreign_key_errors)
)

conn.close()
print("\nDatabase connection closed.")