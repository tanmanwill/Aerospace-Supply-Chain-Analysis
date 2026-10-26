-- Inventory Safety Stock Analysis --
-- Stock snapshot as of September 30, 2026 --
SELECT
    ComponentID,
    ComponentName,
    Category,
    CurrentStock,
    SafetyStock,
    LeadTimeDays,
    UnitCost,

    (CurrentStock - SafetyStock) AS StockSurplus,

    CASE
        WHEN CurrentStock = 0
        THEN 'Out of Stock'

        WHEN CurrentStock < SafetyStock
        THEN 'Below Safety Stock'

        WHEN CurrentStock = SafetyStock
        THEN 'At Safety Stock'

        ELSE 'Above Safety Stock'
    END AS InventoryStatus

FROM components

ORDER BY
    CASE
        WHEN CurrentStock = 0 THEN 1
        WHEN CurrentStock < SafetyStock THEN 2
        WHEN CurrentStock = SafetyStock THEN 3
        ELSE 4
    END,
    StockSurplus ASC;



-- Inventory Status Summary --
SELECT
    CASE
        WHEN CurrentStock = 0
        THEN 'Out of Stock'

        WHEN CurrentStock < SafetyStock
        THEN 'Below Safety Stock'

        WHEN CurrentStock = SafetyStock
        THEN 'At Safety Stock'

        ELSE 'Above Safety Stock'
    END AS InventoryStatus,

    COUNT(*) AS ComponentCount,

    ROUND(
        100.0 * COUNT(*) /
        (SELECT COUNT(*) FROM components),
        2
    ) AS PercentageOfComponents

FROM components

GROUP BY InventoryStatus

ORDER BY ComponentCount DESC;



-- Total Inventory Value --
SELECT
    COUNT(*) AS TotalComponents,

    SUM(CurrentStock) AS TotalUnitsInStock,

    ROUND(
        SUM(CurrentStock * UnitCost),
        2
    ) AS TotalInventoryValue,

    ROUND(
        AVG(CurrentStock),
        2
    ) AS AverageStockPerComponent

FROM components;



-- Inventory Value by Category --
SELECT
    Category,

    COUNT(*) AS ComponentCount,

    SUM(CurrentStock) AS TotalUnitsInStock,

    ROUND(
        SUM(CurrentStock * UnitCost),
        2
    ) AS InventoryValue,

    ROUND(
        100.0 * SUM(CurrentStock * UnitCost)
        / (
            SELECT SUM(CurrentStock * UnitCost)
            FROM components
        ),
        2
    ) AS PercentageOfTotalValue

FROM components

GROUP BY Category

ORDER BY InventoryValue DESC;



-- Average Daily Component Usage --
-- Analysis period: January 1, 2024 - September 30, 2026 --
SELECT
    c.ComponentID,
    c.ComponentName,
    c.Category,

    c.CurrentStock,
    c.SafetyStock,
    c.LeadTimeDays,

    COALESCE(
        SUM(
            CASE
                WHEN im.MovementType = 'Usage'
                THEN im.Quantity
                ELSE 0
            END
        ),
        0
    ) AS TotalUnitsUsed,

    ROUND(
        COALESCE(
            SUM(
                CASE
                    WHEN im.MovementType = 'Usage'
                    THEN im.Quantity
                    ELSE 0
                END
            ),
            0
        ) / 1004.0,
        2
    ) AS AverageDailyUsage

FROM components c

LEFT JOIN inventory_movements im
    ON c.ComponentID = im.ComponentID
    AND im.MovementDate >= '2024-01-01'
    AND im.MovementDate <= '2026-09-30'

GROUP BY
    c.ComponentID,
    c.ComponentName,
    c.Category,
    c.CurrentStock,
    c.SafetyStock,
    c.LeadTimeDays

ORDER BY AverageDailyUsage DESC;



-- Estimated Days of Supply --
WITH ComponentUsage AS (
    SELECT
        c.ComponentID,
        c.ComponentName,
        c.Category,
        c.CurrentStock,
        c.SafetyStock,
        c.LeadTimeDays,
        c.UnitCost,

        COALESCE(
            SUM(
                CASE
                    WHEN im.MovementType = 'Usage'
                    THEN im.Quantity
                    ELSE 0
                END
            ),
            0
        ) AS TotalUnitsUsed

    FROM components c

    LEFT JOIN inventory_movements im
        ON c.ComponentID = im.ComponentID
        AND im.MovementDate BETWEEN '2024-01-01'
                                AND '2026-09-30'

    GROUP BY c.ComponentID
),

