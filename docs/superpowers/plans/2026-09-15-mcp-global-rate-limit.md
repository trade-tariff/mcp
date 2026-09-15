# MCP Global Rate Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move MCP traffic off per-user DevHub rate limits and onto a single shared 3,000 rpm API Gateway usage plan, with a CloudWatch metric and a Slack alert when we approach that limit.

**Architecture:** The MCP server sends a shared secret in `X-Mcp-Token`. The API Gateway custom authorizer keeps verifying the end user's Hub JWT and keeps returning their real `client_id` as the principal, but returns a shared MCP key as the `usageIdentifierKey` when that header matches — so API Gateway bills the request to a dedicated 50 rps / 3,000 rpm usage plan instead of the user's ~750 rpm one. The MCP server emits its own request and throttle counts via CloudWatch Embedded Metric Format, and two MCP-specific alarms watch them.

**Tech Stack:** Ruby 4.0.5 / Rails (mcp), Node.js 22 + Jest + Serverless Framework (authorizer), Terraform + Terragrunt (infrastructure), AWS API Gateway REST + CloudWatch.

**Spec:** `docs/superpowers/specs/2026-09-15-mcp-global-rate-limit-design.md`

## Global Constraints

- The global MCP limit is **3,000 rpm**, expressed to API Gateway as `rate_limit = 50` (rps) with `burst_limit = 100`. Development deliberately runs a lower limit (5 rps / 10 burst) so the split is provable there, following the precedent set by the `ratelimiting-no-api-key` WAF rule.
- **Metric names:** `McpTariffApiRequests`, `McpTariffApiThrottled`. **Namespace:** `TradeTariffMCP` (the existing MCP-only namespace). **Dimension:** `Service`, valued `uk` or `xi`.
- **Alarm names:** `mcp-tariff-api-approaching-rate-limit-<env>` and `mcp-tariff-api-rate-limited-<env>`. **Usage plan and API key name:** `mcp-<env>`.
- The end user's `client_id` must remain the authorizer's `principalId` and `context.client_id` for every request, MCP or not. Losing per-user attribution is a failure of this work.
- Every environment must fail closed: when a secret is missing or empty, behaviour reverts to today's per-user usage plans rather than erroring.
- Two secret values are shared across repositories and must match exactly:
  - `MCP_SECRET_TOKEN` (mcp app) == `MCP_SECRET_TOKEN` (authorizer) == `TF_VAR_waf_mcp_secret_token` (terraform WAF)
  - `MCP_USAGE_KEY` (authorizer) == `TF_VAR_mcp_usage_plan_key` (terraform API key value)
- Do not change `InstrumentationService`'s existing per-tool metrics or its `PutMetricData` emission. Out of scope.
- **Task order is the rollout order.** Tasks 4–6 (terraform) must be applied before Task 2 (the MCP header) reaches an environment, or MCP will send an unknown usage key. Tasks 1–3 are safe to merge in any order because they are inert until the secret is configured.

---

### Task 1: Emit tariff API metrics via Embedded Metric Format

Creates the metric emitter. Nothing calls it yet — Task 2 wires it in.

CloudWatch parses Embedded Metric Format (EMF) automatically out of any log event whose JSON contains an `_aws` block, so this costs log ingestion only rather than one `PutMetricData` API call per request (~4.3M/day at 3,000 rpm).

**Critical detail:** production configures `ActiveSupport::TaggedLogging` with `config.log_tags = [:request_id]` (`config/environments/production.rb:31-32`), and `BearerTokenMiddleware` adds a `client_id=` tag. Those tags prefix the line and would make the JSON unparseable. This emitter therefore writes to its own plain `$stdout` logger, not `Rails.logger`.

**Files:**
- Create: `app/services/tariff_api_metrics.rb`
- Test: `spec/services/tariff_api_metrics_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `TariffApiMetrics.record_request(service:)` and `TariffApiMetrics.record_throttled(service:)`, both taking a `String` service (`"uk"` or `"xi"`), both returning `nil`, both swallowing every `StandardError`.

- [ ] **Step 1: Write the failing test**

Create `spec/services/tariff_api_metrics_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TariffApiMetrics do
  let(:output) { StringIO.new }

  before do
    described_class.logger = Logger.new(output, formatter: ->(_severity, _time, _progname, msg) { "#{msg}\n" })
  end

  after do
    described_class.logger = nil
  end

  def emitted
    JSON.parse(output.string.lines.last)
  end

  describe ".record_request" do
    it "emits McpTariffApiRequests with a value of 1" do
      described_class.record_request(service: "uk")

      expect(emitted["McpTariffApiRequests"]).to eq(1)
    end

    it "dimensions the metric by service" do
      described_class.record_request(service: "xi")

      expect(emitted["Service"]).to eq("xi")
      expect(emitted.dig("_aws", "CloudWatchMetrics", 0, "Dimensions")).to eq([ [ "Service" ] ])
    end

    it "emits into the TradeTariffMCP namespace" do
      described_class.record_request(service: "uk")

      expect(emitted.dig("_aws", "CloudWatchMetrics", 0, "Namespace")).to eq("TradeTariffMCP")
    end

    it "emits a millisecond timestamp" do
      described_class.record_request(service: "uk")

      expect(emitted.dig("_aws", "Timestamp")).to be_within(60_000).of((Time.now.to_f * 1000).to_i)
    end

    it "emits a single line of JSON" do
      described_class.record_request(service: "uk")

      expect(output.string.lines.length).to eq(1)
    end
  end

  describe ".record_throttled" do
    it "emits McpTariffApiThrottled with a value of 1" do
      described_class.record_throttled(service: "uk")

      expect(emitted["McpTariffApiThrottled"]).to eq(1)
      expect(emitted["McpTariffApiRequests"]).to be_nil
    end
  end

  describe "when writing fails" do
    it "does not raise" do
      broken = instance_double(Logger)
      allow(broken).to receive(:info).and_raise(IOError, "closed stream")
      described_class.logger = broken

      expect { described_class.record_request(service: "uk") }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/tariff_api_metrics_spec.rb`
Expected: FAIL with `uninitialized constant TariffApiMetrics`.

- [ ] **Step 3: Write minimal implementation**

Create `app/services/tariff_api_metrics.rb`:

```ruby
# frozen_string_literal: true

