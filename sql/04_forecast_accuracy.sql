/* =====================================================================
   04  FORECAST ACCURACY: 1M vs 3M vs 6M  (Queries P–U)
   ---------------------------------------------------------------------
   Every Monday the forecasting tool shows three rates per SKU: the
   average forecast units per week over the next 1, 3 and 6 months.
   The planner's question: which rate should I trust?
   The answer depends on the decision:
     - short-term moves (FBA transfers, expediting): next 4 weeks
     - supplier orders (~13-week lead time from Asia): next 13 weeks
   So all three rates are tested on both horizons.
   ===================================================================== */


/* Query P: What does the forecasting tool show?
   Example row 2025-03-03: 565 / 500 / 478 units per week.
   The 1M rate swings most with the season; the 6M rate is smoothest. */
SELECT snapshot_week,
       fcst_rate_1m,
       fcst_rate_3m,
       fcst_rate_6m
FROM forecast_snapshots
WHERE parent_sku = 'Switch_Single_Flush_White_1PK'
  AND snapshot_week BETWEEN '2025-02-03' AND '2025-03-31';


/* Query Q: Build the view forecast_vs_actual (saved in the database).
   For every forecast, collect the 13 weeks that followed it
   (JOIN ... BETWEEN snapshot_week AND snapshot_week + 84 days), then:
     actual_rate_next_4w   = average weekly sales over the first 4 weeks
                             (the CASE WHEN keeps weeks 1-4 only)
     actual_rate_next_13w  = average weekly sales over all 13 weeks
     stockout_weeks_next_* = stockout weeks inside each window
     weeks_available       = 13 unless the window runs past the data */
CREATE VIEW forecast_vs_actual AS
SELECT f.snapshot_week,
       f.parent_sku,
       f.fcst_rate_1m,
       f.fcst_rate_3m,
       f.fcst_rate_6m,
       SUM(CASE WHEN d.week_start <= DATE(f.snapshot_week, '+21 days')
                THEN d.total_units END) / 4.0          AS actual_rate_next_4w,
       SUM(CASE WHEN d.week_start <= DATE(f.snapshot_week, '+21 days')
                THEN d.stockout_week END)              AS stockout_weeks_next_4w,
       SUM(d.total_units) / 13.0                       AS actual_rate_next_13w,
       SUM(d.stockout_week)                            AS stockout_weeks_next_13w,
       COUNT(*)                                        AS weeks_available
FROM forecast_snapshots AS f
JOIN demand_weekly AS d
  ON d.parent_sku = f.parent_sku
 AND d.week_start BETWEEN f.snapshot_week AND DATE(f.snapshot_week, '+84 days')
GROUP BY f.snapshot_week, f.parent_sku;


/* Query R: Hand check of one row.
   BlankPlate_Aluminium_1PK, forecast made 2026-05-11:
   next 4 weeks sold 15 + 6 + 6 + 8 = 35 units -> 35 / 4 = 8.75 per week. */
SELECT *
FROM forecast_vs_actual
WHERE parent_sku = 'BlankPlate_Aluminium_1PK'
  AND snapshot_week = '2026-05-11';


/* Query S: Forecast accuracy over the next 4 weeks

   To judge a forecast, two measures are needed. One number alone can
   mislead: a forecast can have small errors overall but still always
   lean the same way.

   1. WAPE (Weighted Absolute Percentage Error): HOW BIG are the errors?
      - Adds up all errors, ignoring plus or minus, and divides by
        total actual sales.
      - "Weighted": big-selling SKUs count more than slow movers, so a
        few tiny SKUs with huge % errors don't distort the result.
      - Lower is better; 0% = perfect.
      - Formula: SUM(ABS(forecast - actual)) / SUM(actual)

   2. Bias: WHICH DIRECTION do the errors lean?
      - Same idea, but keeps the plus and minus signs, so errors can
        cancel out.
      - A forecast that is always too low causes repeated stockouts;
        one always too high builds overstock, even if its WAPE looks fine.
      - Minus = forecast too low (stockout risk)
        Plus  = forecast too high (overstock risk)
        Within +/-5% = treated as acceptable
      - Formula: SUM(forecast - actual) / SUM(actual)

   Filters, so the scoring is fair:
     - from 2024 only (in 2023 the tool was still learning seasonality)
     - complete 13-week windows only
     - no stockout in the window (stockout weeks understate real demand)

   Result: 1M rate wins. WAPE 21.3% vs 23.5% (3M) and 23.8% (6M).
   Bias near zero for all three. */
