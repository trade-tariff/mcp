# MCP Reporting Tools Design

**Date:** 2026-07-23
**Status:** Approved

## Context

[trade-tariff-backend PR #3559](https://github.com/trade-tariff/trade-tariff-backend/pull/3559) adds five new read-only V2 API endpoints designed for programmatic MCP consumption. All existing MCP tools start from a known commodity code; these new endpoints provide measure-first, quota-first, and change-based lookups across the whole tariff.

This spec describes six new MCP tools to wrap those endpoints (measures/search is split into two tools because `summary` mode returns an entirely different response shape).

## Tools

| Tool name | Endpoint |
|---|---|
| `search_measures` | `GET /{service}/api/v2/measures/search` |
| `summarise_measures` | `GET /{service}/api/v2/measures/search?summary=true` |
| `measure_changes` | `GET /{service}/api/v2/measures/diff` |
| `nomenclature_changes` | `GET /{service}/api/v2/changes_by_period` |
| `quota_utilization` | `GET /{service}/api/v2/quota_order_numbers/:id/utilization` |
| `quota_portfolio` | `GET /{service}/api/v2/quotas/utilization_summary` |

## Architecture

Each tool follows the uniform pattern already established in the codebase:

- `app/tools/*_tool.rb` — `class *Tool < ApplicationTool`
- `app/services/*_shaper.rb` — `class *Shaper < ApplicationShaper`
- Registered in `config/initializers/mcp_server.rb`
- Spec in `spec/tools/*_tool_spec.rb`

## Tool Parameters

### `search_measures`

Wraps the full measure search endpoint. All parameters are optional.

| Parameter | Type | Description |
|---|---|---|
| `measure_type_series` | string[] | Filter by series: A=prohibitions, B=restrictions, C=duties, Q=excise, etc. |
| `measure_type_ids` | string[] | Filter by exact measure type codes |
| `geographical_area_id` | string | Filter by geo area ID; accepts `erga_omnes` as alias for 1011 |
| `has_no_geographical_exclusions` | boolean | Only measures with no country exclusions |
| `has_no_exemption_conditions` | boolean | Only measures with no Y-type certificate conditions |
| `trade_direction` | string | `import` or `export` |
| `commodity_code_prefix` | string | 2–10 digit commodity prefix |
| `regulation_id` | string | Generating regulation ID |
| `measure_condition_codes` | string[] | Condition codes (e.g. `B`, `E`) |
| `has_ad_valorem` | boolean | Only measures with percentage-based duty components |
| `as_of` | string (YYYY-MM-DD) | Date for validity filtering; defaults to today |
| `page` | integer | Page number (default: 1) |
| `per_page` | integer | Results per page (max 100) |
| `service` | string | `uk` (default) or `xi`/`ni` |

### `summarise_measures`

Same 11 filters plus `as_of` and `service`. No `page`/`per_page` — summary mode returns aggregated counts, not records.

### `measure_changes`

| Parameter | Type | Required | Description |
|---|---|---|---|
| `from_date` | string (YYYY-MM-DD) | yes | Start of date range |
| `to_date` | string (YYYY-MM-DD) | no | End of date range; defaults to today |
| `page` | integer | no | Page number |
| `service` | string | no | `uk` (default) or `xi`/`ni` |

### `nomenclature_changes`

Same parameters as `measure_changes`.

### `quota_utilization`

| Parameter | Type | Required | Description |
|---|---|---|---|
| `order_number` | string (6 digits) | yes | Quota order number, e.g. `094011` |
| `from_date` | string (YYYY-MM-DD) | no | Start of utilization period |
| `to_date` | string (YYYY-MM-DD) | no | End of utilization period; defaults to today |
| `service` | string | no | `uk` (default) or `xi`/`ni` |

### `quota_portfolio`

| Parameter | Type | Required | Description |
|---|---|---|---|
| `measurement_unit_code` | string | no | Filter by unit (e.g. `LTR`, `KGM`) |
| `quota_type` | string | no | `Licensed` or `First Come First Served` |
| `page` | integer | no | Page number |
| `service` | string | no | `uk` (default) or `xi`/`ni` |

## Shaper Strategy

| Shaper | Output shape |
|---|---|
| `MeasureSearchShaper` | `{ measures: [...], meta: { pagination } }` — each measure: type, duty, geo_area, conditions, order_number, effective dates, commodity_code |
| `MeasureSummaryShaper` | `{ total_count:, by_series: { A:, B:, C:, ... } }` — pass-through of meta fields |
| `MeasureChangesShaper` | `{ changes: [{ operation:, measure_sid:, type:, duty:, geographical_area:, effective_start_date: }], meta: { from_date:, to_date:, pagination } }` |
| `NomenclatureChangesShaper` | `{ changes: [{ operation:, goods_nomenclature_item_id:, description:, validity_start_date:, validity_end_date: }], meta: { from_date:, to_date:, pagination } }` |
| `QuotaUtilizationShaper` | `{ order_number:, definitions: [{ validity_start_date:, validity_end_date:, initial_volume:, current_balance:, volume_used:, utilization_percentage:, status:, measurement_unit_code:, quota_type:, balance_event_summary: [...] }] }` |
| `QuotaPortfolioShaper` | `{ quotas: [...], meta: { pagination } }` — each quota has the same fields as a definition above |

`MeasureSearchShaper` reuses `ApplicationShaper#shape_conditions` to resolve condition records from the included array. The other shapers are flat enough to not need it.

## Validation

- `from_date` / `to_date`: `validate_date` (format check) + `validate_date_order` (from ≤ to)
- `order_number`: `validate_format` against `/\A\d{6}\z/`
- Invalid `service` values: handled by `ServiceNormaliser` (raises `ArgumentError`, caught by `with_error_handling`)
- All validation is performed before any API call, returning an error response immediately

`validate_date_order` is a private class method in `CommodityHistoryDiffTool`; it will be extracted to `ApplicationTool` so all date-range tools can share it.

## Error Handling

All tools use `with_error_handling` from `ApplicationTool`. No new error types needed — the existing `NotFound`, `RateLimited`, and `ApiError` cases cover all scenarios.

## Testing

One spec per tool in `spec/tools/`. Each spec covers:

- **Happy path**: stubs the relevant API endpoint, calls the tool, asserts expected top-level keys in parsed JSON
- **Missing required param**: returns `error: true` response (for tools with required params)
- **Invalid format**: returns `error: true` response (e.g. `order_number: "short"`)
- **Date order violation**: `from_date` after `to_date` returns `error: true`
- **API 404**: returns error response with not-found message

Fixtures are minimal JSON stubs in `spec/fixtures/api/` with just enough structure to exercise the shaper.

## Registration

Six new tool classes appended to the `tools:` array in `config/initializers/mcp_server.rb`. The existing list is not alphabetical; new tools are appended after `CommodityQuotasTool`.

## Files to Create

```
app/tools/search_measures_tool.rb
app/tools/summarise_measures_tool.rb
app/tools/measure_changes_tool.rb
app/tools/nomenclature_changes_tool.rb
app/tools/quota_utilization_tool.rb
app/tools/quota_portfolio_tool.rb

app/services/measure_search_shaper.rb
app/services/measure_summary_shaper.rb
app/services/measure_changes_shaper.rb
app/services/nomenclature_changes_shaper.rb
app/services/quota_utilization_shaper.rb
app/services/quota_portfolio_shaper.rb

spec/tools/search_measures_tool_spec.rb
spec/tools/summarise_measures_tool_spec.rb
spec/tools/measure_changes_tool_spec.rb
spec/tools/nomenclature_changes_tool_spec.rb
spec/tools/quota_utilization_tool_spec.rb
spec/tools/quota_portfolio_tool_spec.rb

spec/fixtures/api/measure_search.json
spec/fixtures/api/measure_summary.json
spec/fixtures/api/measure_changes.json
spec/fixtures/api/nomenclature_changes.json
spec/fixtures/api/quota_utilization.json
spec/fixtures/api/quota_portfolio.json
```

## Files to Modify

```
app/tools/application_tool.rb          — extract validate_date_order as shared helper
config/initializers/mcp_server.rb      — register six new tools
```
