# New Tools Design

**Date:** 2026-06-30
**Status:** Approved

## Overview

Add five new MCP tools to the Trade Tariff MCP server, plus a minor enhancement to `CommodityShaper`. All tools follow the existing one-tool-one-shaper pattern: a `_tool.rb` defines the MCP interface and a `_shaper.rb` shapes the API response into a compact LLM-friendly structure.

## Architecture

Approach: strict one-tool-one-shaper, no shared extraction layer. Each tool is independent and deletable. The three commodity-sourced tools (`commodity_measures`, `duty_vat_calculator`, `commodity_quotas`) each make their own upstream HTTP call rather than sharing a fetcher — the duplication is small and the isolation is worth it.

## Tools

### 1. `commodity_measures`

**Purpose:** Return import and/or export measures for a commodity, without the hierarchy, description, and footnote data that `lookup_commodity` includes. Useful when a caller only needs restrictions, duties, licences, and prohibitions.

**Inputs:**
- `commodity_code` — 10-digit code, required
- `country_code` — optional ISO alpha-2 or geographical area group ID; filters measures to those applicable to that origin/destination
- `direction` — `"import"` | `"export"` | `"both"` (default `"both"`)
- `service`, `validity_date` — standard params

**Backend call:** `GET /api/v2/commodities/:code` with a reduced `include` param covering only `import_measures`, `export_measures`, and their nested measure_type, duty_expression, geographical_area, measure_conditions, order_number trees. No section/chapter/heading/footnotes.

**Shaper:** `CommodityMeasuresShaper`
- Resolves JSONAPI sideloaded relationships
- Filters by `country_code` against geographical_area id/group membership when provided
- Filters by `direction`
- Returns only the fields needed: type description, duty expression, geo area, VAT flag, excise flag, conditions, quota order number

**Output:**
```json
{
  "commodity_code": "0101210000",
  "country_filter": "CN",
  "direction": "import",
  "import_measures": [
    {
      "type": "Third country duty",
      "duty": "12%",
      "geographical_area": { "id": "1011", "description": "ERGA OMNES" },
      "vat": false,
      "excise": false,
      "conditions": [],
      "quota_order_number": null
    }
  ],
  "export_measures": []
}
```

---

### 2. `duty_vat_calculator`

**Purpose:** Return applicable duty rates for a commodity + country, and optionally calculate the duty and VAT amounts when the caller provides a customs value (and quantity for specific duties).

**Inputs:**
- `commodity_code` — 10-digit code, required
- `country_code` — optional; filters to measures applicable to that origin
- `customs_value` — optional numeric, GBP; triggers amount calculation
- `quantity` — optional numeric; required for specific duties (e.g. £1.50/kg)
- `unit` — optional string (e.g. `"kg"`); paired with `quantity`
- `service`, `validity_date` — standard params

**Backend call:** Same endpoint and include params as `commodity_measures`.

**Shaper:** `DutyVatCalculatorShaper`
- Filters measures to those with a duty expression or VAT flag
- For ad-valorem duties (percentage): computes `duty_amount = customs_value × rate` when `customs_value` is present
- For specific duties (e.g. `£1.50/kg`): computes amount when `quantity` + `unit` are present; otherwise returns the rate expression as-is with a note indicating what's needed
- VAT: reported as a flag + 20% applied to `customs_value + duty_amount` when value is present
- When no `customs_value` is provided, returns rates only with no amounts

**Output (with customs value):**
```json
{
  "commodity_code": "0101210000",
  "country": "CN",
  "inputs": { "customs_value": 500.0, "currency": "GBP" },
  "applicable_measures": [
    {
      "type": "Third country duty",
      "rate": "12%",
      "duty_amount": 60.0,
      "basis": "customs value"
    },
    {
      "type": "VAT",
      "rate": "20%",
      "vat_amount": 112.0,
      "basis": "customs value + duty"
    }
  ]
}
```

**Output (rates only, no customs value):**
```json
{
  "commodity_code": "0101210000",
  "country": "CN",
  "inputs": {},
  "applicable_measures": [
    { "type": "Third country duty", "rate": "12%" },
    { "type": "VAT", "rate": "20%" }
  ]
}
```

---

### 3. `commodity_quotas`

**Purpose:** Go directly from a 10-digit commodity code (plus optional origin country) to live quota balances, without requiring the caller to know quota order numbers in advance.

**Inputs:**
- `commodity_code` — 10-digit code, required
- `country_code` — optional; filters to quotas applicable to that origin
- `service`, `validity_date` — standard params

**Backend calls (two-step chain):**
1. `GET /api/v2/commodities/:code` with `include=import_measures,import_measures.order_number,import_measures.geographical_area` — extract quota order numbers from measures that have an `order_number` relationship. If `country_code` provided, filter to measures whose geographical_area matches before extracting order numbers.
2. For each order number: `GET /api/v2/quotas/search?order_number=:num` — collect quota definition and live balance.

**Shaper:** `CommodityQuotasShaper` — merges step 2 results into a flat list using existing `SearchQuotasShaper` logic for each individual quota.