# Emits CloudWatch metrics for outbound tariff API requests using Embedded
# Metric Format: CloudWatch extracts metrics from any log event carrying an
# "_aws" block, so this costs log ingestion rather than one PutMetricData call
# per request.
#
# It deliberately does not use Rails.logger: production wraps that in
# TaggedLogging, and the "[request-id] [client_id=...]" prefix would stop
# CloudWatch parsing the line as JSON.
class TariffApiMetrics
  NAMESPACE = ENV.fetch("MCP_METRICS_NAMESPACE", "TradeTariffMCP")
  REQUESTS_METRIC = "McpTariffApiRequests"
  THROTTLED_METRIC = "McpTariffApiThrottled"

  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new($stdout, formatter: ->(_severity, _time, _progname, msg) { "#{msg}\n" })
    end

    def record_request(service:)
      emit(REQUESTS_METRIC, service)
    end

    def record_throttled(service:)
      emit(THROTTLED_METRIC, service)
    end

    private

    def emit(metric_name, service)
      logger.info(document(metric_name, service).to_json)
      nil
    rescue StandardError
      # metrics must never surface to callers
      nil
    end

    def document(metric_name, service)
      {
        "_aws" => {
          "Timestamp" => (Time.now.to_f * 1000).to_i,
          "CloudWatchMetrics" => [
            {
              "Namespace" => NAMESPACE,
              "Dimensions" => [ [ "Service" ] ],
              "Metrics" => [ { "Name" => metric_name, "Unit" => "Count" } ]
            }
          ]
        },
        "Service" => service,
        metric_name => 1
      }
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/tariff_api_metrics_spec.rb`
Expected: PASS, 7 examples, 0 failures.

- [ ] **Step 5: Run the linter**

Run: `bin/rubocop app/services/tariff_api_metrics.rb spec/services/tariff_api_metrics_spec.rb`
Expected: no offences. Fix any that appear — do not add `rubocop:disable`.

- [ ] **Step 6: Commit**

```bash
git add app/services/tariff_api_metrics.rb spec/services/tariff_api_metrics_spec.rb
git commit -m "HMRC-2699: emit tariff API metrics via embedded metric format

CloudWatch parses EMF out of the log stream, so counting every outbound
request costs log ingestion rather than ~4.3M PutMetricData calls a day at
the 3,000rpm ceiling. It writes to a plain stdout logger because production
tags Rails.logger with the request id, which would break JSON parsing."
```

---

### Task 2: Send `X-Mcp-Token` and count outbound requests

Wires the header and the metrics into the one place all outbound tariff API traffic passes through.

**Files:**
- Modify: `app/services/tariff_client.rb` (the `get`, `post`, `handle_response` and `connection` methods)
- Test: `spec/services/tariff_client_spec.rb`

**Interfaces:**
- Consumes: `TariffApiMetrics.record_request(service:)`, `TariffApiMetrics.record_throttled(service:)` from Task 1.
- Produces: outbound requests carrying `X-Mcp-Token` when `ENV["MCP_SECRET_TOKEN"]` is set. This is the header Task 3's authorizer matches on and the header the existing `allow-mcp-server` WAF rule expects.

- [ ] **Step 1: Write the failing tests**

Add to `spec/services/tariff_client_spec.rb`, inside the top-level `RSpec.describe TariffClient do` block, after the existing `describe "#post"` block:

```ruby
  describe "the X-Mcp-Token header" do
    around do |example|
      original = ENV["MCP_SECRET_TOKEN"]
      example.run
      original.nil? ? ENV.delete("MCP_SECRET_TOKEN") : ENV["MCP_SECRET_TOKEN"] = original
    end

    it "is sent when MCP_SECRET_TOKEN is set" do
      ENV["MCP_SECRET_TOKEN"] = "shared-secret"
      request = stub_request(:get, "#{base_url}/uk/api/v2/sections")
        .with(headers: { "X-Mcp-Token" => "shared-secret" })
        .to_return(status: 200, body: "{}")

      described_class.new(service: "uk").get("/uk/api/v2/sections")

      expect(request).to have_been_requested
    end

    it "is not sent when MCP_SECRET_TOKEN is unset" do
      ENV.delete("MCP_SECRET_TOKEN")
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 200, body: "{}")

      described_class.new(service: "uk").get("/uk/api/v2/sections")

      expect(a_request(:get, "#{base_url}/uk/api/v2/sections")
        .with { |req| req.headers.key?("X-Mcp-Token") }).not_to have_been_made
    end

    it "is not sent when MCP_SECRET_TOKEN is empty" do
      ENV["MCP_SECRET_TOKEN"] = ""
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 200, body: "{}")

      described_class.new(service: "uk").get("/uk/api/v2/sections")

      expect(a_request(:get, "#{base_url}/uk/api/v2/sections")
        .with { |req| req.headers.key?("X-Mcp-Token") }).not_to have_been_made
    end
  end

  describe "metrics" do
    before do
      allow(TariffApiMetrics).to receive(:record_request)
      allow(TariffApiMetrics).to receive(:record_throttled)
    end

    it "records one request per get, dimensioned by service" do
      stub_request(:get, "#{base_url}/xi/api/v2/sections").to_return(status: 200, body: "{}")

      described_class.new(service: "xi").get("/xi/api/v2/sections")

      expect(TariffApiMetrics).to have_received(:record_request).with(service: "xi").once
    end

    it "records one request per post" do
      stub_request(:post, "#{base_url}/uk/api/v2/search").to_return(status: 200, body: "{}")

      described_class.new(service: "uk").post("/uk/api/v2/search", body: { q: "test" })

      expect(TariffApiMetrics).to have_received(:record_request).with(service: "uk").once
    end

    it "records a request even when the API errors" do
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 503, body: "{}")

      expect {
        described_class.new(service: "uk").get("/uk/api/v2/sections")
      }.to raise_error(TariffClient::ApiError)

      expect(TariffApiMetrics).to have_received(:record_request).with(service: "uk").once
    end

    it "records a throttle when the API returns 429" do
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 429, body: "{}")

      expect {
        described_class.new(service: "uk").get("/uk/api/v2/sections")
      }.to raise_error(TariffClient::RateLimited)

      expect(TariffApiMetrics).to have_received(:record_throttled).with(service: "uk").once
    end

    it "does not record a throttle on a successful response" do
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 200, body: "{}")

      described_class.new(service: "uk").get("/uk/api/v2/sections")

      expect(TariffApiMetrics).not_to have_received(:record_throttled)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/tariff_client_spec.rb`
Expected: the new examples FAIL (no `X-Mcp-Token` header sent; `record_request` never received). The pre-existing examples must still pass.

- [ ] **Step 3: Write minimal implementation**

In `app/services/tariff_client.rb`, keep `@service` on the instance, record the request in `get`/`post`, record the throttle in `handle_response`, and add the header in `connection`:

```ruby
  def initialize(service:)
    raise ArgumentError, "Unknown service: #{service}" unless VALID_SERVICES.include?(service)

    @service = service
    @base_url = ENV.fetch("TARIFF_API_URL_#{service.upcase}") { ENV.fetch("TARIFF_API_URL") }
  end

  def get(path, params: {}, as_of: nil)
    TariffApiMetrics.record_request(service: @service)

    response = connection.get(path) do |req|
      req.params.merge!(params)
      req.params["as_of"] = as_of if as_of
    end
    handle_response(response, path)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise ApiError, "Request timed out: #{path} (#{e.message})"
  end

  def post(path, body: {}, as_of: nil)
    TariffApiMetrics.record_request(service: @service)

    response = connection.post(path) do |req|
      req.params["as_of"] = as_of if as_of
      req.headers["Content-Type"] = "application/json"
      req.body = body.to_json
    end
    handle_response(response, path)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise ApiError, "Request timed out: #{path} (#{e.message})"
  end
