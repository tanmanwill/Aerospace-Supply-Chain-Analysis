-- Overall Procurement Summary --
SELECT
    COUNT(*) AS TotalPurchaseOrders,
    ROUND(SUM(TotalCost), 2) AS TotalProcurementSpend,
    ROUND(AVG(TotalCost), 2) AS AverageOrderValue,
    SUM(QuantityOrdered) AS TotalUnitsOrdered
FROM purchase_orders
WHERE OrderDate <= '2026-09-30';


-- Procurement Spending by Component Category --
SELECT
    c.Category,
    COUNT(po.OrderID) AS TotalOrders,
    ROUND(SUM(po.TotalCost), 2) AS TotalSpend,
    SUM(po.QuantityOrdered) AS UnitsOrdered,
    ROUND(AVG(po.TotalCost), 2) AS AverageOrderValue
FROM purchase_orders po
JOIN components c
    ON po.ComponentID = c.ComponentID
WHERE po.OrderDate <= '2026-09-30'
GROUP BY c.Category
ORDER BY TotalSpend DESC;