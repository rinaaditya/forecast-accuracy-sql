/* =====================================================================
   03  WEEKLY ACTUALS + STOCKOUT FLAGS  (Queries K–O)
   ---------------------------------------------------------------------
   Build demand_weekly: one row per parent SKU per week, answering
     1. How many units did we actually sell (all channels)?
     2. Was this a stockout week? If yes, sales understate real demand,
        and the forecast cannot be judged fairly on that week.
   This is the "actuals" table that forecast accuracy is measured against.
   ===================================================================== */


/* Query K: Can the inventory table fill the missing Amazon week (Trap 2)?
   Every Amazon sale is recorded twice: in the sales report and as a unit
   shipped from Amazon FBA in the inventory report. In normal weeks the
   two match exactly; in week 2024-08-12 sales is empty but FBA shipped
   9,038 units. So the inventory number is a reliable backup.
   LEFT JOIN keeps every week from the inventory side, even when the
   sales side has no match (shown as NULL). */
SELECT i.week_start,
       s.amazon_units_in_sales,
       i.units_shipped_from_fba
FROM (SELECT week_start, SUM(shipped_units) AS units_shipped_from_fba
      FROM inventory_weekly
      WHERE location = 'Amazon FBA'
      GROUP BY week_start) AS i
LEFT JOIN (SELECT week_start, SUM(units_sold) AS amazon_units_in_sales
           FROM sales_clean
           WHERE channel = 'Amazon'
           GROUP BY week_start) AS s
  ON i.week_start = s.week_start
WHERE i.week_start BETWEEN '2024-07-29' AND '2024-08-26';


/* Query L: How often were we out of stock, per stock location and year?
   One row of inventory_weekly = one SKU in one week (a "SKU-week").
   A stockout week = 2 or more days out of stock in that week
   (one day barely changes weekly sales; two or more visibly cut them).
   Result: Amazon FBA ~6-8% of SKU-weeks, Warehouse NL ~8-11%;
   2024 is worse than 2023 because of Red Sea shipping delays. */
SELECT location,
       SUBSTR(week_start, 1, 4) AS year,
       COUNT(*)                 AS sku_weeks,
       SUM(CASE WHEN days_out_of_stock >= 2 THEN 1 ELSE 0 END) AS stockout_weeks,
       ROUND(100.0 * SUM(CASE WHEN days_out_of_stock >= 2 THEN 1 ELSE 0 END)
             / COUNT(*), 1)     AS pct_stockout
FROM inventory_weekly
GROUP BY location, year
ORDER BY location, year;


/* Query M: Build the view demand_weekly (saved in the database).
   The WITH blocks are helper tables used only while the query runs:
     warehouse     = master list of SKU-weeks + warehouse stockout days
                     (every live SKU has one warehouse row per week,
                     so weeks with zero sales are included)
     fba           = units shipped from Amazon FBA + FBA stockout days
     b2b_sales     = B2B units sold (from sales_clean)
     amazon_sales  = Amazon units sold (from sales_clean)
   COALESCE(a, b, 0) = "use the first value that is not empty".
   Amazon units: use sales; if missing (Trap 2), use FBA shipped; else 0.
   The raw and clean sales layers are left untouched: the gap is filled
   in this separate layer, so every adjustment stays traceable. */
CREATE VIEW demand_weekly AS
WITH warehouse AS (
    SELECT week_start, parent_sku, days_out_of_stock AS warehouse_days_oos
    FROM inventory_weekly
    WHERE location = 'Warehouse NL'
),
fba AS (
    SELECT week_start, parent_sku, shipped_units AS fba_shipped, days_out_of_stock AS fba_days_oos
    FROM inventory_weekly
    WHERE location = 'Amazon FBA'
),
b2b_sales AS (
    SELECT week_start, parent_sku, units_sold
    FROM sales_clean
    WHERE channel = 'B2B'
),
amazon_sales AS (
    SELECT week_start, parent_sku, units_sold
    FROM sales_clean
    WHERE channel = 'Amazon'
)
SELECT w.week_start,
       w.parent_sku,
       COALESCE(b.units_sold, 0)                    AS b2b_units,
       COALESCE(a.units_sold, f.fba_shipped, 0)     AS amazon_units,
       COALESCE(b.units_sold, 0)
         + COALESCE(a.units_sold, f.fba_shipped, 0) AS total_units,
       w.warehouse_days_oos,
       COALESCE(f.fba_days_oos, 0)                  AS fba_days_oos,
       CASE WHEN w.warehouse_days_oos >= 2 OR f.fba_days_oos >= 2
            THEN 1 ELSE 0 END                       AS stockout_week
FROM warehouse AS w
LEFT JOIN fba          AS f ON w.week_start = f.week_start AND w.parent_sku = f.parent_sku
LEFT JOIN b2b_sales    AS b ON w.week_start = b.week_start AND w.parent_sku = b.parent_sku
LEFT JOIN amazon_sales AS a ON w.week_start = a.week_start AND w.parent_sku = a.parent_sku;


/* Query N: Check the new view.
   Expected: 95,535 SKU-weeks, 3,399,603 units, 11,916 stockout weeks (12.5%). */
SELECT COUNT(*)                                        AS number_of_rows,
       SUM(total_units)                                AS total_units,
       SUM(stockout_week)                              AS stockout_weeks,
       ROUND(100.0 * SUM(stockout_week) / COUNT(*), 1) AS pct_stockout_weeks
FROM demand_weekly;


/* Query O: The stockout effect on one best-seller.
   This switch normally sells ~400-900 units a week. When the warehouse
   was out of stock for 7 days, sales dropped to 338 and 242.
   Demand did not fall; there was simply nothing to sell. */
SELECT week_start,
       total_units,
       warehouse_days_oos,
       fba_days_oos,
       stockout_week
FROM demand_weekly
WHERE parent_sku = 'Switch_Single_Flush_White_1PK'
  AND week_start BETWEEN '2024-03-04' AND '2024-05-27';


/* Extra: Class is not stored in demand_weekly. Each fact is stored once
   (Class lives in products) and looked up when needed. Class is also
   "as of today" (last 52 weeks of margin), so copying it onto 2023 rows
   would be misleading. */
SELECT d.parent_sku,
       p.sales_class,
       d.week_start,
       d.total_units,
       d.stockout_week
FROM demand_weekly AS d
JOIN products AS p
  ON d.parent_sku = p.parent_sku
LIMIT 20;
