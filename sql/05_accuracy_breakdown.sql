/* =====================================================================
   05  WHERE IS THE FORECAST WEAKEST?  (Queries V–X)
   ---------------------------------------------------------------------
   File 04 gave one overall score. This file breaks it down by Class,
   product type and month to find WHERE the forecast performs worst.

   Standard used from here on:
   - 3M rate vs actual sales over the next 13 weeks
     (= the supplier ordering decision, Finding 2)
   - Stockout weeks excluded
     (they make a good forecast look too high, Finding 3)
   - Bias within +/-5% treated as acceptable

   Rule of thumb: compare WAPE and |bias|.
   - Close together: the error is mostly systematic -> find the cause, fix it.
   - WAPE much bigger than |bias|: mostly random noise -> hard to fix,
     safety stock covers it.
   ===================================================================== */


/* Query V: Accuracy by Class
   Class (1-5) is based on gross margin over the last 52 weeks.
   Result: Class 5 is worst, WAPE 24.1% and bias +9.5% (over-forecast),
   so stock builds up in the lowest-margin, lowest-revenue SKUs.
   Class 1 is best: WAPE 16.6%, bias -0.1%. */
SELECT p.sales_class,
       COUNT(*) AS forecasts_scored,
       ROUND(100.0 * SUM(ABS(fa.fcst_rate_3m - fa.actual_rate_next_13w)) / SUM(fa.actual_rate_next_13w), 1) AS wape_3m,
       ROUND(100.0 * SUM(fa.fcst_rate_3m - fa.actual_rate_next_13w) / SUM(fa.actual_rate_next_13w), 1)      AS bias_3m
FROM forecast_vs_actual AS fa
JOIN products AS p
  ON fa.parent_sku = p.parent_sku
WHERE fa.snapshot_week >= '2024-01-01'
  AND fa.weeks_available = 13
  AND fa.stockout_weeks_next_13w = 0
GROUP BY p.sales_class
ORDER BY p.sales_class;


/* Query W: Accuracy by product type, worst first
   Results:
   - New products are UNDER-forecast: SmartSwitch (bias -49.3%),
     SmartPlug (-19.2%), SurgeProtector (-11.4%). Short history and fast
     growth, so the forecast trails demand.
   - Outdoor products are OVER-forecast: ExtensionReel (+26.3%),
     ExtensionCable (+23.2%). The tool uses one seasonal pattern per
     category, which misses outdoor seasonality.
   - Copper Cable is OVER-forecast (+11.9%): 2026 price increases cut
     demand, and the tool does not see prices.
   For ExtensionReel, WAPE (29.0%) is close to |bias| (26.3%):
   a systematic, fixable error. */
SELECT p.product_type,
       COUNT(*) AS forecasts_scored,
       ROUND(100.0 * SUM(ABS(fa.fcst_rate_3m - fa.actual_rate_next_13w)) / SUM(fa.actual_rate_next_13w), 1) AS wape_3m,
       ROUND(100.0 * SUM(fa.fcst_rate_3m - fa.actual_rate_next_13w) / SUM(fa.actual_rate_next_13w), 1)      AS bias_3m
FROM forecast_vs_actual AS fa
JOIN products AS p
  ON fa.parent_sku = p.parent_sku
WHERE fa.snapshot_week >= '2024-01-01'
  AND fa.weeks_available = 13
  AND fa.stockout_weeks_next_13w = 0
GROUP BY p.product_type
ORDER BY wape_3m DESC;


/* Query X: Accuracy by the month the forecast was made
   forecast_month = 7 means "forecasts made in July, judged on the
   13 weeks after (July to October)".
   Results:
   - November -8.3% (under): Black Friday and Cyber Monday spikes
   - July     +7.5% (over):  the Prime Day spike lifts the forecast just
                             before the bouwvak construction holiday
                             cuts B2B demand
   - December +6.2% (over):  quiet Christmas and New Year weeks
   The tool handles gradual seasonality, but not short, sharp calendar
   events: promotions and holidays need manual adjustment. */
SELECT CAST(SUBSTR(fa.snapshot_week, 6, 2) AS INTEGER) AS forecast_month,
       COUNT(*) AS forecasts_scored,
       ROUND(100.0 * SUM(ABS(fa.fcst_rate_3m - fa.actual_rate_next_13w)) / SUM(fa.actual_rate_next_13w), 1) AS wape_3m,
       ROUND(100.0 * SUM(fa.fcst_rate_3m - fa.actual_rate_next_13w) / SUM(fa.actual_rate_next_13w), 1)      AS bias_3m
FROM forecast_vs_actual AS fa
WHERE fa.snapshot_week >= '2024-01-01'
  AND fa.weeks_available = 13
  AND fa.stockout_weeks_next_13w = 0
GROUP BY forecast_month
ORDER BY forecast_month;
