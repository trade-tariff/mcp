# MCP Global Rate Limit Design

**Date:** 2026-09-15
**Status:** Approved
**Ticket:** [HMRC-2699](https://transformuk.atlassian.net/browse/HMRC-2699)

## Context

DevHub issues each developer a Hub (Cognito) client_id/client_secret. The API Gateway custom
authorizer (`trade-tariff-lambdas-authenticator`) verifies the access token and returns
`usageIdentifierKey: clientId`, so API Gateway applies that client's usage plan. The default plan
(`terraform/environments/<env>/common/gateway.tf`) throttles at 13 rps / 25 burst — roughly 750–780
requests per minute per key.

That model assumes one key per developer. It breaks for an organisation on a corporate setup, where
many people share a single key and collectively blow through 750 rpm. Per-organisation keys and
limits would solve it properly, but are a substantial piece of work.

For MCP we take the cheaper route: MCP traffic still requires a valid Hub key (so requests stay
authenticated, scope-checked and attributable), but it no longer consumes the *user's* per-key
throttle. Instead all MCP traffic shares one global ceiling of 3,000 rpm, with a metric and an alert
when we approach it, so we can review the number against real usage.

## Current behaviour

- `mcp` forwards the end user's Hub JWT to the tariff API as `Authorization: Bearer …`
  (`app/services/tariff_client.rb`). MCP sends no other identifying header.
- `modules/api-gateway/main.tf` sets `api_key_source = "AUTHORIZER"` and `api_key_required = true`
  on every method, so the authorizer's `usageIdentifierKey` selects the usage plan.
- `src/authorizer.js` builds the policy with `principalId`, `context.client_id` and
  `usageIdentifierKey` all set to the token's `client_id`.
- `MCP_SECRET_TOKEN` exists in `mcp/.env.example` and `waf_mcp_secret_token` exists in the terraform
  environments, but **neither is wired up**: no `TF_VAR_waf_mcp_secret_token` is set by any
  workflow, so the `allow-mcp-server` WAF rule is not created in any environment, and the MCP code
  never sends the header. This work does that plumbing.

## Design

Five changes across three repositories.

### 1. MCP identifies itself — `mcp`

`TariffClient#connection` sets `X-Mcp-Token` from `ENV["MCP_SECRET_TOKEN"]` when that variable is
present, alongside the existing `Accept` and `Authorization` headers. When the variable is absent
(local development, tests) no header is sent and behaviour is unchanged.

This is the same header and the same secret the WAF rule already anticipates. One secret means "this
request came from the MCP server", used by both the WAF bypass and the usage-plan swap.

### 2. Authorizer swaps the usage-plan key — `trade-tariff-lambdas-authenticator`

`buildPolicy` takes an additional flag and sets:

```js
usageIdentifierKey: isMcpRequest ? MCP_USAGE_KEY : clientId
```

`isMcpRequest(headers)` does a timing-safe comparison of the `x-mcp-token` header against
`process.env.MCP_SECRET_TOKEN`, and returns `false` if either value is empty. An environment where
the secret is not configured therefore fails closed to the existing per-user behaviour.

Everything else is untouched: the JWT is still verified, `authorised(scope, path)` still decides
Allow/Deny, and `principalId` / `context.client_id` still carry the real end-user client_id. A valid
Hub key remains mandatory — it simply no longer selects the plan.

`logDecision` gains an `mcp` boolean so the split is visible in the authorizer logs.

Two new environment variables, added to `serverless.yml` and `.github/bin/deploy`:

| Variable | Contents |
|---|---|
| `MCP_SECRET_TOKEN` | The shared secret MCP sends in `X-Mcp-Token` |
| `MCP_USAGE_KEY` | The API key value tied to the MCP usage plan |

Both are secret, so unlike `USER_POOL_ID` they cannot be hardcoded in the deploy script: they come
from GitHub Actions secrets and are passed into the deploy as environment variables.

Prod runs `authorizer_result_ttl_in_seconds = 0`, so there is no cached policy to go stale when a
request's MCP status differs from the previous one on the same token.

### 3. Dedicated MCP usage plan — `terraform/environments/<env>/common/gateway.tf`

Alongside the existing `standard-<env>` plan:

| Resource | Value |
|---|---|
| `aws_api_gateway_api_key.mcp` | name `mcp-<env>`, value `var.mcp_usage_plan_key` (sensitive) |
| `aws_api_gateway_usage_plan.mcp` | name `mcp-<env>`, `rate_limit = var.mcp_rate_limit`, `burst_limit = var.mcp_burst_limit`, bound to the same API stage |
| `aws_api_gateway_usage_plan_key.mcp` | joins the key to the plan |

`mcp_rate_limit` defaults to 50 rps (50 × 60 = 3,000 rpm) and `mcp_burst_limit` to 100. Both are
variables so the limit can be tuned from the tfvars once we have seen real traffic — which is the
point of the metric below.

`mcp_usage_plan_key` is fed by `TF_VAR_mcp_usage_plan_key` from a GitHub Actions secret, and must
match `MCP_USAGE_KEY` in the authorizer. `waf_mcp_secret_token` gains the same treatment via
`TF_VAR_waf_mcp_secret_token`, matching `MCP_SECRET_TOKEN` in both the authorizer and the
`mcp-configuration` secret.

### 4. Metric and near-exhaustion alert — `mcp`

API Gateway counts *backend API requests*, and one MCP tool call can make several. The metric must
therefore be emitted in `TariffClient`, where the outbound calls happen, not in
`InstrumentationService`'s per-tool hook.

| Metric | Emitted |
|---|---|
| `McpTariffApiRequests` | Once per outbound tariff API request, dimensioned by `Service` (`uk`/`xi`) |
| `McpTariffApiThrottled` | When the API returns 429 (the `RateLimited` branch of `handle_response`) |

Both sit in the existing `TradeTariffMCP` namespace, which is MCP-only, so they cannot be confused
with general tariff traffic.

**Emission method:** CloudWatch Embedded Metric Format — a structured log line to the existing
`platform-logs-<env>` group, which CloudWatch parses into metrics automatically. The existing
`InstrumentationService.emit` makes one `PutMetricData` API call per event; at 3,000 rpm that would
be roughly 4.3 million API calls a day and a needless CloudWatch bill. EMF costs log ingestion only
and needs no new infrastructure. `InstrumentationService`'s existing per-tool metrics are left as
they are — tool calls are far lower volume, and changing them is not this ticket.

Alarms live in `mcp/terraform` and notify the existing `slack-topic` SNS topic:

| Alarm | Condition |
|---|---|
| `mcp-tariff-api-approaching-rate-limit-<env>` | `McpTariffApiRequests` sum > 2,400 in a 60s period, for 5 consecutive periods (80% of 3,000 rpm sustained for 5 minutes) |
| `mcp-tariff-api-rate-limited-<env>` | `McpTariffApiThrottled` >= 1 in a period |

Both alarm descriptions state the 3,000 rpm global MCP limit explicitly, so the Slack notification is
actionable without opening the console. The threshold and evaluation period are terraform variables.

### 5. Preserve per-user attribution in access logs — `terraform/modules/api-gateway`

The access log format records `apiKeyId` and not the authorizer context, and the saved Logs Insights
query `api-<env>/active-api-keys` counts requests by `apiKeyId`. Once MCP traffic shares one key,
every MCP user would collapse into a single consumer row.

The log format gains `clientId = "$context.authorizer.client_id"`. The authorizer already returns
that context value and keeps returning the true per-user client_id for MCP requests, so attribution
survives the key swap. The `active-api-keys` query groups by `clientId`, falling back to `apiKeyId`
for the unauthenticated paths where no authorizer ran.

This touches the shared module and so affects every consumer of it. The change is additive to the log
line, and it is what makes a shared usage key safe.

## What is deliberately not in scope

- **Per-organisation keys and limits.** The complex option this ticket explicitly defers.
- **Changing `InstrumentationService`'s emission method.** Noted above; separate concern.
- **Enabling the `allow-mcp-server` WAF rule's behaviour beyond wiring its secret.** Setting
  `TF_VAR_waf_mcp_secret_token` will bring the existing rule into existence; that is a consequence of
  the secret plumbing, not a new rule.

## Error handling

- Missing or empty `MCP_SECRET_TOKEN` in the authorizer: `isMcpRequest` returns `false`, traffic uses
  per-user plans. Fails closed, no error.
- Missing `MCP_SECRET_TOKEN` in the MCP app: no header sent, traffic uses per-user plans. Same
  behaviour as today.
- Mismatched secret (rotation skew): MCP requests fall back to the user's per-user plan until the two
  sides agree. Degraded, not broken.
- EMF log write failure: log emission is best-effort and must never surface to the caller, matching
  the existing `InstrumentationService.emit` rescue.
- Gateway 429 despite the global plan: surfaces to the user as today's `RateLimited` message, and now
  also fires the `mcp-tariff-api-rate-limited-<env>` alarm.

## Testing

**`mcp` (RSpec):**
- `X-Mcp-Token` is sent when `MCP_SECRET_TOKEN` is set; not sent when it is unset.
- `McpTariffApiRequests` is emitted once per `get` and per `post`, with the correct `Service`
  dimension.
- `McpTariffApiThrottled` is emitted on a 429 and not on 200/404/500.
- Metric emission failures do not raise.

**`trade-tariff-lambdas-authenticator` (Jest):**
- Valid MCP token → `usageIdentifierKey` is `MCP_USAGE_KEY`; `principalId` and `context.client_id`
  remain the user's client_id.
- Absent, empty or mismatched `x-mcp-token` → `usageIdentifierKey` is the client_id.
- `MCP_SECRET_TOKEN` unset in the environment → always the client_id, even if a header is present.
- Header casing (`X-Mcp-Token` / `x-mcp-token`) is handled.
- Existing deny, missing-header and bad-token paths are unchanged.

**`terraform`:** module tests in the `modules/waf` `.tftest.hcl` style, asserting the MCP usage plan's
rate and burst limits, that the key is attached to the plan, and that the access log format includes
`clientId`.

## Rollout order

Order matters — deploying the MCP header before the plan exists would send requests carrying an
unknown usage key.

1. **terraform** — MCP API key, usage plan, access log `clientId`. Nothing references the key yet, so
   this is inert.
2. **authenticator** — deploy with `MCP_SECRET_TOKEN` and `MCP_USAGE_KEY` set. Still inert: no
   request presents the header yet.
3. **mcp** — `X-Mcp-Token` plus the metrics. MCP traffic moves onto the global plan at this point.
4. **mcp/terraform** — alarms, once the metrics are producing data.

Each step is independently revertible, and rolling back step 3 returns MCP to per-user plans.

## Files

**`mcp`:**
- Modify `app/services/tariff_client.rb` — header, two metrics
- Modify `spec/services/tariff_client_spec.rb` (or add, if absent)
- Modify `README.md` — document `MCP_SECRET_TOKEN`
- Modify `terraform/main.tf` (or add `terraform/alarms.tf`) — two alarms
- Modify `terraform/variables.tf` — alarm threshold and period variables

**`trade-tariff-lambdas-authenticator`:**
- Modify `src/authorizer.js` — `isMcpRequest`, `buildPolicy`, `logDecision`
- Modify `__tests__/authorizer.test.js`
- Modify `serverless.yml` — two environment variables
- Modify `.github/bin/deploy` — pass them through
- Modify the three deploy workflows — supply the GitHub secrets
- Modify `README.md`

**`terraform`:**
- Modify `environments/{development,staging,production}/common/gateway.tf` — key, plan, plan key
- Modify `environments/{development,staging,production}/common/variables.tf` — `mcp_usage_plan_key`,
  `mcp_rate_limit`, `mcp_burst_limit`
- Modify `modules/api-gateway/main.tf` — access log `clientId`
- Modify `modules/api-gateway/logging.tf` — `active-api-keys` query
- Modify the deploy workflows — `TF_VAR_mcp_usage_plan_key`, `TF_VAR_waf_mcp_secret_token`
- Add module tests
