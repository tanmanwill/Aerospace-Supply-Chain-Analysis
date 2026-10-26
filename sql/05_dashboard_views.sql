-- Supplier Performance Dashboard View --
-- Reporting cutoff: September 30, 2026 --
DROP VIEW IF EXISTS vw_supplier_performance;
CREATE VIEW vw_supplier_performance AS
SELECT
    s.SupplierID,
    s.SupplierName,
    s.SupplierCategory,
    s.Location,
    s.ReliabilityRating,

    COUNT(sh.ShipmentID) AS TotalShipments,

    SUM(
        CASE
            WHEN sh.ActualDeliveryDate <= po.ExpectedDeliveryDate
            THEN 1
            ELSE 0
        END
    ) AS OnTimeShipments,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN sh.ActualDeliveryDate <= po.ExpectedDeliveryDate
                THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(sh.ShipmentID), 0),
        2
    ) AS OnTimeDeliveryRate,

    SUM(sh.QuantityReceived) AS TotalUnitsReceived,
    SUM(sh.DefectiveUnits) AS TotalDefectiveUnits,
    ROUND(
        100.0 * SUM(sh.DefectiveUnits)
        / NULLIF(SUM(sh.QuantityReceived), 0),
        2
    ) AS DefectRate

FROM suppliers s

LEFT JOIN purchase_orders po
    ON s.SupplierID = po.SupplierID

LEFT JOIN shipments sh
    ON po.OrderID = sh.OrderID
    AND sh.ActualDeliveryDate <= '2026-09-30'

GROUP BY
    s.SupplierID,
    s.SupplierName,
    s.SupplierCategory,
    s.Location,
    s.ReliabilityRating;

-- Verify supplier performance view --
SELECT *
FROM vw_supplier_performance
ORDER BY OnTimeDeliveryRate ASC
LIMIT 10;



-- Supplier Risk Dashboard View --
DROP VIEW IF EXISTS vw_supplier_risk;
CREATE VIEW vw_supplier_risk AS
SELECT
    SupplierID,
    SupplierName,
    SupplierCategory,
    Location,
    ReliabilityRating,
    TotalShipments,
    OnTimeShipments,
    OnTimeDeliveryRate,
    TotalUnitsReceived,
    TotalDefectiveUnits,
    DefectRate,

    CASE
        WHEN OnTimeDeliveryRate < 70
             AND DefectRate > 30
            THEN 'High Risk'

        WHEN OnTimeDeliveryRate < 80
             OR DefectRate > 20
            THEN 'Moderate Risk'

        ELSE 'Low Risk'
    END AS RiskCategory
FROM vw_supplier_performance;

-- Verify Supplier Risk Classification --
SELECT
    RiskCategory,
    COUNT(*) AS SupplierCount,

    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM vw_supplier_risk),
        2
    ) AS PercentageOfSuppliers

FROM vw_supplier_risk
GROUP BY RiskCategory

ORDER BY
    CASE RiskCategory
        WHEN 'High Risk' THEN 1
        WHEN 'Moderate Risk' THEN 2
        WHEN 'Low Risk' THEN 3
    END;



-- Inventory Valuation Dashboard View --
DROP VIEW IF EXISTS vw_inventory_valuation;
CREATE VIEW vw_inventory_valuation AS
SELECT
    c.ComponentID,
    c.ComponentName,
    c.Category,

    c.SupplierID,
    s.SupplierName,

    c.UnitCost,
    c.CurrentStock,
    c.SafetyStock,
    c.LeadTimeDays,

    ROUND(c.CurrentStock * c.UnitCost, 2) AS InventoryValue,

    c.CurrentStock - c.SafetyStock
        AS StockAboveSafetyStock,

    CASE
        WHEN c.CurrentStock < c.SafetyStock
            THEN 'Below Safety Stock'

        WHEN c.CurrentStock = c.SafetyStock
            THEN 'At Safety Stock'

        ELSE 'Above Safety Stock'
    END AS SafetyStockStatus
FROM components c
LEFT JOIN suppliers s
    ON c.SupplierID = s.SupplierID;

