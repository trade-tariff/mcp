# Trade Tariff MCP Server

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that exposes UK Trade Tariff commodity lookup as tools for AI clients. It wraps the [GOV.UK Online Trade Tariff](https://www.trade-tariff.service.gov.uk) backend API.

Implements MCP 2025-11-25 (streamable HTTP transport).

## Tools

| Tool | Description |
|------|-------------|
| `list_sections` | List all top-level sections of the tariff |
| `show_chapter` | Show a chapter by 2-digit ID (e.g. `01`) |
| `show_heading` | Show a heading by 4-digit code (e.g. `0101`) |
| `lookup_commodity` | Look up a commodity by 10-digit code (e.g. `0101210000`) |
| `search_commodities` | Search by keyword (e.g. `"live horses"`) |
| `navigate_hierarchy` | Look up any goods nomenclature entry by 4–10 digit code |

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

## Requirements

- Ruby 4.0.5
- `TARIFF_API_URL` — base URL for the tariff API (both UK and XI services are served from the same host)

## Setup

```bash
bundle install
cp .env.example .env
# Edit .env with the correct API URL
```

## Running

```bash
bundle exec rails server
```

The MCP endpoint is available at `http://localhost:3000/mcp`.

## Connecting to Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "trade-tariff": {
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

## Testing with MCP Inspector

```bash
npx @modelcontextprotocol/inspector http://localhost:3000/mcp
```

## Tests

```bash
bundle exec rspec
```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `TARIFF_API_URL` | Base URL for the tariff backend | `https://www.trade-tariff.service.gov.uk` |

Required at startup in non-test environments.
