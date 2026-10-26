-- Annual Procurement Spending --
-- Reporting cutoff: September 30, 2026 --
SELECT
    strftime('%Y', OrderDate) AS OrderYear,
    COUNT(*) AS TotalOrders,
    SUM(QuantityOrdered) AS TotalUnitsOrdered,
    ROUND(SUM(TotalCost), 2) AS TotalProcurementSpend,
    ROUND(AVG(TotalCost), 2) AS AverageOrderValue
FROM purchase_orders
WHERE OrderDate <= '2026-09-30'
GROUP BY strftime('%Y', OrderDate)
ORDER BY OrderYear;



-- Monthly Procurement Trends --
SELECT
    strftime('%Y-%m', OrderDate) AS OrderMonth,
    COUNT(*) AS TotalOrders,
    SUM(QuantityOrdered) AS TotalUnitsOrdered,
    ROUND(SUM(TotalCost), 2) AS MonthlyProcurementSpend,
    ROUND(AVG(TotalCost), 2) AS AverageOrderValue
FROM purchase_orders
WHERE OrderDate BETWEEN '2024-01-01' AND '2026-09-30'
GROUP BY strftime('%Y-%m', OrderDate)
ORDER BY OrderMonth;



-- Annual Procurement vs. Consumption
WITH AnnualPurchases AS (
    SELECT
        strftime('%Y', OrderDate) AS Year,
        SUM(QuantityOrdered) AS UnitsOrdered
    FROM purchase_orders
    WHERE OrderDate BETWEEN '2024-01-01' AND '2026-09-30'
    GROUP BY strftime('%Y', OrderDate)
),

AnnualUsage AS (
    SELECT
        strftime('%Y', MovementDate) AS Year,
        SUM(Quantity) AS UnitsConsumed
    FROM inventory_movements
    WHERE MovementType = 'Usage'
        AND MovementDate BETWEEN '2024-01-01' AND '2026-09-30'
    GROUP BY strftime('%Y', MovementDate)
)

SELECT
    p.Year,
    p.UnitsOrdered,
    COALESCE(u.UnitsConsumed, 0) AS UnitsConsumed,
    p.UnitsOrdered
        - COALESCE(u.UnitsConsumed, 0) AS PurchaseConsumptionGap,
    ROUND(1.0 * p.UnitsOrdered / NULLIF(u.UnitsConsumed, 0), 2) AS PurchaseToConsumptionRatio
FROM AnnualPurchases p 
LEFT JOIN AnnualUsage u ON p.Year = u.Year
ORDER BY p.Year;



-- Annual Inventory Receipts vs. Consumption --
-- Reporting cutoff: September 30, 2026 --
SELECT
    strftime('%Y', MovementDate) AS Year,
    SUM(
        CASE
            WHEN MovementType = 'Receipt'
            THEN Quantity
            ELSE 0
        END
    ) AS UnitsReceived,

    SUM(
        CASE
            WHEN MovementType = 'Usage'
            THEN Quantity
            ELSE 0
        END
    ) AS UnitsConsumed,

    SUM(
        CASE
            WHEN MovementType = 'Receipt'
            THEN Quantity
            WHEN MovementType = 'Usage'
            THEN -Quantity
            ELSE 0
        END
    ) AS NetInventoryChange,

    ROUND(
        1.0 * SUM(
            CASE
                WHEN MovementType = 'Receipt'
                THEN Quantity
                ELSE 0
            END
        )
        / NULLIF(
            SUM(
                CASE
                    WHEN MovementType = 'Usage'
                    THEN Quantity
                    ELSE 0
                END
            ), 0
        ), 2) AS ReceiptToConsumptionRatio
FROM inventory_movements
Where MovementDate BETWEEN '2024-01-01' AND '2026-09-30'
GROUP BY strftime('%Y', MovementDate)
ORDER BY Year;


-- Monthly Component Consumption --
SELECT
    strftime('%Y-%m', MovementDate) AS UsageMonth,
    COUNT(*) AS TotalUsageTransactions,
    SUM(Quantity) AS TotalUnitsConsumed,
    ROUND(AVG(Quantity), 2) AS AverageUnitsPerTransaction
FROM inventory_movements
WHERE MovementType = 'Usage'
    AND MovementDate BETWEEN '2024-01-01' AND '2026-09-30'
GROUP BY strftime('%Y-%m', MovementDate)
ORDER BY UsageMonth;



-- Historical 3-Month Moving Average --
-- Each forecast uses the previous 3 months. --
WITH MonthlyUsage AS (
    SELECT
        strftime('%Y-%m', MovementDate) AS UsageMonth,
        SUM(Quantity) AS UnitsConsumed
    FROM inventory_movements
    WHERE MovementType = 'Usage'
      AND MovementDate BETWEEN '2024-01-01' AND '2026-09-30'
    GROUP BY strftime('%Y-%m', MovementDate)
),

