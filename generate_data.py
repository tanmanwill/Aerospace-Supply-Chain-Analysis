from pathlib import Path
import pandas as pd
import numpy as np

# Project Paths
BASE_DIR = Path(__file__).resolve().parent
RAW_DIR = BASE_DIR / "data" / "raw"
RAW_DIR.mkdir(parents=True, exist_ok=True)

# Make generated data reproducible
rng = np.random.default_rng(42)

# Supplier Information
categories = ["Electronics", "Propulsion", "Structural", "Sensors", "Communications", "Thermal Control", "Power Systems"]
locations = ["Houston, TX", "Austin, TX", "Dallas, TX", "Los Angeles, CA", "Seattle, WA", "Denver, CO", "Phoenix, AZ", "Hunstville, AL"]

suppliers = []

for i in range(1, 41):
    supplier = {
        "SupplierID": f"SUP{i:03d}",
        "SupplierName": f"Aerospace Supplier {i:02d}",
        "Location": rng.choice(locations),
        "SupplierCategory": rng.choice(categories),
        "ReliabilityRating": round(float(rng.uniform(65, 99)), 2)
    }
    suppliers.append(supplier)
suppliers_df = pd.DataFrame(suppliers)

# Export Dataset
output_path = RAW_DIR / "suppliers.csv"
suppliers_df.to_csv(output_path, index=False)

print("Suppliers dataset generated successfully")
print(f"Total suppliers: {len(suppliers_df)}")
print(f"Saved to: {output_path}")

print("\nFirst 5 record:")
print(suppliers_df.head())


# ----- Generate Aerospace Components Dataset -----

components = []

# Define cost ranges by component category
cost_ranges = {
    "Electronics": (50, 1500),
    "Propulsion": (500, 10000),
    "Structural": (100, 3500),
    "Sensors": (200, 5000),
    "Communications": (300, 7000),
    "Thermal Control": (150, 4000),
    "Power Systems": (250, 6000)
}

# Create supplier groups by category
supplier_groups = {
    category: suppliers_df.loc[
        suppliers_df["SupplierCategory"] == category, "SupplierID"
    ].tolist()
    for category in categories
}

# Generate 500 components
for i in range(1, 501):
    category = str(rng.choice(categories))

    # Assign a supplier from the corresponding category
    available_suppliers = supplier_groups[category]

    # Handle categories with no suppliers
    if not available_suppliers:
        available_suppliers = suppliers_df["SupplierID"].tolist()

    supplier_id = str(rng.choice(available_suppliers))
    min_cost, max_cost = cost_ranges[category]

    unit_cost = round(float(rng.uniform(min_cost, max_cost)), 2)

    safety_stock = int(rng.integers(20, 101))
    current_stock = int(rng.integers(0, 501))
    lead_time = int(rng.integers(5, 46))

    component = {
        "ComponentID": f"CMP{i:04d}",
        "ComponentName": f"{category} Component {i:04d}",
        "Category": category,
        "UnitCost": unit_cost,
        "CurrentStock": current_stock,
        "SafetyStock": safety_stock,
        "LeadTimeDays": lead_time,
        "SupplierID": supplier_id
    }

    components.append(component)

components_df = pd.DataFrame(components)

# Export components dataset
components_path = RAW_DIR / "components.csv"

components_df.to_csv(components_path, index=False)

print("\nComponents dataset generated successfully")
print(f"Total components: {len(components_df)}")
print(f"Saved to: {components_path}")

print("\nFirst 5 records:")
print(components_df.head())



# ----- Generate Purchase Orders Dataset -----
purchase_orders = []

# Historical purchasing period
start_date = pd.Timestamp("2024-01-01")
end_date = pd.Timestamp("2026-09-30")

total_days = (end_date - start_date).days + 1

# Create purchase orders
for i in range(1, 10001):

    # Select a component
    component = components_df.iloc[int(rng.integers(0, len(components_df)))]

    component_id = component["ComponentID"]
    supplier_id = component["SupplierID"]

    # Generate an order date
    days_offset = int(rng.integers(0, total_days))
    order_date = start_date + pd.Timedelta(days=days_offset)

    # Generate a quantity ordered
    quantity = int(rng.integers(10, 201))

    # Introduce price fluctuations
    base_price = float(component["UnitCost"])
    price_multiplier = float(rng.uniform(0.90, 1.15))
    unit_price = round(base_price * price_multiplier, 2)
    total_cost = round(quantity * unit_price, 2)

    # Expected supplier lead time
    lead_time = int(component["LeadTimeDays"])
    expected_delivery = order_date + pd.Timedelta(days=lead_time)

    purchase_order = {
        "OrderId": f"PO{i:05d}",
        "SupplierId": supplier_id,
        "ComponentId": component_id,
        "OrderDate": order_date.date(),
        "Quantity": quantity,
        "UnitPrice": unit_price,
        "TotalCost": total_cost,
        "ExpectedDeliveryDate": expected_delivery.date()
    }

    purchase_orders.append(purchase_order)