```

In `handle_response`, the 429 branch becomes:

```ruby
    when 429
      TariffApiMetrics.record_throttled(service: @service)
      raise RateLimited, "Rate limit exceeded — too many requests to the tariff API"
```

In `connection`, after the `Authorization` line:

```ruby
      mcp_token = ENV["MCP_SECRET_TOKEN"].presence
      f.headers["X-Mcp-Token"] = mcp_token if mcp_token
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/tariff_client_spec.rb`
Expected: PASS, all examples.

- [ ] **Step 5: Run the full suite and the linter**

Run: `bundle exec rspec && bin/rubocop`
Expected: all green. Every tool spec exercises `TariffClient`, so a regression here shows up immediately.

- [ ] **Step 6: Document the environment variable**

In `README.md`, add a row to the "Environment Variables" table (currently only `TARIFF_API_URL`):

```markdown
| `MCP_SECRET_TOKEN` | Shared secret sent to the tariff API in `X-Mcp-Token`. Identifies traffic as coming from the MCP server, so API Gateway bills it to the shared MCP usage plan (3,000 rpm) rather than the end user's own. Optional: when unset, requests fall back to the user's per-key limit. | `<from mcp-configuration secret>` |
```

- [ ] **Step 7: Commit**

```bash
git add app/services/tariff_client.rb spec/services/tariff_client_spec.rb README.md
git commit -m "HMRC-2699: identify MCP traffic and count tariff API requests

X-Mcp-Token tells the API Gateway authorizer to bill the request to the
shared MCP usage plan instead of the end user's ~750rpm one, and is the
header the existing allow-mcp-server WAF rule already expects. The metrics
go here rather than in InstrumentationService because API Gateway counts
backend requests, and one tool call can make several.

Absent or empty, the header is not sent and behaviour is unchanged."
```

---

### Task 3: Swap the usage-plan key in the authorizer

Repository: `trade-tariff-lambdas-authenticator` (cloned at `~/code/trade-tariff-lambdas-authenticator`). Work on a branch named `HMRC-2699-mcp-usage-plan`.

`src/authorizer.js` currently ends every successful authorisation with `usageIdentifierKey: clientId`, which is why each Cognito client gets its own usage plan. Only that field changes.

**Files:**
- Modify: `src/authorizer.js` (`buildPolicy`, `logDecision`, `handler`, plus a new `isMcpRequest`)
- Modify: `serverless.yml` (the `provider.environment` block)
- Modify: `.github/bin/deploy` (pass the two new variables through)
- Modify: `.github/workflows/deploy-to-{development,staging,production}.yml` (supply them from secrets)
- Modify: `README.md`
- Test: `__tests__/authorizer.test.js`

**Interfaces:**
- Consumes: the `X-Mcp-Token` header sent by Task 2.
- Produces: for MCP requests, `usageIdentifierKey === process.env.MCP_USAGE_KEY` — the value Task 4 configures as the API key. `principalId` and `context.client_id` keep carrying the end user's Cognito `client_id` in all cases.

- [ ] **Step 1: Write the failing tests**

The existing suite reads env vars at module load and reloads via `loadHandler()` (`__tests__/authorizer.test.js:15-23`), so the new tests set `process.env` before calling it. Add this block to `__tests__/authorizer.test.js`, and extend the existing `createEvent` helper to accept arbitrary headers:

```js
// Replace the existing createEvent helper with this version.
function createEvent({
  authorization,
  headers = {},
  methodArn = "arn:aws:execute-api:eu-west-2:123456789012:apiid/development/GET/uk/api/commodities",
  path = "/uk/api/commodities",
  method = "GET",
} = {}) {
  return {
    type: "REQUEST",
    methodArn,
    path,
    httpMethod: method,
    headers: authorization ? { Authorization: authorization, ...headers } : { ...headers },
  };
}