MovingAverage AS (
    SELECT
        UsageMonth,
        UnitsConsumed,
        ROUND(
            AVG(UnitsConsumed) OVER (
                ORDER BY UsageMonth
                ROWS BETWEEN 3 PRECEDING
                         AND 1 PRECEDING
            ),
            2
        ) AS ForecastedConsumption,

        COUNT(*) OVER (
            ORDER BY UsageMonth
            ROWS BETWEEN 3 PRECEDING
                     AND 1 PRECEDING
        ) AS MonthsUsed
    FROM MonthlyUsage
)

SELECT
    UsageMonth,
    UnitsConsumed,
    ForecastedConsumption,
    ROUND(ABS(UnitsConsumed - ForecastedConsumption), 2) AS AbsoluteForecastError
FROM MovingAverage
WHERE MonthsUsed = 3
ORDER BY UsageMonth;



-- Evaluate Forecast Accuracy --
-- 3-Month Moving Average --
WITH MonthlyUsage AS (
    SELECT
        strftime('%Y-%m', MovementDate) AS UsageMonth,
        SUM(Quantity) AS UnitsConsumed
    FROM inventory_movements
    WHERE MovementType = 'Usage'
      AND MovementDate BETWEEN '2024-01-01' AND '2026-09-30'
    GROUP BY strftime('%Y-%m', MovementDate)
),

MovingAverage AS (
    SELECT
        UsageMonth,
        UnitsConsumed,

        AVG(UnitsConsumed) OVER (
            ORDER BY UsageMonth
            ROWS BETWEEN 3 PRECEDING
                     AND 1 PRECEDING
        ) AS ForecastedConsumption,

        COUNT(*) OVER (
            ORDER BY UsageMonth
            ROWS BETWEEN 3 PRECEDING
                     AND 1 PRECEDING
        ) AS MonthsUsed
    FROM MonthlyUsage
),

ForecastErrors AS (
    SELECT
        UsageMonth,
        UnitsConsumed,
        ForecastedConsumption,
        ABS(
            UnitsConsumed - ForecastedConsumption
        ) AS AbsoluteError,

        100.0 * ABS(
            UnitsConsumed - ForecastedConsumption
        ) / NULLIF(UnitsConsumed, 0)
          AS AbsolutePercentageError

    FROM MovingAverage
    WHERE MonthsUsed = 3
)

SELECT
    COUNT(*) AS MonthsEvaluated,

    ROUND(AVG(AbsoluteError), 2)
        AS MeanAbsoluteError,

    ROUND(AVG(AbsolutePercentageError), 2)
        AS MeanAbsolutePercentageError,

    ROUND(MAX(AbsoluteError), 2)
        AS MaximumForecastError
FROM ForecastErrors;



-- Compare Forecasting Models --
-- 3-Month vs. 6-Month Moving Average --
WITH MonthlyUsage AS (
    SELECT
        strftime('%Y-%m', MovementDate) AS UsageMonth,
        SUM(Quantity) AS UnitsConsumed
    FROM inventory_movements
    WHERE MovementType = 'Usage'
      AND MovementDate BETWEEN '2024-01-01'
                           AND '2026-09-30'
    GROUP BY strftime('%Y-%m', MovementDate)
),

Forecasts AS (
    SELECT
        UsageMonth,
        UnitsConsumed,

        AVG(UnitsConsumed) OVER (
            ORDER BY UsageMonth
            ROWS BETWEEN 3 PRECEDING
                     AND 1 PRECEDING
        ) AS Forecast3Month,

        AVG(UnitsConsumed) OVER (
            ORDER BY UsageMonth
            ROWS BETWEEN 6 PRECEDING
                     AND 1 PRECEDING
        ) AS Forecast6Month,

        COUNT(*) OVER (
            ORDER BY UsageMonth
            ROWS BETWEEN 6 PRECEDING
                     AND 1 PRECEDING
        ) AS MonthsAvailable
    FROM MonthlyUsage
),

Errors AS (
    SELECT
        UnitsConsumed,
        ABS(UnitsConsumed - Forecast3Month)
            AS Error3Month,

        ABS(UnitsConsumed - Forecast6Month)
            AS Error6Month
    FROM Forecasts
    WHERE MonthsAvailable = 6
)

SELECT
    '3-Month Moving Average' AS ForecastModel,
    COUNT(*) AS MonthsEvaluated,
    ROUND(AVG(Error3Month), 2) AS MAE,
    ROUND(
        AVG(
            100.0 * Error3Month
            / NULLIF(UnitsConsumed, 0)
        ),
        2
    ) AS MAPE
FROM Errors

UNION ALL

SELECT
    '6-Month Moving Average' AS ForecastModel,
    COUNT(*) AS MonthsEvaluated,
    ROUND(AVG(Error6Month), 2) AS MAE,
    ROUND(
        AVG(
            100.0 * Error6Month
            / NULLIF(UnitsConsumed, 0)
        ),
        2
    ) AS MAPE
