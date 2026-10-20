# SRE Agent deployment (platform operations agent)

This folder deploys **one** Azure SRE Agent for platform operations, following the topology guidance in `..\..\agent-topology.md`: one agent, use cases as custom agents, and split only when a trigger (A1–A7) applies. It is based on the official templates at [microsoft/sre-agent](https://github.com/microsoft/sre-agent).

| File | Purpose |
| --- | --- |
| `main.bicep` | Subscription scope. Creates the resource group, the agent module, and **Reader** on the subscription for the agent's identities. |
| `agent.bicep` | Creates the Log Analytics workspace, workspace-based App Insights, a user-assigned managed identity and `Microsoft.App/agents`. Sets **Azure Monitor as the incident platform** and creates the **connectors**: `azure-monitor` plus one `LogAnalytics` connector per existing workspace. Also assigns **SRE Agent Administrator** to the deployer. |
| `main.bicepparam` | Agent name, RG, region, monthly AAU cap, model provider, incident platform and the workspaces to connect. |
| `dataplane\subagents.json` | 13 read-only custom agents: `platform-orchestrator` (UC04, UC12), 7 domain specialists (UC01–UC11) and 5 WAF pillar agents (W1–W5). |
| `dataplane\scheduled-tasks.json` | 8 scheduled tasks, all in **Review** mode. |
| `dataplane\response-plans.json` | 8 response plans (incident filters) that route Azure Monitor alerts to the right custom agent, all in **Review** mode. |
| `dataplane\Apply-DataPlane.ps1` | Idempotent apply of the custom agents, scheduled tasks, response plans and 4 knowledge files (use cases, WAF pillars, topology, queries). |

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

## Scheduled tasks (UTC, Review mode)

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

Event-driven use cases that still need wiring are UC01 (vending pipeline), UC06 and UC09 (acceptance and upgrade checks), and the W4 post-deployment gate. They need **HTTP triggers** from your pipelines, or alert rules that the response plans above can match.

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

- **Pause the active flow:** disable the scheduled tasks in the portal, or set `isEnabled` to false and re-apply. The always-on charge continues.
- **Stop all billing:** `az group delete --name rg-platform-sreagent`. Stopping the agent does **not** stop the always-on charge. Also remove the subscription-scope Reader assignments for the deleted identities.
