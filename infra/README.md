# Optional monitoring skeleton

This is a **partial, non-production monitoring foundation**, not an SRE Agent deployment or a complete ALZ, AI landing zone, or AKS deployment. Prefer the existing ALZ workspaces and diagnostic policy assignments. Do not deploy a duplicate central workspace merely to try SRE Agent.

`main.bicep` creates a new pilot Log Analytics workspace using published AVM `0.16.1`, disables local authentication, and requires an explicit public/private network choice. It deliberately creates no broad RBAC assignments, no execution identity, no connector secrets, no remediation workflow, and no billable SRE Agent.

`activity-log.bicep` routes selected subscription Activity Log categories to an existing workspace. The diagnostic settings API is a documented preview API; the resource is used directly because it is a small subscription-scoped extension resource. This is not a claim that an AVM equivalent does not exist.

> **SRE Agent deployment:** the billable agent itself, with its custom agents, scheduled tasks and knowledge, is in [`sre-agent\README.md`](sre-agent/README.md).

## 1. Compile locally without deploying

From this folder in PowerShell:

```powershell
bicep restore .\main.bicep
bicep build .\main.bicep --outfile "$env:TEMP\sre-foundation-main.json"
bicep build .\activity-log.bicep --outfile "$env:TEMP\sre-foundation-activity.json"
```

Registry restoration needs access to `mcr.microsoft.com`. Module versions are intentionally pinned; review updates rather than substituting `latest`.

## 2. Decide whether any deployment is needed

Check the subscription, management group inheritance, existing Log Analytics workspaces, diagnostic settings, resource locks, and policy assignments. Obtain platform approval. Confirm retention, cost allocation, and data access. Deployment permissions belong to the approved deployment identity, **not** the SRE Agent.

The files do **not** configure Azure Monitor Private Link Scope (AMPLS), private endpoints, DNS, DCRs, Azure Monitor Agent, Container Insights, managed Prometheus, alert rules/action groups, AMBA, or an SRE incident-response plan. These are explicit setup tasks in the playbook.

`Disabled` query/ingestion is unusable until the appropriate private path exists. Do not turn public access on merely to bypass a failed private-network test. `Enabled` allows the service's authenticated public endpoint; it does not allow anonymous queries. Select it only if the organization's network/data policy permits it. Neither setting establishes SRE Agent regional data residency.

## 3. Preview changes against the intended sandbox

The following commands contact Azure and require an already authenticated operator. They are **examples, not commands executed by this kit**. Replace every placeholder. A `what-if` can evaluate provider behavior but is not a connectivity test.

```powershell
$subscriptionId = '<sandbox-subscription-id>'
$resourceGroup = '<existing-pilot-resource-group>'
$workspaceName = '<new-pilot-workspace-name>'
az account set --subscription $subscriptionId

# Choose these deliberately after network approval; no default is implied.
$queryAccess = '<Enabled-or-Disabled>'
$ingestionAccess = '<Enabled-or-Disabled>'
az deployment group what-if --resource-group $resourceGroup `
  --template-file .\main.bicep `
  --parameters workspaceName=$workspaceName `
    publicNetworkAccessForQuery=$queryAccess `
    publicNetworkAccessForIngestion=$ingestionAccess
```

After review, an authorized operator can use the same parameters with `az deployment group create`. Do not automate the transition from `what-if` to `create` without the approved release gate.

For an **existing or newly approved workspace**, inspect for duplicate source routing before previewing:

```powershell
$workspaceId = '<approved-workspace-resource-id>'
az deployment sub what-if --location westeurope `
  --template-file .\activity-log.bicep `
  --parameters workspaceResourceId=$workspaceId
```

`--location westeurope` specifies deployment metadata location, not SRE Agent processing location. An authorized operator can replace `what-if` with `create` only after approval.

## 4. Verify the exact behavior

In the source subscription, perform one approved sandbox management operation; record its correlation ID. In the workspace, run the AzureActivity query in `..\queries\starter-queries.kql` and locate that operation after ingestion. Repeat from the SRE Agent's tool context to prove query authorization and connectivity. A successful query by the human operator is not evidence that the agent can query.

Reject onboarding if there is no evidence, if the agent can access an unapproved subscription/table, or if private connectivity fails. Configure a harmless test alert and use the portal alert test as described in the setup guide; neither Bicep file creates or wires that alert.

## 5. Rollback

Use the approved IaC process to remove only the newly added diagnostic setting if it duplicates routing or exposes data. Do not delete shared workspaces, inherited policy assignments, or production alerts. Removing routing stops future ingestion; it does not purge existing records. Retention/purge and SRE Agent deletion require separate authorized procedures. Compilation artifacts in the session folder can be removed independently of Azure.

## Sources

- [AVM workspace source and parameter contract](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/operational-insights/workspace)
- [Subscription diagnostic settings API](https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/2021-05-01-preview/diagnosticsettings)
- [Export the Azure Activity Log](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log)
- [Azure Monitor Private Link design](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/private-link-design)
