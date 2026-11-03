# SRE Agent deployment (platform operations agent)

This folder deploys **one** Azure SRE Agent for platform operations, following the topology guidance in `..\..\agent-topology.md`: one agent, use cases as custom agents, and split only when a trigger (A1–A7) applies. It is based on the official templates at [microsoft/sre-agent](https://github.com/microsoft/sre-agent).

| File | Purpose |
| --- | --- |
| `main.bicep` | Subscription scope. Creates the resource group, the agent module, and **Reader** on the subscription for the agent's identities. |
| `agent.bicep` | Creates the Log Analytics workspace, workspace-based App Insights, a user-assigned managed identity and `Microsoft.App/agents`. Sets **Azure Monitor as the incident platform** and creates the **connectors**: `azure-monitor` plus one `LogAnalytics` connector per existing workspace. Also assigns **SRE Agent Administrator** to the deployer. |
| `main.bicepparam` | Agent name, RG, region, monthly AAU cap, model provider, incident platform and the workspaces to connect. |
| `event-alerts.bicep`, `event-alerts.json` | Opt-in Activity Log starter rules and typed metric/log alert deployment. Requires existing human on-call action groups; rules are staged disabled by default. |
| `event-alerts.example.bicepparam` | Copyable resource-group deployment example: Activity Log rules, a storage metric, AKS scheduling errors and an independently registered missing-heartbeat source. Replace placeholders and validate telemetry first. |
| `dataplane\subagents.json` | 13 read-only custom agents: `platform-orchestrator` (UC04, UC12), 7 domain specialists (UC01–UC11) and 5 WAF pillar agents (W1–W5). |
| `dataplane\scheduled-tasks.json` | 8 scheduled tasks, all in **Review** mode. |
| `dataplane\response-plans.json` | 8 response plans (incident filters) that route Azure Monitor alerts to the right custom agent, all in **Review** mode. |
| `dataplane\event-response-plans.json` | 17 opt-in, title-token Review routes for W1-W5 and UC01-UC12. Each source rule must match exactly one route. |
| `dataplane\Apply-DataPlane.ps1` | Idempotent apply of custom agents, persisted schedule flags, selected response-plan set and 5 knowledge files (use cases, WAF pillars, topology, event triggers, queries). Guards migration and explicit rollback. |

## Connectors

| Connector | Source | Created by |
| --- | --- | --- |
| `law`, `appinsights` | The agent's own workspace and App Insights | The platform, automatically (from `logConfiguration`) |
| `azure-monitor` | Alerts in the subscription (7-day look-back) | `agent.bicep` |
| `law-<workspace>` | Each ID in `logAnalyticsWorkspaceIds`: the ALZ management workspace (AMBA, Activity Log) and the AKS / Container insights workspace | `agent.bicep` |

Both the ARM and the data-plane APIs mask the connector targets on read. Check them in the portal (**Builder > Connectors**), and test with a query such as `Heartbeat | take 1` against each workspace.

## Response plans (Azure Monitor, Review mode)

| Plan | Match | Custom agent | Use case |
| --- | --- | --- | --- |
| `rp-service-health` | Title contains `ServiceHealth` | platform-orchestrator | UC04 |
| `rp-resource-health` | Title contains `ResourceHealth` | waf-reliability | W1 |
| `rp-aks-platform` | `Microsoft.ContainerService/managedClusters` | aks-platform | UC08 |
| `rp-ai-platform` | `Microsoft.CognitiveServices/accounts` | ai-platform | UC07 |
| `rp-network-firewall` | `Microsoft.Network/azureFirewalls` | network | UC03 |
| `rp-network-gateways` | `Microsoft.Network/virtualNetworkGateways` | network | UC03 |
| `rp-backup` | `Microsoft.RecoveryServices/vaults` | resilience | UC10 |
| `rp-log-analytics` | `Microsoft.OperationalInsights/workspaces` | observability | UC05 |

All plans cover Sev0–Sev4, merge related alerts within 1 hour, and allow at most 2 automated investigation attempts, which limits AAU use.

- **No catch-all plan.** The documentation doesn't say which plan wins when several match, and overlapping plans can investigate the same alert twice. Alerts that match no plan are not investigated automatically. Add a catch-all only once you have tested the routing.
- **Known overlap:** a Resource Health alert on an AKS cluster can match both `rp-resource-health` and `rp-aks-platform`.
- **Quickstart plan:** connecting an incident platform in the portal creates a default **quickstart** plan, which can double-route incidents. The apply script warns about any plan it doesn't manage. Delete these in **Builder > Incident response plans**.
- Titles are matched against the alert rule names, which here are the AMBA defaults. Adjust `titleContains` if your AMBA naming differs.
- `deepInvestigationEnabled`, which the template recipes still use, is rejected by the current API, so the kit omits it.

## Design choices

- **Region:** Sweden Central. `Microsoft.App/agents` is not available in West Europe. Sweden Central is in the cheapest EU price tier: EUR 282.66/month always-on (2,920 AAU), the same as Poland Central, France Central, UK South and Italy North. It is also co-located with the existing management and AMBA resources. Prices come from the Retail Prices API on 20-10-2026.
- **Cost guardrail:** active flow is capped at 2,000 AAU/month (about EUR 194). The maximum is about EUR 477/month.
- **Access:** the Bicep assigns only subscription **Reader** and no Contributor. The action configuration is `Low` / `Review`. **Check the effective roles after setup:** setting Azure Monitor as the incident platform can add **Monitoring Contributor** on the subscription to the user-assigned identity, under the deploying user's account. That happened in the reference sandbox. Monitoring Contributor lets the agent acknowledge and close alerts and edit alert rules and diagnostic settings. Keep it only if alert intake requires it, record it as an access change, or replace it with a custom role limited to `Microsoft.AlertsManagement/alerts/*`.
- **Log data access (accepted residual risk):** subscription Reader (`*/read`) also lets the agent query all log data in **every** workspace in the subscription, not only the connected ones. It overrides table-level access control ([Manage access to Log Analytics workspaces](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/manage-access)). A separate Log Analytics Reader assignment is therefore redundant, and the kit does not create one. Adding a Log Analytics connector in the portal may still auto-assign it. **Hardening path:** replace Reader with a custom role that keeps `*/read` but adds `NotActions` for `Microsoft.OperationalInsights/workspaces/query/read`, `Microsoft.OperationalInsights/workspaces/query/*/read` and `Microsoft.Insights/logs/*/read`. Then grant Log Analytics Reader on the connected workspaces only, and prove the result with a negative query test against a workspace outside the list.
- **Model:** the `MicrosoftFoundry` provider, chosen for EU Data Boundary alignment.
- **Hand-offs:** agent-to-agent hand-offs are **not supported in workspace mode**. The data-plane API rejects them, so `platform-orchestrator` delegates to the specialists as Task-based subagents instead.

## Legacy scheduled tasks (UTC, Review mode)

**Replacement design:** [event-driven SRE triggers](../../event-driven-triggers.md) maps every task below to Azure Monitor alerts, Azure activities and approved lifecycle-event integrations, including latency settings, routing gaps and absence/deadline monitoring. Starter deployment code is included below, but **has not been deployed or validated in Azure**. Each task now has a persisted boolean `isEnabled`; keep it true until all of that task's replacement paths are accepted.

| Task | Agent | Cron | Use case |
| --- | --- | --- | --- |
| `w2-security-drift-daily` | waf-security | `0 6 * * 1-5` | W2 |
| `w4-out-of-band-changes-daily` | waf-opex | `30 6 * * 1-5` | W4 |
| `w1-reliability-review-weekly` | waf-reliability | `0 7 * * 1` | W1 |
| `w3-cost-waste-weekly` | waf-cost | `0 7 * * 2` | W3, UC11 |
| `w5-capacity-headroom-weekly` | waf-performance | `0 7 * * 3` | W5 |
| `uc05-monitoring-blind-spots-weekly` | observability (+ vending-governance) | `0 7 * * 4` | UC05, UC02 |
| `uc10-backup-assurance-weekly` | resilience | `0 7 * * 5` | UC10 |
| `uc12-incident-to-waf-monthly` | platform-orchestrator | `0 8 1 * *` | UC12 |

Event-driven use cases that still need wiring include UC01 (vending pipeline), UC06 and UC09 (acceptance and upgrade checks), the W4 post-deployment gate, and UC12 (confirmed incident closure). They need separately authorized **HTTP-trigger integrations** or alert rules that verified response plans can match. Log Analytics connectors do not trigger on new rows, and broad workspace/resource-type response plans must be narrowed or replaced before adding domain-specific log-alert routes.

## Event-driven deployment and cutover

The starter contains **eight Activity Log rules**: security/identity changes, network changes, Resource Health, Service Health, disk lifecycle, failed capacity operations, monitoring changes and backup-protection changes. They use distinct `SRE-Wn-` / `SRE-UCnn-` tokens matching `event-response-plans.json`. Configuration changes request investigation; they are not proof of a fault. Health rules also receive recovery/update events.

These are **not complete replacements for all legacy task requirements**. Add service-specific metric/log rules, Policy/Defender export, cost notifications, backup job/recovery-point deadlines, independent expected-resource registries and approved lifecycle adapters using the trigger proposal. The example heartbeat query illustrates a never-seen resource; it is not a subscription-wide inventory or collector. No HTTP adapter, Event Grid subscription, collector or cost integration is provisioned here.

1. **Stage rules disabled.** In an ignored `*.local.bicepparam` copy of `main.bicepparam`, set `deployEventDrivenAlerts = true`, supply `eventActionGroupIds`, and leave `activateEventDrivenAlerts = false`. Add validated metric/log definitions to `eventMetricRules` / `eventLogRules` using the contracts in `event-alerts.bicep`. Query permissions, tables, region and alert evaluation eligibility must be proven first. Alternatively deploy the standalone module below into each approved source subscription; choose one deployment path per rule, not both.
2. **Prepare routing.** Map existing AMBA rules and every new source rule to exactly one token. All existing broad managed plans will be disabled by `-UseEventDrivenResponsePlans`, so map their alert coverage before switching. Disable unmanaged overlapping plans (including quickstart) explicitly; the script blocks migration while potentially active unmanaged plans remain. Retain independent human on-call delivery. Pause agent incident intake during the route-set swap to avoid the brief overlap between new-plan activation and old-plan retirement.
3. **Apply event routes.** Run the data-plane command below with `-UseEventDrivenResponsePlans`. It enables the 17 token routes in Review mode, then disables existing managed legacy routes only if preceding updates succeeded. A later apply without the event flag refuses to silently restore legacy routing. Partial API failure is reported; inspect and repair partially updated plans before resuming intake. This is not a transactional API.
4. **Activate and prove.** Set `activateEventDrivenAlerts = true` (or `activate = true` for the standalone module) only after accepted routing/on-call checks, then restore agent intake. Keep schedules enabled while proving every required replacement, including unchanged pre-existing gaps and missing/deadline evidence. Measure event-to-investigation delay and duplicates.
5. **Retire each schedule explicitly.** Set its `isEnabled` to false in `scheduled-tasks.json` (or an approved persistent file passed with `-ScheduledTasksFile`). Apply with both `-UseEventDrivenResponsePlans` and `-ConfirmScheduleCutover`. Flags are no longer hard-coded to true. Use the same reviewed configuration file on subsequent applies; do not revert to a file with enabled flags.

```powershell
# Run from infra/sre-agent. Stage disabled rules in an existing approved monitoring RG.
az deployment group what-if --resource-group <monitoring-rg> --template-file .\event-alerts.bicep --parameters .\event-alerts.local.bicepparam
az deployment group create --resource-group <monitoring-rg> --template-file .\event-alerts.bicep --parameters .\event-alerts.local.bicepparam

# After mapping existing alerts and accepting the migration gates:
.\dataplane\Apply-DataPlane.ps1 -SubscriptionId <subscription-id> -ResourceGroup rg-platform-sreagent -AgentName sre-platform-ops -TenantId <tenant-id> -UseEventDrivenResponsePlans

# Only after the selected schedules' full replacement coverage is accepted:
.\dataplane\Apply-DataPlane.ps1 -SubscriptionId <subscription-id> -ResourceGroup rg-platform-sreagent -AgentName sre-platform-ops -TenantId <tenant-id> -UseEventDrivenResponsePlans -ConfirmScheduleCutover
```

For the standalone path, first copy `event-alerts.example.bicepparam` to `event-alerts.local.bicepparam`, replace placeholders and remove unsupported sample rules. Select each source subscription with `az account set` before deployment. This module does not create SRE connectors or extend the agent's permissions to another subscription.

**Rollback:** pause agent intake, set affected schedule flags back to true, and if reverting routing run the apply script with `-RestoreLegacyResponsePlans` (not the event flag). Explicit rollback enables the eight legacy routes and disables managed token routes after successful updates. Restore legacy alert names/mappings as needed; token-only alerts may not match the legacy plans. Keep independent human alerts active throughout.

**Offline checks:** `pwsh -NoProfile -File tools/test-dataplane.ps1` from the repository root checks matching, Review mode, persisted schedule flags, unmanaged-plan rejection, API-failure guards and explicit rollback. Compile `main.bicep` and both `.bicepparam` examples with the Bicep CLI. These checks do not prove delivery, query execution or incident intake in Azure.

## Deploy

Replace the `<…>` placeholders in `logAnalyticsWorkspaceIds` in `main.bicepparam` with your own workspace resource IDs, or set the list to `[]`. Keep files that contain real IDs (for example `*.local.bicepparam`) out of shared copies.

```powershell
az account set --subscription <subscription-id>
az deployment sub what-if  --location swedencentral --template-file .\main.bicep --parameters .\main.bicepparam
az deployment sub create   --location swedencentral --name sreagent-platform --template-file .\main.bicep --parameters .\main.bicepparam

# Data plane. Sign in once with the SRE scope if the token request returns a claims challenge.
az login --tenant <tenant-id> --scope "https://azuresre.dev/.default"
.\dataplane\Apply-DataPlane.ps1 -SubscriptionId <subscription-id> -ResourceGroup rg-platform-sreagent -AgentName sre-platform-ops -TenantId <tenant-id>
```

Open the agent at `https://sre.azure.com`, check **Custom agents**, **Scheduled tasks** and **Knowledge sources**, then run one task manually and review the evidence.

## Pause or remove

- **Pause the active flow:** disable response plans and schedules in the portal. Persist schedule changes in `scheduled-tasks.json` and use `-ConfirmScheduleCutover` when applying disabled flags; keep the selected routing flag on subsequent applies. Disable event rules through their deployment parameters if appropriate, but preserve independent on-call monitoring. The always-on charge continues.
- **Stop all billing:** `az group delete --name rg-platform-sreagent`. Stopping the agent does **not** stop the always-on charge. Also remove the subscription-scope Reader assignments for the deleted identities.