-- Verify Inventory Valuation --
SELECT
    COUNT(*) AS TotalComponents,

    SUM(CurrentStock) AS TotalUnitsInStock,

    ROUND(
        SUM(InventoryValue),
        2
    ) AS TotalInventoryValue,

    SUM(
        CASE
            WHEN SafetyStockStatus = 'Below Safety Stock'
            THEN 1
            ELSE 0
        END
    ) AS ComponentsBelowSafetyStock,

    SUM(
        CASE
            WHEN SafetyStockStatus = 'Above Safety Stock'
            THEN 1
            ELSE 0
        END
    ) AS ComponentsAboveSafetyStock
FROM vw_inventory_valuation;



-- Excess Inventory Dashboard View --
-- Historical usage: January 2024 - September 2026 --
DROP VIEW IF EXISTS vw_excess_inventory;
CREATE VIEW vw_excess_inventory AS
WITH ComponentUsage AS (
    SELECT
        ComponentID,
        SUM(Quantity) AS TotalUnitsUsed
    FROM inventory_movements
    WHERE MovementType = 'Usage'
      AND MovementDate BETWEEN '2024-01-01'
                           AND '2026-09-30'
    GROUP BY ComponentID
),

DemandCalculations AS (
    SELECT
        c.ComponentID,
        c.ComponentName,
        c.Category,
        c.SupplierID,
        c.UnitCost,
        c.CurrentStock,
        c.SafetyStock,
        c.LeadTimeDays,

        COALESCE(u.TotalUnitsUsed, 0)
            AS TotalUnitsUsed,

        COALESCE(u.TotalUnitsUsed, 0) / 1004.0
            AS AverageDailyDemand

    FROM components c

    LEFT JOIN ComponentUsage u
        ON c.ComponentID = u.ComponentID
),

InventoryTargets AS (
    SELECT
        *,

        CAST(
            AverageDailyDemand * LeadTimeDays * 2
            + SafetyStock
            + 0.999999999
            AS INTEGER
        ) AS TargetStock

    FROM DemandCalculations
),

ExcessCalculations AS (
    SELECT
        *,

        CASE
            WHEN CurrentStock > TargetStock
                THEN CurrentStock - TargetStock
            ELSE 0
        END AS ExcessUnits

    FROM InventoryTargets
)

SELECT
    ComponentID,
    ComponentName,
    Category,
    SupplierID,
    UnitCost,
    CurrentStock,
    SafetyStock,
    LeadTimeDays,
    TotalUnitsUsed,

    ROUND(AverageDailyDemand, 4)
        AS AverageDailyDemand,

    TargetStock,
    ExcessUnits,

    ROUND(
        CurrentStock * UnitCost,
        2
    ) AS InventoryValue,

    ROUND(
        ExcessUnits * UnitCost,
        2
    ) AS PotentialExcessValue,

    CASE
        WHEN ExcessUnits > 0
            THEN 'Above Target'
        ELSE 'At or Below Target'
    END AS InventoryTargetStatus
FROM ExcessCalculations;

-- Verify Excess Inventory Dashboard View --
SELECT
    COUNT(*) AS TotalComponents,

    SUM(
        CASE
            WHEN InventoryTargetStatus = 'Above Target'
            THEN 1
            ELSE 0
        END
    ) AS ComponentsAboveTarget,

    SUM(ExcessUnits) AS TotalExcessUnits,

    ROUND(
        SUM(PotentialExcessValue),
        2
    ) AS TotalPotentialExcessValue,

    ROUND(
        SUM(InventoryValue),
        2
    ) AS TotalInventoryValue,

    ROUND(
        100.0 * SUM(PotentialExcessValue)
        / NULLIF(SUM(InventoryValue), 0),
        2
    ) AS PercentageOfInventoryValueAboveTarget
FROM vw_excess_inventory;



