/* =====================================================================
   01  DATA QUALITY CHECKS  (Queries A–E)
   ---------------------------------------------------------------------
   Before measuring forecast accuracy, check that the sales data can be
   trusted. Every real export has problems. These checks look for three
   common ones in sales_weekly:
     Trap 1: an old channel code still in the data
     Trap 2: a week of data that was never loaded
     Trap 3: a week that was loaded twice
   All queries in this file only look at the data; nothing is changed.
   ===================================================================== */


/* Query A: Which sales channels exist, and over which period?
   Expected: two channels (Amazon, B2B).
   Found: a third code, 'AMZ-NL', used for Amazon until June 2023,
   then replaced by 'Amazon'.  -> Trap 1 */
SELECT channel,
       COUNT(*)        AS number_of_rows,
       MIN(week_start) AS first_week,
       MAX(week_start) AS last_week
FROM sales_weekly
GROUP BY channel;


/* Query B: Rows per week and channel, smallest first.
   The smallest weeks are B2B holiday weeks (Christmas, bouwvak):
   real seasonality, not an error.
   Lesson: a week with zero rows can never appear in a GROUP BY result,
   so missing weeks must be found by counting (Query D) or by looking
   for gaps (Query E). */
SELECT week_start,
       channel,
       COUNT(*) AS number_of_rows
FROM sales_weekly
GROUP BY week_start, channel
ORDER BY number_of_rows ASC
LIMIT 10;


/* Query C: Is any row counted twice?
   Each sellable SKU should appear once per week, channel and record type.
   Found: every row of week 2025-10-13 appears twice (file loaded twice).
   -> Trap 3 */
SELECT week_start,
       sellable_sku,
       channel,
       record_type,
       COUNT(*) AS copies
FROM sales_weekly
GROUP BY week_start, sellable_sku, channel, record_type
HAVING COUNT(*) > 1
LIMIT 20;


/* Query D: How many weeks of data does each channel have?
   The data covers 203 weeks. B2B has 203; Amazon + AMZ-NL have 202.
   One Amazon week is missing. */
SELECT channel,
       COUNT(DISTINCT week_start) AS weeks_with_data
FROM sales_weekly
GROUP BY channel;


/* Query E: Which Amazon week is missing?
   Weeks are normally 7 days apart. LAG() takes the previous week,
   so a gap larger than 7 days marks a missing week.
   Found: 14-day gap between 2024-08-05 and 2024-08-19,
   so week 2024-08-12 is missing.  -> Trap 2 */
WITH amazon_weeks AS (
    SELECT DISTINCT week_start
    FROM sales_weekly
    WHERE channel IN ('Amazon', 'AMZ-NL')
)
SELECT week_start,
       LAG(week_start) OVER (ORDER BY week_start) AS previous_week,
       julianday(week_start)
         - julianday(LAG(week_start) OVER (ORDER BY week_start)) AS days_gap
FROM amazon_weeks
ORDER BY days_gap DESC
LIMIT 3;
