/* =====================================================================
   02  CLEAN SALES TABLE  (Queries F–J)
   ---------------------------------------------------------------------
   Build one trustworthy sales table, sales_clean, that:
     - fixes Trap 1 (AMZ-NL -> Amazon)
     - fixes Trap 3 (removes the duplicate rows)
     - converts Amazon bundles into parent units, because forecasting
       and replenishment happen at parent SKU level
       (e.g. 23 units of a 3-pack bundle = 69 parent units)
     - keeps sales and returns in separate columns
   Trap 2 (the missing week) cannot be cleaned here: that data was never
   loaded. It is filled from the inventory table in file 03.
   ===================================================================== */


/* Query F: Fix the legacy channel code (Trap 1).
   CASE WHEN works like Excel's IF(). Result: only Amazon and B2B. */
SELECT CASE WHEN channel = 'AMZ-NL' THEN 'Amazon'
            ELSE channel
       END AS channel_clean,
       COUNT(*) AS number_of_rows
FROM sales_weekly
GROUP BY channel_clean;


/* Query G: Remove the duplicate rows (Trap 3).
   SELECT DISTINCT * keeps one copy of rows that are identical in every
   column, like Excel's "Remove Duplicates".
   192,383 rows before, 191,364 after: 1,019 duplicates removed,
   exactly the double-loaded week 2025-10-13. */
SELECT COUNT(*) AS rows_after_cleaning
FROM (SELECT DISTINCT * FROM sales_weekly);


/* Query H: Convert bundles to parent units.
   JOIN works like VLOOKUP: for each sales row, look up the parent SKU
   and pack multiplier in sellable_skus. Negative units are returns. */
SELECT s.week_start,
       s.sellable_sku,
       k.parent_sku,
       k.pack_multiplier,
       s.units,
       s.units * k.pack_multiplier AS parent_units
FROM sales_weekly AS s
JOIN sellable_skus AS k
  ON s.sellable_sku = k.sellable_sku
WHERE k.pack_multiplier > 1
LIMIT 5;


/* Query I: Build the view sales_clean (saved in the database).
   One row = one parent SKU, in one channel, in one week.
   units_sold is used for forecasting: a return does not mean the
   customer's demand disappeared, so returns are kept separately. */
CREATE VIEW sales_clean AS
WITH deduplicated AS (
    SELECT DISTINCT * FROM sales_weekly
)
SELECT d.week_start,
       k.parent_sku,
       CASE WHEN d.channel = 'AMZ-NL' THEN 'Amazon' ELSE d.channel END AS channel,
       SUM(CASE WHEN d.record_type = 'SALE'   THEN d.units * k.pack_multiplier ELSE 0 END) AS units_sold,
       SUM(CASE WHEN d.record_type = 'RETURN' THEN -d.units * k.pack_multiplier ELSE 0 END) AS units_returned,
       ROUND(SUM(d.net_sales_eur), 2) AS net_sales_eur
FROM deduplicated AS d
JOIN sellable_skus AS k
  ON d.sellable_sku = k.sellable_sku
GROUP BY d.week_start,
         k.parent_sku,
         CASE WHEN d.channel = 'AMZ-NL' THEN 'Amazon' ELSE d.channel END;


/* Query J: Check the new view.
   Expected: Amazon 202 weeks / 2,148,471 units sold,
             B2B 203 weeks / 1,242,094 units sold. */
SELECT channel,
       COUNT(DISTINCT week_start) AS weeks,
       SUM(units_sold)            AS total_units_sold
FROM sales_clean
GROUP BY channel;