InventoryCoverage AS (
    SELECT
        *,
        ROUND(TotalUnitsUsed / 1004.0, 2)
            AS AverageDailyUsage,

        CASE
            WHEN TotalUnitsUsed > 0
            THEN ROUND(
                CurrentStock / (TotalUnitsUsed / 1004.0),
                2
            )
            ELSE NULL
        END AS DaysOfSupply

    FROM ComponentUsage
)

SELECT
    ComponentID,
    ComponentName,
    Category,
    CurrentStock,
    SafetyStock,
    LeadTimeDays,
    AverageDailyUsage,
    DaysOfSupply,

    CASE
        WHEN DaysOfSupply IS NULL
        THEN 'No Recorded Usage'

        WHEN DaysOfSupply < LeadTimeDays
        THEN 'Potential Stockout Risk'

        WHEN DaysOfSupply > LeadTimeDays * 3
        THEN 'Potential Overstock'

        ELSE 'Adequate Coverage'
    END AS InventoryRisk

FROM InventoryCoverage

ORDER BY DaysOfSupply DESC;



-- Inventory Risk Summary --
WITH ComponentUsage AS (
    SELECT
        c.ComponentID,
        c.CurrentStock,
        c.LeadTimeDays,
        c.UnitCost,

        COALESCE(
            SUM(
                CASE
                    WHEN im.MovementType = 'Usage'
                    THEN im.Quantity
                    ELSE 0
                END
            ), 0
        ) AS TotalUnitsUsed

    FROM components c

    LEFT JOIN inventory_movements im
        ON c.ComponentID = im.ComponentID
        AND im.MovementDate BETWEEN '2024-01-01'
                                AND '2026-09-30'

    GROUP BY
        c.ComponentID,
        c.CurrentStock,
        c.LeadTimeDays,
        c.UnitCost
),

InventoryCoverage AS (
    SELECT
        *,
        CASE
            WHEN TotalUnitsUsed > 0
            THEN CurrentStock / (TotalUnitsUsed / 1004.0)
            ELSE NULL
        END AS DaysOfSupply

    FROM ComponentUsage
),

InventoryClassification AS (
    SELECT
        *,
        CASE
            WHEN DaysOfSupply IS NULL
            THEN 'No Recorded Usage'

            WHEN DaysOfSupply < LeadTimeDays
            THEN 'Potential Stockout Risk'

            WHEN DaysOfSupply > LeadTimeDays * 3
            THEN 'Potential Overstock'

            ELSE 'Adequate Coverage'
        END AS InventoryRisk

    FROM InventoryCoverage
)

SELECT
    InventoryRisk,

    COUNT(*) AS ComponentCount,

    ROUND(
        100.0 * COUNT(*) /
        (SELECT COUNT(*) FROM components),
        2
    ) AS PercentageOfComponents,

    ROUND(
        SUM(CurrentStock * UnitCost),
        2
    ) AS InventoryValue

FROM InventoryClassification

GROUP BY InventoryRisk

ORDER BY ComponentCount DESC;




-- Inventory Optimization Analysis --
WITH ComponentUsage AS (
    SELECT
        c.ComponentID,
        c.ComponentName,
        c.Category,
        c.CurrentStock,
        c.SafetyStock,
        c.LeadTimeDays,
        c.UnitCost,

        COALESCE(
            SUM(
                CASE
                    WHEN im.MovementType = 'Usage'
                    THEN im.Quantity
                    ELSE 0
                END
            ), 0
        ) AS TotalUnitsUsed

    FROM components c

    LEFT JOIN inventory_movements im
        ON c.ComponentID = im.ComponentID
        AND im.MovementDate BETWEEN '2024-01-01'
                                AND '2026-09-30'

    GROUP BY c.ComponentID
),