**Output:**
```json
{
  "commodity_code": "0101210000",
  "country_filter": "CN",
  "quotas": [
    {
      "order_number": "094011",
      "description": "Horses for slaughter",
      "balance": 5000.0,
      "initial_volume": 10000.0,
      "status": "not_critical",
      "measurement_unit": "KGM",
      "validity_start_date": "2024-01-01",
      "validity_end_date": "2024-12-31",
      "geographical_areas": [{ "id": "CN", "description": "China" }]
    }
  ]
}
```

If no quotas are found for the commodity (or country filter), return `{ "commodity_code": "…", "quotas": [] }` with a message indicating no quota relief applies.

`search_quotas` is unchanged — `commodity_quotas` is the ergonomic entry point for callers who have a commodity code; `search_quotas` remains for callers who already have an order number or need pagination/date filtering.

---

### 4. `commodity_history_diff`

**Purpose:** Show what changed for a specific commodity between two dates — measures added/removed, duty rate changes.

**Inputs:**
- `commodity_code` — 10-digit code, required
- `from_date` — YYYY-MM-DD, required
- `to_date` — YYYY-MM-DD, optional; defaults to today
- `service`

**Backend calls:** The commodity endpoint twice — once with `as_of: from_date`, once with `as_of: to_date` — using the same include params as `commodity_measures`. No new backend endpoint required.

**Shaper:** `CommodityHistoryDiffShaper`
- Shapes each response into a normalised measure set
- Keys measures for comparison by `[measure_type_description, geographical_area_id, order_number]`
- Produces three lists: measures_added, measures_removed, duty_changes
- Duty changes: same key, different duty expression
- When both dates return identical data, states this explicitly rather than returning empty arrays

**Output:**
```json
{
  "commodity_code": "0101210000",
  "from_date": "2024-01-01",
  "to_date": "2025-01-01",
  "changes": {
    "measures_added": [],
    "measures_removed": [
      { "type": "Tariff preference", "duty": "0%", "geographical_area": "EU", "removed_on": "2024-01-01" }
    ],
    "duty_changes": [
      {
        "type": "Third country duty",
        "geographical_area": "ERGA OMNES",
        "from": "12%",
        "to": "8%"
      }
    ]
  },
  "unchanged_measure_count": 14
}
```

---

### 5. `full_text_search`

**Purpose:** Keyword search across commodity descriptions and/or chapter/section legal notes text. Complements `classification_search` (which is semantic/vector-based) with exact keyword matching.

**Inputs:**
- `query` — string, required
- `search_type` — `"notes"` | `"descriptions"` | `"all"` (default `"all"`)
- `service`, `validity_date` — standard params

**Backend endpoint:** Needs verification before implementation. The frontend exposes keyword search; the backend likely exposes `/api/v2/search?q=:query` and possibly a separate notes search endpoint. Implementation task must begin with endpoint discovery (check backend routes, API docs, or inspect frontend network calls).

Fallback if no unified endpoint exists: two separate calls — one for descriptions, one for notes — merged by the shaper and labelled by kind.

**Shaper:** `FullTextSearchShaper`
- Normalises results from one or two endpoints into a unified result list
- Each result tagged with `kind: "commodity"` or `kind: "note"`
- Commodity results: code + description
- Note results: source (e.g. "Chapter 84"), excerpt with query term in context, hierarchy path

**Output:**
```json
{
  "query": "hydraulic",
  "search_type": "all",
  "results": [
    { "kind": "commodity", "code": "8412210000", "description": "Hydraulic power engines and motors, linear acting (cylinders)" },
    { "kind": "note", "source": "Chapter 84", "excerpt": "…parts of hydraulic equipment…", "path": "/chapters/84" }
  ]
}
```

**Implementation note:** Mark as "verify backend endpoint first" — if no suitable endpoint exists, descope to descriptions-only search and file a follow-up to add notes search.

---

## Minor Enhancement: `CommodityShaper`

Add `bti_url` to the shaped commodity output. This field is already present in the API response but currently dropped by the shaper. Surfacing it allows LLM clients to direct users to the GOV.UK binding tariff ruling guidance when relevant.

No new tool required — this is a one-line addition to `CommodityShaper#call`.

---

## Testing

Each tool follows the existing spec pattern:
- `spec/tools/<name>_tool_spec.rb` — stubs `TariffClient`, tests input validation, service normalisation, error handling
- `spec/services/<name>_shaper_spec.rb` — unit tests with fixture JSON, tests field extraction, filtering logic, edge cases (empty measures, missing relationships, identical snapshots for diff tool)

`commodity_quotas` requires two stubs per test (commodity fetch + quota search per order number). `commodity_history_diff` requires two commodity stubs per test (from_date + to_date).

Target: same coverage level as existing tools (~90%+ on shapers, happy path + key error paths on tools).

---

## What Is Not In Scope

- Changes to existing tool interfaces or shapers (except `CommodityShaper` `bti_url` addition)
- A `bti_lookup` tool — the API only exposes a static `bti_url` guidance link, not a BTI record database
- Pagination on `commodity_quotas` — if a commodity has many quotas the two-step chain may make multiple calls; acceptable for now, revisit if performance is a concern
- Caching or batching of the two-step quota chain