SELECT COUNT(*) AS forecasts_scored,
       ROUND(100.0 * SUM(ABS(fcst_rate_1m - actual_rate_next_4w)) / SUM(actual_rate_next_4w), 1) AS wape_1m,
       ROUND(100.0 * SUM(ABS(fcst_rate_3m - actual_rate_next_4w)) / SUM(actual_rate_next_4w), 1) AS wape_3m,
       ROUND(100.0 * SUM(ABS(fcst_rate_6m - actual_rate_next_4w)) / SUM(actual_rate_next_4w), 1) AS wape_6m,
       ROUND(100.0 * SUM(fcst_rate_1m - actual_rate_next_4w) / SUM(actual_rate_next_4w), 1)      AS bias_1m,
       ROUND(100.0 * SUM(fcst_rate_3m - actual_rate_next_4w) / SUM(actual_rate_next_4w), 1)      AS bias_3m,
       ROUND(100.0 * SUM(fcst_rate_6m - actual_rate_next_4w) / SUM(actual_rate_next_4w), 1)      AS bias_6m
FROM forecast_vs_actual
WHERE snapshot_week >= '2024-01-01'
  AND weeks_available = 13
  AND stockout_weeks_next_4w = 0;


/* Query T: Forecast accuracy over the next 13 weeks (supplier ordering).
   Same as Query S with 4w -> 13w.
   Result: 3M rate wins. WAPE 18.2% vs 20.4% (1M) and 19.6% (6M).
   Bias near zero. 6M never wins on either horizon. */
SELECT COUNT(*) AS forecasts_scored,
       ROUND(100.0 * SUM(ABS(fcst_rate_1m - actual_rate_next_13w)) / SUM(actual_rate_next_13w), 1) AS wape_1m,
       ROUND(100.0 * SUM(ABS(fcst_rate_3m - actual_rate_next_13w)) / SUM(actual_rate_next_13w), 1) AS wape_3m,
       ROUND(100.0 * SUM(ABS(fcst_rate_6m - actual_rate_next_13w)) / SUM(actual_rate_next_13w), 1) AS wape_6m,
       ROUND(100.0 * SUM(fcst_rate_1m - actual_rate_next_13w) / SUM(actual_rate_next_13w), 1)      AS bias_1m,
       ROUND(100.0 * SUM(fcst_rate_3m - actual_rate_next_13w) / SUM(actual_rate_next_13w), 1)      AS bias_3m,
       ROUND(100.0 * SUM(fcst_rate_6m - actual_rate_next_13w) / SUM(actual_rate_next_13w), 1)      AS bias_6m
FROM forecast_vs_actual
WHERE snapshot_week >= '2024-01-01'
  AND weeks_available = 13
  AND stockout_weeks_next_13w = 0;


/* Query U: What if stockout weeks are NOT excluded?
   Same as Query T without the stockout filter (the usual, easy way).
   Result: bias flips from ~0% to +4.9% / +5.7% / +5.6%, so the forecast
   LOOKS too high, because sales were capped by empty shelves.
   A planner seeing only this would cut the forecast, order less and
   cause more stockouts: the stockout spiral. */
SELECT COUNT(*) AS forecasts_scored,
       ROUND(100.0 * SUM(ABS(fcst_rate_1m - actual_rate_next_13w)) / SUM(actual_rate_next_13w), 1) AS wape_1m,
       ROUND(100.0 * SUM(ABS(fcst_rate_3m - actual_rate_next_13w)) / SUM(actual_rate_next_13w), 1) AS wape_3m,
       ROUND(100.0 * SUM(ABS(fcst_rate_6m - actual_rate_next_13w)) / SUM(actual_rate_next_13w), 1) AS wape_6m,
       ROUND(100.0 * SUM(fcst_rate_1m - actual_rate_next_13w) / SUM(actual_rate_next_13w), 1)      AS bias_1m,
       ROUND(100.0 * SUM(fcst_rate_3m - actual_rate_next_13w) / SUM(actual_rate_next_13w), 1)      AS bias_3m,
       ROUND(100.0 * SUM(fcst_rate_6m - actual_rate_next_13w) / SUM(actual_rate_next_13w), 1)      AS bias_6m
FROM forecast_vs_actual
WHERE snapshot_week >= '2024-01-01'
  AND weeks_available = 13;
