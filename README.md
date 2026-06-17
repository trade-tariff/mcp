# Trade Tariff MCP Server

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that exposes UK Trade Tariff commodity lookup as tools for AI clients. It wraps the [GOV.UK Online Trade Tariff](https://www.trade-tariff.service.gov.uk) backend API.

Implements MCP 2025-11-25 (streamable HTTP transport).

## Connecting to Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "trade-tariff": {
      "url": "https://mcp.trade-tariff.service.gov.uk/",
      "headers": {
        "Authorization": "Bearer <your-api-token>"
      }
    }
  }
}
```

A bearer token is required on every request — see [Authentication](#authentication).

## Tools

| Tool | Description |
|------|-------------|
| `list_sections` | List all top-level sections of the tariff |
| `show_chapter` | Show a chapter by 2-digit ID (e.g. `01`) |
| `show_heading` | Show a heading by 4-digit code (e.g. `0101`) |
| `lookup_commodity` | Look up a commodity by 10-digit code (e.g. `0101210000`) |
| `search_commodities` | Search by keyword (e.g. `"live horses"`) |
| `navigate_hierarchy` | Look up any goods nomenclature entry by 4–10 digit code |
| `list_exchange_rates` | List GBP monetary exchange rates used in duty calculations |
| `list_geographical_areas` | List all countries and country groups (use to find country codes) |
| `search_quotas` | Search quota definitions to check quota relief eligibility and balances |
| `search_additional_codes` | Search additional codes (e.g. Meursing codes for agricultural goods) |
| `list_certificate_types` | List all certificate and licence types required by measures |
| `rules_of_origin` | Get rules of origin schemes for a heading and country combination |

All tools accept these optional parameters:

| Parameter | Description |
|-----------|-------------|
| `service` | Which tariff to query (see below). Defaults to `uk`. |
| `validity_date` | Return data as it appeared on this date (`YYYY-MM-DD`). Defaults to today. |

**Service values:**

| Value | Tariff served |
|-------|--------------|
| `uk`, `gb`, `great britain`, `united kingdom` (default) | Great Britain |
| `xi`, `ni`, `northern ireland`, `northern_ireland` | Northern Ireland |

Unrecognised service values return an error rather than silently defaulting.

## Authentication

Clients must pass a bearer token on every request:

```
Authorization: Bearer <your-api-token>
```

The token is forwarded as-is to the tariff backend API. Requests without a token receive a `401 Unauthorized` response.

In the development environment the bearer token requirement is skipped — no `Authorization` header is needed when running locally.

## Development

### Requirements

- Ruby 4.0.5
- `TARIFF_API_URL` — base URL for the tariff API (both UK and XI services are served from the same host)

### Setup

```bash
bundle install
cp .env.example .env
# Edit .env with the correct API URL
```

### Running

```bash
bundle exec rails server
```

The MCP endpoint is available at `http://localhost:3000/` locally.

### Tests

```bash
bundle exec rspec
```

### Testing with MCP Inspector

```bash
npx @modelcontextprotocol/inspector https://mcp.trade-tariff.service.gov.uk/
```

<img width="801" height="615" alt="Screenshot 2026-06-16 at 16 22 51" src="https://github.com/user-attachments/assets/91a770e6-ca18-4260-afd7-28112c27233b" />

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `TARIFF_API_URL` | Base URL for the tariff backend | `https://www.trade-tariff.service.gov.uk` |

Required at startup in non-test environments.