FROM Errors;



-- October 2026 Demand Forecast --
-- Selected Model: 6-Month Moving Average --
WITH MonthlyUsage AS (
    SELECT
        strftime('%Y-%m', MovementDate) AS UsageMonth,
        SUM(Quantity) AS UnitsConsumed
    FROM inventory_movements
    WHERE MovementType = 'Usage'
      AND MovementDate BETWEEN '2024-01-01'
                           AND '2026-09-30'
    GROUP BY strftime('%Y-%m', MovementDate)
),

RecentUsage AS (
    SELECT
        UsageMonth,
        UnitsConsumed
    FROM MonthlyUsage
    ORDER BY UsageMonth DESC
    LIMIT 6
)

SELECT
    '2026-10' AS ForecastMonth,

    COUNT(*) AS MonthsUsed,

    SUM(UnitsConsumed) AS TotalRecentConsumption,

    ROUND(AVG(UnitsConsumed), 2)
        AS ForecastedUnits,

    CAST(AVG(UnitsConsumed) + 0.999999999 AS INTEGER)
        AS RoundedForecastUnits
FROM RecentUsage;



-- Component-Level Demand Forecast --
-- Forecast month: October 2026 --
-- Historical period: April–September 2026 --
WITH ComponentUsage AS (
    SELECT
        ComponentID,
        SUM(Quantity) AS UnitsConsumedLast6Months
    FROM inventory_movements
    WHERE MovementType = 'Usage'
      AND MovementDate BETWEEN '2026-04-01' AND '2026-09-30'
    GROUP BY ComponentID
),

ComponentForecast AS (
    SELECT
        c.ComponentID,
        c.ComponentName,
        c.Category,
        c.CurrentStock,
        c.SafetyStock,
        c.LeadTimeDays,
        COALESCE(u.UnitsConsumedLast6Months, 0)
            AS UnitsConsumedLast6Months,

        ROUND(COALESCE(u.UnitsConsumedLast6Months, 0) / 6.0, 2) AS ForecastedMonthlyDemand
    FROM components c
    LEFT JOIN ComponentUsage u
        ON c.ComponentID = u.ComponentID
)

SELECT
    ComponentID,
    ComponentName,
    Category,
    CurrentStock,
    SafetyStock,
    LeadTimeDays,
    UnitsConsumedLast6Months,
    ForecastedMonthlyDemand
FROM ComponentForecast
ORDER BY ForecastedMonthlyDemand DESC
LIMIT 20;



-- Component Replenishment Recommendations --
-- Based on 6-month average consumption --
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

DemandForecast AS (
    SELECT
        c.ComponentID,
        c.ComponentName,
        c.Category,
        c.CurrentStock,
        c.SafetyStock,
        c.LeadTimeDays,

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

    FROM DemandForecast
)

SELECT
    ComponentID,
    ComponentName,
    Category,
    CurrentStock,
    SafetyStock,
    LeadTimeDays,

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
FROM ReorderCalculations

ORDER BY
    CASE
        WHEN CurrentStock <= ReorderPoint THEN 1
        WHEN CurrentStock < ReorderPoint * 2 THEN 2
        ELSE 3
    END,
    StockAboveReorderPoint ASC
LIMIT 20;



-- Replenishment Recommendation Summary --
-- All 500 components --
WITH ComponentUsage AS (
    SELECT
        ComponentID,
        SUM(Quantity) AS UnitsConsumedLast6Months
    FROM inventory_movements
    WHERE MovementType = 'Usage'
      AND MovementDate BETWEEN '2026-04-01' AND '2026-09-30'
    GROUP BY ComponentID
),

DemandForecast AS (
    SELECT
        c.ComponentID,
        c.CurrentStock,
        c.SafetyStock,
        c.LeadTimeDays,
        c.UnitCost,

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

    FROM DemandForecast
),

Recommendations AS (
    SELECT
        *,
        CASE
            WHEN CurrentStock <= ReorderPoint
                THEN 'Reorder Review'

            WHEN CurrentStock < ReorderPoint * 2
                THEN 'Monitor Inventory'

            ELSE 'Defer Replenishment Review'
        END AS Recommendation
    FROM ReorderCalculations
)

SELECT
    Recommendation,
    COUNT(*) AS ComponentCount,
    SUM(CurrentStock) AS TotalUnitsInStock,

    ROUND(
        SUM(CurrentStock * UnitCost),
        2
    ) AS TotalInventoryValue,

    ROUND(
        COUNT(*) * 100.0
        / (SELECT COUNT(*) FROM components),
        2
    ) AS PercentageOfComponents
FROM Recommendations
GROUP BY Recommendation
ORDER BY ComponentCount DESC;