describe("MCP usage plan", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    jest.clearAllMocks();
    mockVerify.mockReset();
    mockVerify.mockResolvedValue({
      client_id: "test-client",
      scope: "tariff/read",
    });
    process.env = { ...ORIGINAL_ENV, MCP_SECRET_TOKEN: "shared-secret", MCP_USAGE_KEY: "mcp-usage-key" };
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
  });

  it("bills a valid MCP request to the shared MCP usage key", async () => {
    const { handler } = loadHandler();

    const result = await handler(
      createEvent({ authorization: "Bearer token", headers: { "x-mcp-token": "shared-secret" } }),
    );

    expect(result.usageIdentifierKey).toBe("mcp-usage-key");
  });

  it("keeps the end user identifiable on an MCP request", async () => {
    const { handler } = loadHandler();

    const result = await handler(
      createEvent({ authorization: "Bearer token", headers: { "x-mcp-token": "shared-secret" } }),
    );

    expect(result.principalId).toBe("test-client");
    expect(result.context.client_id).toBe("test-client");
  });

  it("accepts the header in canonical casing", async () => {
    const { handler } = loadHandler();

    const result = await handler(
      createEvent({ authorization: "Bearer token", headers: { "X-Mcp-Token": "shared-secret" } }),
    );

    expect(result.usageIdentifierKey).toBe("mcp-usage-key");
  });

  it("logs that the decision was for MCP traffic", async () => {
    const { handler, info } = loadHandler();

    await handler(createEvent({ authorization: "Bearer token", headers: { "x-mcp-token": "shared-secret" } }));

    expect(info).toHaveBeenCalledWith(
      "authorizer decision",
      expect.objectContaining({ mcp: true, client_id: "test-client" }),
    );
  });

  it("bills a request with no MCP header to the client's own key", async () => {
    const { handler } = loadHandler();

    const result = await handler(createEvent({ authorization: "Bearer token" }));

    expect(result.usageIdentifierKey).toBe("test-client");
  });

  it("bills a request with a mismatched MCP token to the client's own key", async () => {
    const { handler } = loadHandler();

    const result = await handler(
      createEvent({ authorization: "Bearer token", headers: { "x-mcp-token": "wrong-secret" } }),
    );

    expect(result.usageIdentifierKey).toBe("test-client");
  });

  it("bills a request with an empty MCP token to the client's own key", async () => {
    const { handler } = loadHandler();

    const result = await handler(
      createEvent({ authorization: "Bearer token", headers: { "x-mcp-token": "" } }),
    );

    expect(result.usageIdentifierKey).toBe("test-client");
  });

  it("falls back to the client's own key when the environment is not configured", async () => {
    process.env = { ...ORIGINAL_ENV };
    delete process.env.MCP_SECRET_TOKEN;
    delete process.env.MCP_USAGE_KEY;
    const { handler } = loadHandler();

    const result = await handler(
      createEvent({ authorization: "Bearer token", headers: { "x-mcp-token": "shared-secret" } }),
    );

    expect(result.usageIdentifierKey).toBe("test-client");
  });

  it("still denies an MCP request whose scope does not cover the path", async () => {
    mockVerify.mockResolvedValue({ client_id: "test-client", scope: "tariff/categorisation" });
    const { handler } = loadHandler();

    const result = await handler(
      createEvent({ authorization: "Bearer token", headers: { "x-mcp-token": "shared-secret" } }),
    );

    expect(result.policyDocument.Statement[0].Effect).toBe("Deny");
  });

  it("still rejects an MCP request with no token at all", async () => {
    const { handler } = loadHandler();

    await expect(handler(createEvent({ headers: { "x-mcp-token": "shared-secret" } }))).rejects.toThrow(
      "Unauthorized",
    );
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `yarn jest __tests__/authorizer.test.js`
Expected: the MCP examples FAIL (`usageIdentifierKey` is `"test-client"` where `"mcp-usage-key"` is expected). Existing examples must still pass — if `createEvent` broke them, fix the helper before continuing.

- [ ] **Step 3: Write minimal implementation**

In `src/authorizer.js`, add `crypto` to the requires at the top:

```js
const crypto = require("node:crypto");
```

Add the constants beside the existing `USER_POOL_ID`:

```js
const MCP_SECRET_TOKEN = process.env.MCP_SECRET_TOKEN;
const MCP_USAGE_KEY = process.env.MCP_USAGE_KEY;
```

Add `isMcpRequest` next to `extractAuthorizationHeader`:

```js
// MCP traffic shares one 3,000rpm usage plan instead of consuming the end
// user's ~750rpm per-key plan (HMRC-2699). The token only selects the plan:
// the JWT is still verified and scope-checked, and the real client_id is still
// returned as the principal.
function isMcpRequest(headers = {}) {
  if (!MCP_SECRET_TOKEN || !MCP_USAGE_KEY) return false;

  const presented = headers["x-mcp-token"] || headers["X-Mcp-Token"];
  if (!presented) return false;

  const presentedBytes = Buffer.from(presented);
  const expectedBytes = Buffer.from(MCP_SECRET_TOKEN);
  if (presentedBytes.length !== expectedBytes.length) return false;

  return crypto.timingSafeEqual(presentedBytes, expectedBytes);
}
```

Change `buildPolicy` to take the flag:

```js
function buildPolicy({ principalId, effect, resource, clientId, mcp }) {
  return {
    principalId,
    policyDocument: {
      Version: "2012-10-17",
      Statement: [
        {
          Action: "execute-api:Invoke",
          Effect: effect,
          Resource: resource,
        },
      ],
    },
    context: {
      client_id: clientId,
    },
    usageIdentifierKey: mcp ? MCP_USAGE_KEY : clientId,
  };
}
```

Add `mcp` to `logDecision`:

```js
function logDecision({ decision, reason, clientId, path, method, mcp }) {
  info("authorizer decision", {
    decision,
    reason,
    client_id: clientId,
    path,
    method,
    mcp,
  });
}
```

In `handler`, after `const effect = ...`, compute the flag once and pass it to both calls:

```js
    const effect = authorised(payload.scope, path) ? "Allow" : "Deny";
    const mcp = isMcpRequest(event.headers);

    logDecision({
      decision: effect.toLowerCase(),
      clientId,
      path,
      method,
      mcp,
    });

    return buildPolicy({
      principalId: clientId,
      effect,
      resource: event.methodArn,
      clientId,
      mcp,
    });
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `yarn test`
Expected: PASS, whole suite.

- [ ] **Step 5: Lint**

Run: `yarn eslint src __tests__`
Expected: no errors.

- [ ] **Step 6: Wire the environment variables through deployment**

In `serverless.yml`, add to `provider.environment`:

```yaml
    MCP_SECRET_TOKEN: ${env:MCP_SECRET_TOKEN, ''}
    MCP_USAGE_KEY: ${env:MCP_USAGE_KEY, ''}
```

The `, ''` defaults matter: an unset variable must deploy cleanly and fall back to per-user plans rather than failing the deploy.

In `.github/bin/deploy`, extend the `deploy` function's environment block (these are secrets, so unlike `USER_POOL_ID` they are *not* hardcoded in the arrays above it):

```bash
  STAGE="$stage" \
  AWS_REGION="eu-west-2" \
  DEPLOYMENT_BUCKET="$bucket" \
  USER_POOL_ID="$user_pool_id" \
  LOG_LEVEL="$log_level" \
  MCP_SECRET_TOKEN="${MCP_SECRET_TOKEN:-}" \
  MCP_USAGE_KEY="${MCP_USAGE_KEY:-}" \
    serverless deploy
```

Note the script runs under `set -o nounset`, which is why both use `${VAR:-}`.

In each of `.github/workflows/deploy-to-development.yml`, `deploy-to-staging.yml` and `deploy-to-production.yml`, add to the `deploy` job:

```yaml
    env:
      MCP_SECRET_TOKEN: ${{ secrets.MCP_SECRET_TOKEN }}
      MCP_USAGE_KEY: ${{ secrets.MCP_USAGE_KEY }}
```

- [ ] **Step 7: Document it**

Add to `README.md`, after the Deployments section:

```markdown
## MCP usage plan

MCP traffic shares a single 3,000rpm API Gateway usage plan rather than consuming each end user's
per-key plan (HMRC-2699). A request presenting `X-Mcp-Token` matching `MCP_SECRET_TOKEN` is billed to
`MCP_USAGE_KEY`; everything else is billed to the caller's Cognito `client_id` as before.

The token only selects the usage plan. The access token is still verified and scope-checked, and the
real `client_id` is still returned as `principalId` and in the policy context, so per-user
attribution is unaffected.

| Variable | Contents |
|---|---|
| `MCP_SECRET_TOKEN` | Shared secret the MCP server sends in `X-Mcp-Token`. Must match `TF_VAR_waf_mcp_secret_token` in the terraform repo and `MCP_SECRET_TOKEN` in the `mcp-configuration` secret. |
| `MCP_USAGE_KEY` | Value of the `mcp-<env>` API Gateway key. Must match `TF_VAR_mcp_usage_plan_key` in the terraform repo. |

Both are supplied from GitHub Actions secrets. If either is unset the swap is disabled and all traffic
uses per-user plans.
```

- [ ] **Step 8: Commit**

```bash
git add src/authorizer.js __tests__/authorizer.test.js serverless.yml .github/bin/deploy .github/workflows README.md
git commit -m "HMRC-2699: bill MCP traffic to a shared usage plan

Returning the caller's client_id as usageIdentifierKey gives every DevHub
key its own ~750rpm plan, which breaks for organisations sharing one key.
A request carrying the MCP shared secret is now billed to a single 3,000rpm
plan instead.

Only the usage key changes: the token is still verified, the scope still
checked, and principalId and context.client_id still carry the real
client_id so per-user attribution survives. Missing configuration falls back
to per-user plans."
```

---

### Task 4: Create the MCP usage plan and API key

Repository: `trade-tariff-terraform` (`~/code/terraform`). Branch `HMRC-2699-mcp-usage-plan`.

This is inert until Task 3 is deployed with a matching `MCP_USAGE_KEY`, so it is safe to apply first — and it must be applied first, because the key must exist before any request references it.

The three environments each hold their own copy of `gateway.tf` with variables declared inline, so this is the same edit three times with different numbers.

**Files:**
- Modify: `environments/development/common/gateway.tf`
- Modify: `environments/staging/common/gateway.tf`
- Modify: `environments/production/common/gateway.tf`
- Modify: `environments/development/common/variables.tf`
- Modify: `environments/staging/common/variables.tf`
- Modify: `environments/production/common/variables.tf`
- Modify: `.github/workflows/deploy-to-development.yml`
- Modify: `.github/workflows/deploy-to-staging.yml`
- Modify: `.github/workflows/deploy-to-production.yml`

**Interfaces:**
- Consumes: `module.gateway.rest_api_id` and `module.gateway.stage_name`, already used by `aws_api_gateway_usage_plan.default`.
- Produces: an API key whose *value* is `var.mcp_usage_plan_key` — the value Task 3's authorizer returns as `usageIdentifierKey`.

- [ ] **Step 1: Add the sensitive variable to each environment**

In each of `environments/{development,staging,production}/common/variables.tf`, next to the existing `waf_mcp_secret_token` declaration:

```hcl
variable "mcp_usage_plan_key" {
  description = "Value of the API Gateway key tied to the shared MCP usage plan. Returned by the authorizer as usageIdentifierKey for requests carrying a valid X-Mcp-Token, so MCP traffic is throttled globally rather than per end user. Empty disables the plan."
  type        = string
  sensitive   = true
  default     = ""
}
```

- [ ] **Step 2: Add the plan, key and join to each environment**

Append to `environments/production/common/gateway.tf` (the throttle variables are declared inline here, matching the `apigw_default_*` pair directly above):

```hcl
############################################
# MCP Usage Plan (HMRC-2699)
############################################

# MCP traffic shares one ceiling instead of consuming each end user's plan:
# DevHub issues a key per developer, which breaks for organisations on a
# corporate setup sharing one key. The authorizer returns
# aws_api_gateway_api_key.mcp's value as the usageIdentifierKey for requests
# presenting a valid X-Mcp-Token, so they land here.
#
# 50 rps x 60 = 3,000 rpm. Tunable: mcp-tariff-api-approaching-rate-limit-<env>
# fires at 80% of it, and the number is meant to be reviewed against real usage.
variable "mcp_rate_limit" {
  description = "Steady-state requests per second for the shared MCP usage plan. 50 rps = 3,000 rpm."
  type        = number
  default     = 50
}

variable "mcp_burst_limit" {
  description = "Burst limit for the shared MCP usage plan."
  type        = number
  default     = 100
}

resource "aws_api_gateway_api_key" "mcp" {
  count       = var.mcp_usage_plan_key != "" ? 1 : 0
  name        = "mcp-${var.environment}"
  description = "Shared key for MCP server traffic (HMRC-2699)"
  value       = var.mcp_usage_plan_key
}

resource "aws_api_gateway_usage_plan" "mcp" {
  count       = var.mcp_usage_plan_key != "" ? 1 : 0
  name        = "mcp-${var.environment}"
  description = "Global rate limit for all MCP server traffic in ${var.environment}"

  throttle_settings {
    burst_limit = var.mcp_burst_limit
    rate_limit  = var.mcp_rate_limit
  }

  api_stages {
    api_id = module.gateway.rest_api_id
    stage  = module.gateway.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "mcp" {
  count         = var.mcp_usage_plan_key != "" ? 1 : 0
  key_id        = aws_api_gateway_api_key.mcp[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.mcp[0].id
}
```

Append the identical block to `environments/staging/common/gateway.tf`.

Append it to `environments/development/common/gateway.tf` too, but with the development defaults — low enough that the split is provable there, the same tactic the `ratelimiting-no-api-key` WAF rule uses (`environments/development/common/waf.tf`):

```hcl
variable "mcp_rate_limit" {
  description = "Steady-state requests per second for the shared MCP usage plan. Deliberately low in development so the shared plan is observably different from the per-user one."
  type        = number
  default     = 5
}

variable "mcp_burst_limit" {
  description = "Burst limit for the shared MCP usage plan."
  type        = number
  default     = 10
}
```

The `count` guards mean an environment without the secret configured plans to zero resources rather than creating a key with an empty value.

- [ ] **Step 3: Supply the secrets from CI**

In each of `.github/workflows/deploy-to-{development,staging,production}.yml`, add to the `env:` block that already carries `TF_VAR_WAF_E2E_SECRET_TOKEN`:

```yaml
      TF_VAR_mcp_usage_plan_key: ${{ secrets.TF_VAR_MCP_USAGE_PLAN_KEY }}
      TF_VAR_waf_mcp_secret_token: ${{ secrets.TF_VAR_WAF_MCP_SECRET_TOKEN }}
```

`waf_mcp_secret_token` has never been supplied by any workflow, so the `allow-mcp-server` WAF rule (`waf.tf`) does not currently exist in any environment. Setting it here brings that dormant rule into existence — intended, and called out in the spec.

- [ ] **Step 4: Validate**

Run, for each environment directory:

```bash
cd ~/code/terraform && terraform fmt -check -recursive environments modules
export DISABLE_INIT=true
cd environments/production/common && terragrunt validate
```

Expected: formatting clean, validation passes.

- [ ] **Step 5: Plan against development to prove it is inert**

Run: `cd ~/code/terraform/environments/development/common && terragrunt plan`
Expected: with `TF_VAR_mcp_usage_plan_key` unset, **no MCP resources appear in the plan** (the `count` guards evaluate to 0). This is the check that an unconfigured environment is untouched. Record the relevant plan lines in the PR description.

- [ ] **Step 6: Commit**

```bash
git add environments/*/common/gateway.tf environments/*/common/variables.tf .github/workflows
git commit -m "HMRC-2699: add a shared MCP usage plan

DevHub gives every Cognito client its own ~750rpm plan, which breaks for
organisations sharing a single corporate key. This adds one plan covering
all MCP traffic at 50rps (3,000rpm), which the authorizer selects for
requests presenting a valid X-Mcp-Token.

Development runs at 5rps so the split is observable there. Both the key and
the plan are guarded on the secret being set, so an environment without it
plans no changes. This also supplies TF_VAR_waf_mcp_secret_token for the
first time, which brings the existing allow-mcp-server WAF rule into being."
```

---

### Task 5: Keep per-user attribution in gateway access logs

Same repository and branch as Task 4.

The access log format records `apiKeyId` and nothing from the authorizer, and the saved Logs Insights query `api-<env>/active-api-keys` groups by it. Once MCP traffic shares one key, every MCP user would collapse into a single consumer row — this is the change that makes a shared key safe.

**Files:**
- Modify: `modules/api-gateway/main.tf:35-45` (the `access_log_settings` format)
- Modify: `modules/api-gateway/logging.tf:19-30` (the `active_api_keys` query definition)
- Test: `modules/api-gateway/tests/access_logs.tftest.hcl` (create)

**Interfaces:**
- Consumes: `context.client_id`, which the authorizer returns for every authorised request (unchanged by Task 3).
- Produces: a `clientId` field in every access log line.

- [ ] **Step 1: Write the failing test**

Create `modules/api-gateway/tests/access_logs.tftest.hcl`, following the provider stanza used by the existing `cache_defaults.tftest.hcl`:

```hcl
provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

run "access_log_format_records_the_end_user_client_id" {
  command = plan

  variables {
    environment               = "test"
    domain_name               = "example.test"
    validated_certificate_arn = "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    zone_id                   = "Z0000000000000000000"
    security_group_ids        = ["sg-00000000000000000"]
    private_subnet_ids        = ["subnet-00000000000000000", "subnet-11111111111111111"]
    lb_arn                    = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/test/0000000000000000"
    alb_secret_header         = ["X-Origin-Secret", "test-secret"]
    access_logging_enabled    = true
    cloudwatch_role_arn       = "arn:aws:iam::123456789012:role/serverlessApiGatewayCloudWatchRole"
  }

  assert {
    condition     = jsondecode(aws_api_gateway_stage.this.access_log_settings[0].format)["clientId"] == "$context.authorizer.client_id"
    error_message = "Access logs must record the authorizer's client_id, so end users stay identifiable once MCP traffic shares one API key."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_stage.this.access_log_settings[0].format)["apiKeyId"] == "$context.identity.apiKeyId"
    error_message = "apiKeyId must still be recorded."
  }
}
```

Check the stage resource's actual name in `modules/api-gateway/main.tf` and use it in the assertions if it differs from `aws_api_gateway_stage.this`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/code/terraform/modules/api-gateway && terraform init -backend=false && terraform test`
Expected: FAIL on the `clientId` assertion.

- [ ] **Step 3: Write minimal implementation**

In `modules/api-gateway/main.tf`, add one line to the format map, after `apiKeyId`:

```hcl
        apiKeyId          = "$context.identity.apiKeyId"
        clientId          = "$context.authorizer.client_id"
```

In `modules/api-gateway/logging.tf`, update the saved query so consumers are counted by end user rather than by key:

```hcl
  query_string = <<-EOT
    fields @timestamp, clientId, apiKeyId, status
    | filter clientId != "-" and clientId != ""
    | stats count(*) as requests by clientId
    | sort requests desc
  EOT
```

MCP requests all share one `apiKeyId` but keep their own `clientId`, which is why the grouping moves.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/code/terraform/modules/api-gateway && terraform test`
Expected: PASS, both the new file and `cache_defaults.tftest.hcl`.

- [ ] **Step 5: Format and validate**

Run: `cd ~/code/terraform && terraform fmt -check -recursive modules/api-gateway`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add modules/api-gateway/main.tf modules/api-gateway/logging.tf modules/api-gateway/tests/access_logs.tftest.hcl
git commit -m "HMRC-2699: record the end user client_id in gateway access logs

Access logs identified callers by apiKeyId, and the active-api-keys query
grouped by it. Once MCP traffic shares a single usage key, every MCP user
would have collapsed into one consumer row.

The authorizer already returns the real client_id in the policy context, so
logging it keeps per-user attribution intact and the query now groups by it."
```

---

### Task 6: Alarm when MCP approaches its global limit

Repository: `mcp`, same branch as Tasks 1–2. Do this last: the alarms reference metrics that only exist once Task 2 is deployed and taking traffic.

**Files:**
- Create: `terraform/alarms.tf`
- Modify: `terraform/variables.tf`
- Modify: `terraform/config_development.tfvars`, `terraform/config_staging.tfvars`, `terraform/config_production.tfvars`

**Interfaces:**
- Consumes: metrics `McpTariffApiRequests` and `McpTariffApiThrottled` in namespace `TradeTariffMCP` from Task 1, and the existing `data.aws_sns_topic.slack_topic` in `terraform/data.tf`.
- Produces: two CloudWatch alarms.

- [ ] **Step 1: Add the variables**

Append to `terraform/variables.tf`:

```hcl
variable "mcp_rate_limit_rpm" {
  description = "The shared MCP usage plan's limit in requests per minute, as configured in the terraform repo's gateway.tf. Used only to derive the alarm threshold and to describe it."
  type        = number
  default     = 3000
}

variable "mcp_rate_limit_alarm_percentage" {
  description = "Percentage of the global MCP rate limit at which the approaching-limit alarm fires."
  type        = number
  default     = 80
}

variable "mcp_rate_limit_alarm_periods" {
  description = "Number of consecutive 60-second periods above the threshold before the approaching-limit alarm fires."
  type        = number
  default     = 5
}
```

- [ ] **Step 2: Add the alarms**

Create `terraform/alarms.tf`:

```hcl
# MCP traffic shares one 3,000rpm API Gateway usage plan rather than consuming
# each end user's per-key limit (HMRC-2699). Nothing else watches that ceiling,
# so these alarms are how we find out it needs reviewing.
locals {
  mcp_rate_limit_alarm_threshold = var.mcp_rate_limit_rpm * var.mcp_rate_limit_alarm_percentage / 100
}

resource "aws_cloudwatch_metric_alarm" "approaching_rate_limit" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "mcp-tariff-api-approaching-rate-limit-${var.environment}"
  alarm_description   = "MCP tariff API requests have exceeded ${var.mcp_rate_limit_alarm_percentage}% of the shared ${var.mcp_rate_limit_rpm}rpm MCP usage plan for ${var.mcp_rate_limit_alarm_periods} consecutive minutes. Review the limit in the terraform repo (environments/${var.environment}/common/gateway.tf, var.mcp_rate_limit)."
  namespace           = "TradeTariffMCP"
  metric_name         = "McpTariffApiRequests"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = var.mcp_rate_limit_alarm_periods
  datapoints_to_alarm = var.mcp_rate_limit_alarm_periods
  threshold           = local.mcp_rate_limit_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [data.aws_sns_topic.slack_topic.arn]
  ok_actions    = [data.aws_sns_topic.slack_topic.arn]
}

resource "aws_cloudwatch_metric_alarm" "rate_limited" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "mcp-tariff-api-rate-limited-${var.environment}"
  alarm_description   = "The tariff API returned 429 to the MCP server. The shared ${var.mcp_rate_limit_rpm}rpm MCP usage plan is exhausted and users are being refused."
  namespace           = "TradeTariffMCP"
  metric_name         = "McpTariffApiThrottled"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [data.aws_sns_topic.slack_topic.arn]
  ok_actions    = [data.aws_sns_topic.slack_topic.arn]
}
```

Both alarms aggregate across every MCP task, because the metric carries only a `Service` dimension and no per-task dimension — which is what a *global* limit needs. `treat_missing_data = "notBreaching"` keeps a quiet environment out of alarm.

- [ ] **Step 3: Set the development limit in tfvars**

Development runs the usage plan at 5 rps (Task 4), so its alarm must match. Add to `terraform/config_development.tfvars`:

```hcl
mcp_rate_limit_rpm = 300
```

`config_staging.tfvars` and `config_production.tfvars` need no entry — the 3,000 default is correct for both.

- [ ] **Step 4: Validate**

Run:

```bash
cd ~/code/mcp/terraform
terraform fmt -check -recursive .
terraform init -backend=false && terraform validate
```

Expected: formatting clean, validation passes.

- [ ] **Step 5: Confirm the threshold arithmetic**

Run: `cd ~/code/mcp/terraform && terraform console` then enter `3000 * 80 / 100`
Expected: `2400` — 2,400 requests in a 60-second period, five periods running. Exit with Ctrl-D.

- [ ] **Step 6: Commit**

```bash
git add terraform/alarms.tf terraform/variables.tf terraform/config_development.tfvars
git commit -m "HMRC-2699: alert when MCP approaches its global rate limit

The shared 3,000rpm MCP usage plan is a number picked without production
data, so it needs watching. One alarm fires at 80% sustained for five
minutes, the other when the API actually returns 429.

Both aggregate across tasks, since the limit is global. Development's
threshold tracks its lower 5rps plan."
```

---

### Task 7: Verify the whole path in development

No code. This is the gate before staging and production, and it is the only place the three repositories are proven to agree on two secrets.

- [ ] **Step 1: Generate and store the secrets**

Generate two distinct values (`openssl rand -hex 32` each) and store them:

| Value | Location |
|---|---|
| MCP secret token | GitHub secret `TF_VAR_WAF_MCP_SECRET_TOKEN` (terraform repo), GitHub secret `MCP_SECRET_TOKEN` (authenticator repo), key `MCP_SECRET_TOKEN` in the `mcp-configuration` Secrets Manager secret |
| MCP usage key | GitHub secret `TF_VAR_MCP_USAGE_PLAN_KEY` (terraform repo), GitHub secret `MCP_USAGE_KEY` (authenticator repo) |

The API key value must be 20–128 characters, which `openssl rand -hex 32` satisfies. The `mcp-configuration` secret is read at task start by `terraform/locals.tf`, so the MCP service needs redeploying (not just restarting) after it changes.

- [ ] **Step 2: Deploy in rollout order**

1. terraform repo → development. Confirm `aws_api_gateway_api_key.mcp[0]`, `aws_api_gateway_usage_plan.mcp[0]` and `aws_api_gateway_usage_plan_key.mcp[0]` are created, and that the access log format now includes `clientId`.
2. authenticator repo → development. Confirm the lambda's configuration shows both new environment variables set.
3. mcp repo → development.

- [ ] **Step 3: Confirm MCP traffic lands on the MCP plan**

Make a tool call through the development MCP server, then check the authorizer log group `/aws/lambda/api-gateway-authorizer-development-authorizer`:

```
fields @timestamp, client_id, mcp, decision
| filter ispresent(mcp)
| sort @timestamp desc
| limit 20
```

Expected: `mcp = true` and a real `client_id` on MCP-originated requests.

- [ ] **Step 4: Confirm end users are still identifiable**

In the access log group `/aws/apigateway/api-development/access-logs`:

```
fields @timestamp, clientId, apiKeyId, path, status
| sort @timestamp desc
| limit 20
```

Expected: `clientId` holds the end user's Cognito client_id; `apiKeyId` is the shared MCP key id. **If `clientId` is `-` or empty on authorised requests, stop** — attribution is broken and Task 5 needs revisiting before this goes further.

- [ ] **Step 5: Confirm the metrics arrive**

In the CloudWatch console, namespace `TradeTariffMCP`: `McpTariffApiRequests` should be non-zero with `Service` dimensions. Then exceed development's deliberately low 5 rps plan (a short burst of tool calls) and confirm `McpTariffApiThrottled` appears and `mcp-tariff-api-rate-limited-development` fires into Slack.

This burst is also the proof that the shared plan is the one being enforced: 5 rps is far below any per-user plan, so being refused at that rate means MCP traffic is on the MCP plan.

- [ ] **Step 6: Record the evidence**

Put the Logs Insights output and the metric graphs into the PR descriptions, and comment the result on HMRC-2699 — including the observed request rate, which is the baseline for deciding whether 3,000 rpm is the right number.

---

## Notes for the reviewer

- **Rollback:** reverting the MCP deploy (Task 2) stops the header, and all traffic returns to per-user plans within one deploy. The usage plan and the authorizer change are both inert without it.
- **Secret rotation:** the MCP secret must be changed in all three places together. During skew, MCP requests fall back to per-user limits — degraded, not broken.
- **The 3,000 rpm number is a guess** made without production data. Task 7 Step 6 captures the real rate, and `var.mcp_rate_limit` plus `var.mcp_rate_limit_rpm` exist so it can be changed without touching code.