purchase_orders_df = pd.DataFrame(purchase_orders)

# Standardize purchase order column names
purchase_orders_df = purchase_orders_df.rename(
    columns={
        "OrderId": "OrderID",
        "SupplierId": "SupplierID",
        "ComponentId": "ComponentID",
        "Quantity": "QuantityOrdered"
    }
)

# Export purchase orders dataset
purchase_orders_path = RAW_DIR / "purchase_orders.csv"
purchase_orders_df.to_csv(purchase_orders_path, index=False)

print("\nPurchase Orders dataset generated successfully")
print(f"Total purchase orders: {len(purchase_orders_df)}")
print(f"Saved to: {purchase_orders_path}")

print("\nFirst 5 records:")
print(purchase_orders_df.head())

# Check 1: Every purchase order has a valid component
invalid_components = ~purchase_orders_df["ComponentID"].isin(
    components_df["ComponentID"]
)

# Check 2: Every purchase order has a valid supplier
invalid_suppliers_po = ~purchase_orders_df["SupplierID"].isin(
    suppliers_df["SupplierID"]
)

# Check 3: Total cost matches quantity × unit price
calculated_total = (
    purchase_orders_df["QuantityOrdered"]
    * purchase_orders_df["UnitPrice"]
).round(2)

cost_mismatches = (
    calculated_total != purchase_orders_df["TotalCost"]
)

print("\nPurchase Order Validation:")
print("Invalid components:", invalid_components.sum())
print("Invalid suppliers:", invalid_suppliers_po.sum())
print("Cost mismatches:", cost_mismatches.sum())


# ----- Generate Shipment Records Dataset -----
shipments = []

# Supplier-specific performance characteristics
supplier_performance = {}

for supplier_id in suppliers_df["SupplierID"]:
    supplier_performance[supplier_id] = {
        "delay_profitability": float(rng.uniform(0.10, 0.45)),
        "defect_profitability": float(rng.uniform(0.005, 0.5)),
    }

# Generate one shipment per purchase order
for i, order in purchase_orders_df.iterrows():
    supplier_id = order["SupplierID"]
    order_id = order["OrderID"]
    quantity = int(order["QuantityOrdered"])
    order_cost = float(order["TotalCost"])
    expected_date = pd.Timestamp(order["ExpectedDeliveryDate"])
    performance = supplier_performance[supplier_id]

    # Determine whether the shipment is delayed
    is_late = rng.random() < performance["delay_profitability"]

    if is_late:
        delay_days = int(rng.integers(1, 16))
    else:
        delay_days  = int(rng.integers(-5, 1))

    actual_date = expected_date + pd.Timedelta(days=delay_days)

    # Calculate shipping costs
    shipping_rate = float(rng.uniform(0.01, 0.05))
    shipping_cost = round(order_cost * shipping_rate, 2)

    # Generate defective units
    defective_units = int(rng.binomial(quantity, performance["defect_profitability"]))

    # Determine delivery status
    if delay_days > 0:
        delivery_status = "Late"
    elif delay_days < 0:
        delivery_status = "Early"
    else:
        delivery_status = "On Time"

    shipment = {
        "ShipmentID": f"SHP{i+1:05d}",
        "OrderID": order_id,
        "ActualDeliveryDate": actual_date.date(),
        "QuantityReceived": quantity,
        "ShippingCost": shipping_cost,
        "DefectiveUnits": defective_units,
        "DeliveryStatus": delivery_status
    }
    shipments.append(shipment)
shipments_df = pd.DataFrame(shipments)

# Export shipment records dataset
shipments_path = RAW_DIR / "shipments.csv"
shipments_df.to_csv(shipments_path, index=False)

print("\nShipment Records dataset generated successfully")
print(f"Total shipments: {len(shipments_df)}")
print(f"Saved to: {shipments_path}")

print("\nFirst 5 records:")
print(shipments_df.head())



# ----- Generate Inventory Movement Records -----
REPORTING_DATE = pd.Timestamp("2026-09-30")
inventory_movements = []

# Create a chronological list of receipt events.
# Only deliveries received by the reporting date
# can affect inventory.

receipts_df = shipments_df.merge(
    purchase_orders_df[
        ["OrderID", "ComponentID"]
    ],
    on="OrderID",
    how="inner",
    validate="one_to_one"
)

receipts_df["MovementDate"] = pd.to_datetime(
    receipts_df["ActualDeliveryDate"]
)

receipts_df = receipts_df[
    receipts_df["MovementDate"] <= REPORTING_DATE
].copy()

