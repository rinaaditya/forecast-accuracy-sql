# Kanaal Electric B.V. — Dataset (simulated)

> **All data in this folder is simulated.** Kanaal Electric B.V. is a fictional company, and all supplier names are invented. The dataset was designed by a supply chain planner to reflect realistic weekly planning conditions: seasonality, Amazon promotions, supplier delays, material cost increases, stockouts, dead stock and manual planner overrides. It contains no real company, product, customer or supplier data.

## The company

- Dutch e-commerce seller of electrical installation components. Its own warehouse is in the Netherlands, and imports come in through the **Port of Rotterdam**
- Sales channels: **Amazon (~60% of revenue)**, fulfilled from Amazon FBA warehouses, and **B2B (~40%)** to installers and resellers, shipped from the company warehouse
- **498 parent SKUs** in 4 categories: Electric Sockets, Switches & Outlets, Wires & Cables, and Circuit Protection & Distribution
- **659 sellable SKUs**: 161 of them are Amazon bundles of a parent SKU (e.g. `Socket_USB-C_20W_White_4PK` = 2 × `Socket_USB-C_20W_White_2PK`)
- **3 suppliers**: China and Vietnam (sea freight to Rotterdam) and Morocco (nearshore, truck + ferry)
- Planning rhythm: **weekly**. Forecasts are refreshed weekly, replenishment is weekly, and weeks start on Monday
- Period: **2 Jan 2023 – 22 Nov 2026** (203 weeks). Currency: **EUR**, excluding VAT

## How stock flows

```
Supplier ──(production)──> Ready at supplier ──(departure)──> At sea / on road ──> Port of Rotterdam ──> Warehouse NL
                                                                                                          │
                                                               B2B customers <────────────────────────────┤
                                                                                                          │ weekly transfer
                                                               Amazon customers <── Amazon FBA <──────────┘
```

Inventory is held in two pools, **Warehouse NL** and **Amazon FBA**, and each needs its own days-of-inventory (DOI) check.

## Tables

| Table | One row = | Rows |
|---|---|---|
| `products` | one parent SKU | 498 |
| `sellable_skus` | one SKU as sold (single or bundle) | 659 |
| `suppliers` | one supplier | 3 |
| `price_history` | one cost/price change for a SKU | 2,804 |
| `calendar_events` | one event in one week | 50 |
| `sales_weekly` | one sellable SKU × channel × record type × week | ~192,000 |
| `inventory_weekly` | one parent SKU × location × week | ~191,000 |
| `forecast_snapshots` | what the forecasting tool said for one SKU in one week | ~93,000 |
| `purchase_orders` | one purchase order (one SKU) | ~9,100 |
| `po_shipments` | one shipment against a PO (a PO can have several) | ~9,600 |

### products
| Column | Meaning |
|---|---|
| parent_sku | Planning-level SKU, written as a readable name: `Type_Spec_Colour_Pack` |
| category, product_type | Product grouping |
| colour, pack_size | Variant attributes |
| supplier_id | Supplier |
| carton_qty | Units per carton (order multiple) |
| moq | Minimum order quantity |
| launch_date | First sales week for products launched after Jan 2023 (blank = existing range) |
| discontinue_date | Date discontinued (blank = active) |
| replaces_sku | Older SKU this product replaces |
| status | Active / Discontinued |
| sales_class | 1–5, based on gross margin over the last 52 weeks: **1** ≥ 25% · **2** 15–25% · **3** 10–15% · **4** < 10%, top half by revenue · **5** < 10%, bottom half by revenue |

### sellable_skus
| Column | Meaning |
|---|---|
| sellable_sku | SKU as sold to the customer |
| parent_sku | Planning SKU it is made of |
| pack_multiplier | Parent units in one sellable unit |
| channel_availability | Amazon + B2B / Amazon only / B2B only |

### suppliers
| Column | Meaning |
|---|---|
| supplier_id, supplier_name, country, origin_port | Supplier identity (fictional names) |
| transport_mode, incoterm | Shipping set-up |
| planned_production_weeks, planned_transit_weeks | Original standard lead-time parameters |

### price_history
| Column | Meaning |
|---|---|
| effective_date | Date the new cost/price applies |
| unit_cost_eur | Purchase cost per parent unit |
| b2b_price_eur | B2B selling price per parent unit |
| amazon_price_eur | Amazon list price per parent unit (excl. VAT, before Amazon fees) |
| change_reason | Initial price / Material cost increase |

### calendar_events
`week_start`, `event_name` (e.g. Amazon Prime Day, Black Friday, Bouwvak, Price increase effective, Amazon FBA capacity limits), `event_type` (Promotion / Holiday / Price / Supply).

### sales_weekly
| Column | Meaning |
|---|---|
| week_start | Monday of the sales week |
| sellable_sku | SKU as sold |
| channel | Sales channel |
| record_type | SALE or RETURN (returns have negative units) |
| units | Units of the **sellable** SKU (× `pack_multiplier` = parent units) |
| net_sales_eur | Net revenue excl. VAT; Amazon revenue is after Amazon fees |

### inventory_weekly
| Column | Meaning |
|---|---|
| week_start, parent_sku | Week and SKU |
| location | `Warehouse NL` or `Amazon FBA` |
| opening_on_hand | Stock at the start of the week |
| received_units | Warehouse: received from suppliers. FBA: received from the warehouse transfer |
| transferred_out_units | Warehouse only: units sent to Amazon FBA this week |
| shipped_units | Units shipped to customers (B2B from the warehouse, Amazon orders from FBA) |
| closing_on_hand | Stock at the end of the week |
| days_out_of_stock | Days in the week the SKU could not be sold from this location |

### forecast_snapshots
What the forecasting tool showed the planner at the start of each week. Rates are in **units per week** (divide by 7 for a daily rate when calculating DOI).

| Column | Meaning |
|---|---|
| snapshot_week | Week the forecast was made |
| fcst_rate_1m / 3m / 6m | Average forecast units per week over the next 1, 3 and 6 months (all channels) |
| amazon_fcst_month1 / 2 / 3 | Forecast Amazon units for the next month, the month after, and month 3 |

### purchase_orders
| Column | Meaning |
|---|---|
| po_number, parent_sku, supplier_id | What was ordered from whom |
| order_date | Date the PO was placed |
| system_suggested_qty | Quantity the replenishment system suggested (0 = no order suggested) |
| ordered_qty | Final quantity the planner ordered |
| planner_comment | Planner's note, when one was written (often blank) |
| unit_cost_eur | Cost per unit on the PO |
| promised_arrival_date | Expected warehouse arrival at the time of ordering |
| qty_received_to_date | Units received so far |
| po_status | Open / Partially Received / Received (as of 22 Nov 2026) |

### po_shipments
| Column | Meaning |
|---|---|
| shipment_id, po_number, parent_sku | Shipment and the PO it belongs to |
| shipped_qty | Units in this shipment |
| ready_at_supplier_date | Goods ready for pick-up at the supplier |
| departure_date | Left origin (vessel / truck) |
| port_arrival_date | Arrived at the Port of Rotterdam |
| warehouse_receipt_date | Received into Warehouse NL |
| shipment_status | In Production / Shipping Soon / In Transit / Received |

Dates that have not happened yet (after 22 Nov 2026) are blank.

## Note

Like any real export, the raw data is not perfectly clean. Data-quality checks are part of each analysis.