-- Procurement Dashboard View --
DROP VIEW IF EXISTS vw_procurement;
CREATE VIEW vw_procurement AS
SELECT
    po.OrderID,
    po.OrderDate,

    strftime('%Y', po.OrderDate) AS OrderYear,
    strftime('%Y-%m', po.OrderDate) AS OrderMonth,

    po.SupplierID,
    s.SupplierName,

    po.ComponentID,
    c.ComponentName,
    c.Category,

    po.QuantityOrdered,
    po.UnitPrice,
    po.TotalCost,
    po.ExpectedDeliveryDate

FROM purchase_orders po
LEFT JOIN suppliers s
    ON po.SupplierID = s.SupplierID

LEFT JOIN components c
    ON po.ComponentID = c.ComponentID

WHERE po.OrderDate <= '2026-09-30';

-- Verify Procurement Dashboard View --
SELECT
    COUNT(*) AS TotalPurchaseOrders,

    SUM(QuantityOrdered) AS TotalUnitsOrdered,

    ROUND(
        SUM(TotalCost),
        2
    ) AS TotalProcurementSpend,

    ROUND(
        AVG(TotalCost),
        2
    ) AS AverageOrderValue,

    COUNT(DISTINCT SupplierID)
        AS SuppliersWithOrders
FROM vw_procurement;



-- Component Demand Forecast Dashboard View --
-- Forecast period: October 2026 --
-- Historical period: April–September 2026 --
DROP VIEW IF EXISTS vw_demand_forecast;
CREATE VIEW vw_demand_forecast AS
WITH ComponentUsage AS (
    SELECT
        ComponentID,
        SUM(Quantity) AS UnitsConsumedLast6Months
    FROM inventory_movements
    WHERE MovementType = 'Usage'
      AND MovementDate BETWEEN '2026-04-01'
                           AND '2026-09-30'
    GROUP BY ComponentID
),

DemandCalculations AS (
    SELECT
        c.ComponentID,
        c.ComponentName,
        c.Category,
        c.SupplierID,
        c.CurrentStock,
        c.SafetyStock,
        c.LeadTimeDays,

        COALESCE(u.UnitsConsumedLast6Months, 0)
            AS UnitsConsumedLast6Months,

        COALESCE(u.UnitsConsumedLast6Months, 0) / 6.0
            AS MonthlyDemand,

        COALESCE(u.UnitsConsumedLast6Months, 0) / 180.0
            AS DailyDemand

    FROM components c

    LEFT JOIN ComponentUsage u
        ON c.ComponentID = u.ComponentID
),

ReorderCalculations AS (
    SELECT
        *,

        CAST(
            DailyDemand * LeadTimeDays
            + SafetyStock
            + 0.999999999
            AS INTEGER
        ) AS ReorderPoint

    FROM DemandCalculations
)

SELECT
    ComponentID,
    ComponentName,
    Category,
    SupplierID,
    CurrentStock,
    SafetyStock,
    LeadTimeDays,
    UnitsConsumedLast6Months,

    ROUND(MonthlyDemand, 2)
        AS ForecastedMonthlyDemand,

    ReorderPoint,

    CurrentStock - ReorderPoint
        AS StockAboveReorderPoint,

    CASE
        WHEN CurrentStock <= ReorderPoint
            THEN 'Reorder Review'

        WHEN CurrentStock < ReorderPoint * 2
            THEN 'Monitor Inventory'

        ELSE 'Defer Replenishment Review'
    END AS ReplenishmentRecommendation
FROM ReorderCalculations;

-- Verify Demand Forecast View --
SELECT
    COUNT(*) AS TotalComponents,

    ROUND(
        SUM(ForecastedMonthlyDemand),
        2
    ) AS TotalForecastedMonthlyDemand,

    SUM(
        CASE
            WHEN ReplenishmentRecommendation =
                 'Reorder Review'
            THEN 1
            ELSE 0
        END
    ) AS ComponentsRequiringReorderReview,

    SUM(
        CASE
            WHEN ReplenishmentRecommendation =
                 'Monitor Inventory'
            THEN 1
            ELSE 0
        END
    ) AS ComponentsToMonitor,

    SUM(
        CASE
            WHEN ReplenishmentRecommendation =
                 'Defer Replenishment Review'
            THEN 1
            ELSE 0
        END
    ) AS ComponentsToDefer
FROM vw_demand_forecast;