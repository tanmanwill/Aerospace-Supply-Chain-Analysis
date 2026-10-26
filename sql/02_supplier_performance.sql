-- Supplier On-Time Delivery Performance
-- Reporting cutoff: September 30, 2026

SELECT
    s.SupplierID,
    s.SupplierName,
    COUNT(sh.ShipmentID) AS TotalDeliveries,

    SUM(
        CASE
            WHEN sh.ActualDeliveryDate <= po.ExpectedDeliveryDate
            THEN 1
            ELSE 0
        END
    ) AS OnTimeDeliveries,

    SUM(
        CASE
            WHEN sh.ActualDeliveryDate > po.ExpectedDeliveryDate
            THEN 1
            ELSE 0
        END
    ) AS LateDeliveries,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN sh.ActualDeliveryDate <= po.ExpectedDeliveryDate
                THEN 1
                ELSE 0
            END
        ) / COUNT(sh.ShipmentID),
        2
    ) AS OnTimeDeliveryRate

FROM shipments sh

JOIN purchase_orders po
    ON sh.OrderID = po.OrderID

JOIN suppliers s
    ON po.SupplierID = s.SupplierID

WHERE sh.ActualDeliveryDate <= '2026-09-30'

GROUP BY
    s.SupplierID,
    s.SupplierName

ORDER BY OnTimeDeliveryRate ASC;


-- Supplier Defect Rate Analysis --
SELECT
    s.SupplierID,
    s.SupplierName,

    COUNT(sh.ShipmentID) AS TotalShipments,

    SUM(sh.QuantityReceived) AS TotalUnitsReceived,

    SUM(sh.DefectiveUnits) AS TotalDefectiveUnits,

    ROUND(
        100.0 * SUM(sh.DefectiveUnits)
        / NULLIF(SUM(sh.QuantityReceived), 0),
        2
    ) AS DefectRate

FROM shipments sh

JOIN purchase_orders po
    ON sh.OrderID = po.OrderID

JOIN suppliers s
    ON po.SupplierID = s.SupplierID

WHERE sh.ActualDeliveryDate <= '2026-09-30'

GROUP BY
    s.SupplierID,
    s.SupplierName

ORDER BY DefectRate DESC;


-- Combined Supplier Risk Analysis --

WITH SupplierMetrics AS (
    SELECT
        s.SupplierID,
        s.SupplierName,

        COUNT(sh.ShipmentID) AS TotalShipments,

        ROUND(
            100.0 * SUM(
                CASE
                    WHEN sh.ActualDeliveryDate <= po.ExpectedDeliveryDate
                    THEN 1 ELSE 0
                END
            ) / COUNT(sh.ShipmentID),
            2
        ) AS OnTimeDeliveryRate,

        ROUND(
            100.0 * SUM(sh.DefectiveUnits)
            / NULLIF(SUM(sh.QuantityReceived), 0),
            2
        ) AS DefectRate

    FROM suppliers s
    JOIN purchase_orders po
        ON s.SupplierID = po.SupplierID
    JOIN shipments sh
        ON po.OrderID = sh.OrderID

    WHERE sh.ActualDeliveryDate <= '2026-09-30'

    GROUP BY s.SupplierID, s.SupplierName
)

SELECT
    SupplierID,
    SupplierName,
    TotalShipments,
    OnTimeDeliveryRate,
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

FROM SupplierMetrics

ORDER BY
    CASE
        WHEN RiskCategory = 'High Risk' THEN 1
        WHEN RiskCategory = 'Moderate Risk' THEN 2
        ELSE 3
    END,
    OnTimeDeliveryRate ASC;