InventoryTargets AS (
    SELECT
        *,

        TotalUnitsUsed / 1004.0 AS AverageDailyUsage,

        CAST(
            (TotalUnitsUsed / 1004.0)
            * LeadTimeDays
            + SafetyStock + 0.999999999
            AS INTEGER
        ) AS ReorderPoint,

        CAST(
            (TotalUnitsUsed / 1004.0)
            * LeadTimeDays * 2
            + SafetyStock + 0.999999999
            AS INTEGER
        ) AS TargetStock

    FROM ComponentUsage
)

SELECT
    ComponentID,
    ComponentName,
    Category,
    CurrentStock,
    SafetyStock,
    LeadTimeDays,

    ROUND(AverageDailyUsage, 2) AS AverageDailyUsage,

    ReorderPoint,
    TargetStock,

    MAX(CurrentStock - TargetStock, 0)
        AS ExcessUnits,

    ROUND(
        MAX(CurrentStock - TargetStock, 0) * UnitCost,
        2
    ) AS PotentialExcessValue

FROM InventoryTargets

ORDER BY PotentialExcessValue DESC;



-- Potential Excess Inventory Summary --
WITH UsageData AS (
    SELECT
        c.ComponentID,
        c.CurrentStock,
        c.SafetyStock,
        c.LeadTimeDays,
        c.UnitCost,

        COALESCE(
            SUM(
                CASE
                    WHEN im.MovementType = 'Usage'
                    THEN im.Quantity
                    ELSE 0
                END
            ), 0
        ) AS TotalUnitsUsed

    FROM components c

    LEFT JOIN inventory_movements im
        ON c.ComponentID = im.ComponentID
        AND im.MovementDate BETWEEN '2024-01-01'
                                AND '2026-09-30'

    GROUP BY c.ComponentID
),

Targets AS (
    SELECT
        *,

        CAST(
            (TotalUnitsUsed / 1004.0)
            * LeadTimeDays * 2
            + SafetyStock + 0.999999999
            AS INTEGER
        ) AS TargetStock

    FROM UsageData
)

SELECT
    COUNT(*) AS TotalComponents,

    SUM(
        CASE
            WHEN CurrentStock > TargetStock
            THEN 1
            ELSE 0
        END
    ) AS ComponentsAboveTarget,

    SUM(
        MAX(CurrentStock - TargetStock, 0)
    ) AS TotalExcessUnits,

    ROUND(
        SUM(
            MAX(CurrentStock - TargetStock, 0)
            * UnitCost
        ),
        2
    ) AS PotentialExcessInventoryValue,

    ROUND(
        SUM(CurrentStock * UnitCost),
        2
    ) AS TotalInventoryValue

FROM Targets;



-- Potential Excess Inventory by Category --
WITH ComponentUsage AS (
    SELECT
        c.ComponentID,
        c.Category,
        c.CurrentStock,
        c.SafetyStock,
        c.LeadTimeDays,
        c.UnitCost,

        COALESCE(
            SUM(
                CASE
                    WHEN im.MovementType = 'Usage'
                    THEN im.Quantity
                    ELSE 0
                END
            ), 0
        ) AS TotalUnitsUsed

    FROM components c

    LEFT JOIN inventory_movements im
        ON c.ComponentID = im.ComponentID
        AND im.MovementDate BETWEEN '2024-01-01'
                                AND '2026-09-30'

    GROUP BY c.ComponentID
),

InventoryTargets AS (
    SELECT
        *,

        CAST(
            (TotalUnitsUsed / 1004.0)
            * LeadTimeDays * 2
            + SafetyStock + 0.999999999
            AS INTEGER
        ) AS TargetStock

    FROM ComponentUsage
),

ExcessInventory AS (
    SELECT
        *,
        MAX(CurrentStock - TargetStock, 0)
            AS ExcessUnits
    FROM InventoryTargets
)

SELECT
    Category,

    COUNT(*) AS ComponentCount,

    SUM(ExcessUnits) AS TotalExcessUnits,

    ROUND(
        SUM(ExcessUnits * UnitCost),
        2
    ) AS PotentialExcessValue,

    ROUND(
        100.0 * SUM(ExcessUnits * UnitCost)
        / (
            SELECT SUM(ExcessUnits * UnitCost)
            FROM ExcessInventory
        ),
        2
    ) AS PercentageOfTotalExcess

FROM ExcessInventory

GROUP BY Category

ORDER BY PotentialExcessValue DESC;
