## What:
<!-- A brief description of what this PR does -->

## Why:
<!-- The reasoning or context behind this change -->

## Ticket:
<!-- Link to the relevant Jira/ticket, or 'N/A' if not applicable -->

## Risk:
**Risk level:** 🟢 / 🟠 / 🔴 <!-- delete as appropriate -->

**Reason for rating:**
<!-- One or two sentences explaining your assessment, especially for Amber or Red -->

───────────────────────────────────────────────────

Rate the overall risk of deploying this change:

🟢 Green  – Low risk. Good to go, standard review applies.

🟠 Amber  – Medium risk. Socialise with the team before merging.

🔴 Red    – High risk. Requires explicit approval from Thor or Neil before merging.

───────────────────────────────────────────────────

🟢 GREEN – things that are typically low risk:
───────────────────────────────────────────────────
- Dependency bumps with no API changes (e.g. minor/patch gems)
- Adding or updating tools with no behaviour change to existing ones
- New tests or improved test coverage with no production code changes
- Config/env var additions that are purely additive and have safe defaults
- Refactors with full test coverage and no behaviour change

🟠 AMBER – things that need a team conversation first:
───────────────────────────────────────────────────
- Changes to tool output format or response structure
- Adding or changing feature flags that affect live user journeys
- Infrastructure changes that alter networking, security groups, or IAM permissions
- Changes to CI/CD pipeline steps or deployment order dependencies

🔴 RED – requires explicit approval from Thor or Neil:
───────────────────────────────────────────────────
- Changes to how the MCP server authenticates or authorises requests
- Secrets rotation or changes to how credentials are stored or accessed
- Significant architectural shifts (e.g. new transport layer, session handling)
