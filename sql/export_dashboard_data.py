import sqlite3
from pathlib import Path
import pandas as pd

# Locate the project directory
PROJECT_DIR = Path(__file__).resolve().parent.parent

# Database and export paths
DB_PATH = PROJECT_DIR / "aerospace_supply_chain.db"
OUTPUT_DIR = PROJECT_DIR / "data" / "cleaned" / "dashboard_exports"

# Create output directory if needed
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Views to export
views = [
    "vw_supplier_performance",
    "vw_supplier_risk",
    "vw_inventory_valuation",
    "vw_excess_inventory",
    "vw_procurement",
    "vw_demand_forecast",
]

if not DB_PATH.is_file():
    raise FileNotFoundError(
        f"Database not found: {DB_PATH}"
    )

# Connect to SQLite
with sqlite3.connect(DB_PATH) as conn:
    for view in views:
        query = f"SELECT * FROM {view}"
        df = pd.read_sql_query(query, conn)
        output_file = OUTPUT_DIR / f"{view}.csv"
        df.to_csv(output_file, index=False)
        print(
            f"Exported {view}: "
            f"{len(df):,} rows"
        )
print("\nAll dashboard exports completed!")