receipts_df["AcceptedQuantity"] = (
    receipts_df["QuantityReceived"]
    - receipts_df["DefectiveUnits"]
)

# Establish opening balances and generate usage events.
# These are synthetic starting assumptions.

events = []
for _, component in components_df.iterrows():

    component_id = component["ComponentID"]

    opening_stock = int(rng.integers(100, 501))

    events.append({
        "ComponentID": component_id,
        "MovementDate": pd.Timestamp("2024-01-01"),
        "MovementType": "Opening Balance",
        "Quantity": opening_stock,
        "OrderID": None
    })

# Add accepted shipment receipts
for _, receipt in receipts_df.iterrows():

    events.append({
        "ComponentID": receipt["ComponentID"],
        "MovementDate": receipt["MovementDate"],
        "MovementType": "Receipt",
        "Quantity": int(receipt["AcceptedQuantity"]),
        "OrderID": receipt["OrderID"]
    })

# Generate synthetic component usage
# 9,000 usage events spread across the period

start_date = pd.Timestamp("2024-01-02")
total_days = (REPORTING_DATE - start_date).days + 1

for _ in range(9000):

    component_id = str(
        rng.choice(components_df["ComponentID"].to_numpy())
    )

    movement_date = start_date + pd.Timedelta(
        days=int(rng.integers(0, total_days))
    )

    usage_quantity = int(rng.integers(1, 41))

    events.append({
        "ComponentID": component_id,
        "MovementDate": movement_date,
        "MovementType": "Usage",
        "Quantity": usage_quantity,
        "OrderID": None
    })

# Sort by component, date and movement priority
# Opening balances and receipts occur before usage
# on the same day.

priority = {
    "Opening Balance": 0,
    "Receipt": 1,
    "Usage": 2
}

events_df = pd.DataFrame(events)

events_df["Priority"] = (
    events_df["MovementType"].map(priority)
)

events_df = events_df.sort_values(
    ["ComponentID", "MovementDate", "Priority"],
    kind="stable"
).reset_index(drop=True)

# Calculate running stock balances.
# Usage cannot exceed available stock.

stock_balances = {}
movement_records = []

for _, event in events_df.iterrows():

    component_id = event["ComponentID"]
    movement_type = event["MovementType"]
    quantity = int(event["Quantity"])

    current_balance = stock_balances.get(
        component_id, 0
    )

    if movement_type == "Usage":
        quantity = min(quantity, current_balance)
        new_balance = current_balance - quantity
    else:
        new_balance = current_balance + quantity

    stock_balances[component_id] = new_balance

    movement_records.append({
        "ComponentID": component_id,
        "MovementDate": event["MovementDate"].date(),
        "MovementType": movement_type,
        "Quantity": quantity,
        "OrderID": event["OrderID"],
        "StockAfterMovement": new_balance
    })

inventory_movements_df = pd.DataFrame(
    movement_records
)

inventory_movements_df.insert(
    0,
    "MovementID",
    [
        f"MOV{i:05d}"
        for i in range(
            1, len(inventory_movements_df) + 1
        )
    ]
)

# Export the dataset
inventory_path = RAW_DIR / "inventory_movements.csv"

inventory_movements_df.to_csv(
    inventory_path,
    index=False
)

print("\nInventory Movements generated successfully!")
print(
    "Total movements:",
    len(inventory_movements_df)
)
print(f"Saved to: {inventory_path}")

print("\nFirst 5 inventory movements:")
print(inventory_movements_df.head())


# ----------------------------------------
# Inventory Validation
# ----------------------------------------

negative_stock = (
    inventory_movements_df["StockAfterMovement"] < 0
).sum()

invalid_components = (
    ~inventory_movements_df["ComponentID"].isin(
        components_df["ComponentID"]
    )
).sum()

receipt_movements = inventory_movements_df[
    inventory_movements_df["MovementType"] == "Receipt"
]

receipt_mismatches = (
    receipt_movements["Quantity"].sum()
    != receipts_df["AcceptedQuantity"].sum()
)

# Reconcile ending stock with opening balances,
# receipts and actual usage.

signed_movements = inventory_movements_df.copy()

signed_movements["SignedQuantity"] = np.where(
    signed_movements["MovementType"] == "Usage",
    -signed_movements["Quantity"],
    signed_movements["Quantity"]
)

calculated_balances = signed_movements.groupby(
    "ComponentID"
)["SignedQuantity"].sum()

recorded_balances = (
    inventory_movements_df.groupby("ComponentID")[
        "StockAfterMovement"
    ].last()
)

balance_mismatches = (
    calculated_balances != recorded_balances
).sum()

print("\nInventory Validation:")
print("Negative stock records:", negative_stock)
print("Invalid components:", invalid_components)
print("Receipt quantity mismatch:", receipt_mismatches)
print("Balance mismatches:", balance_mismatches)