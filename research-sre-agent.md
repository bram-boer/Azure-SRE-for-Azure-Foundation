# Azure SRE Agent — Evidence Report (Product Capabilities & Precise Setup)

**Research date:** 20-10-2026 (amended same date with narrow follow-up on tool-access policies, response-plan setup, and corrections below)
**Scope:** Product capabilities and setup mechanics of Azure SRE Agent only, for use in a CAF/ALZ + WAF reference/starter kit targeting an EU public-cloud (Azure Commercial) IT platform. Subscription Vending, AI Landing Zones, and the AKS accelerator are referenced only as the surrounding CAF/ALZ context the SRE Agent slots into — they were not independently re-researched in this pass per instruction.
**Sources:** Microsoft Learn (`learn.microsoft.com/azure/sre-agent/*`) and `azure.microsoft.com` pricing, fetched live via Microsoft Learn MCP search/fetch tools. No third-party or community sources used.
**Caveat:** Microsoft Learn content is continuously revised and not version-pinned; treat every claim below as "true as observed on 20-10-2026," not as an enduring guarantee. Several internal contradictions were found between Learn pages themselves (flagged inline) — these indicate stale sub-pages, not inference errors on my part.

---

## 1. Release / preview status — ⚠️ contains confirmed contradictions

| Claim | Status | Source |
|---|---|---|
| Product overall | **Unconfirmed / not verified as GA.** The Overview page shows no explicit "preview" banner and the product has its own portal and pricing meter, but no Microsoft "what's new"/announcement page confirming a formal GA date was located in any search pass. Absence of a preview banner on one page is not proof of GA — treat overall release status as **unconfirmed** pending an authoritative GA announcement. | `azure/sre-agent/overview` (searches for GA/announcement returned no matching result) |
| **Control-plane (ARM) and data-plane REST APIs** | Explicitly **"currently in preview"**; API version is `2025-05-01-preview`; doc warns "Endpoint paths, request and response schemas, and behavior might change before general availability" | `azure/sre-agent/api-reference` |
| **GitHub Enterprise Cloud connector (BYO GitHub App)** | Explicitly marked **"currently in preview"**, with a link to the Azure Preview Supplemental Terms | `azure/sre-agent/connect-github-enterprise-cloud` |
| **Managed connectors (Google Drive, SharePoint, Notion, Confluence, Trello, Planner, Box, Dropbox, Outlook, Teams, Gmail, OneNote, Power BI, …)** | Page title itself states **"(preview)"** | `azure/sre-agent/managed-connectors` (title confirmed via Learn search index) |
| Trial / evaluation program | A documented 30-day trial (up to 3 agents) waives always-on charges — described as a current commercial program, not a beta | `azure/sre-agent/evaluate` |
| Pricing page FAQ | States **"At this time, free, trial, and Dev/Test AAUs are not available. All usage is billed based on the Azure Agent Unit pay as you go pricing."** | `azure.microsoft.com/en-us/pricing/details/sre-agent/` |

**⚠️ Contradiction flagged, do not resolve by inference:** The `evaluate` Learn doc (describing a 30-day always-on-fee waiver trial) directly conflicts with the public pricing page's FAQ assertion that "free, trial, and Dev/Test AAUs are not available." Both are official Microsoft pages fetched on the same research date. Recommend the starter kit state this as an open question for the customer to verify at purchase time, not present either claim as settled.

**Bottom line for the starter kit:** Do **not** state Azure SRE Agent core/overall is "GA" — this is **unconfirmed**; no authoritative GA/preview label for the product as a whole was found. What *is* explicitly documented as preview: **the REST/ARM API (`2025-05-01-preview`), the GitHub Enterprise Cloud BYO-App connector, and Managed Connectors (SaaS)**. Any "Subscription Vending + SRE Agent IaC" pattern in the starter kit must be labeled preview-dependent, with the caveat that schemas may change before GA (`azure/sre-agent/api-reference`). Present the product's overall maturity as "actively billed, documented, portal-based service; formal release-stage label not found in Microsoft Learn," not as verified GA.

---

## 2. What the product does (capabilities)

Source: `azure/sre-agent/overview` (full fetch).

- **Core loop:** connects to Azure resources, observability tools, incident platforms, and source-code repos; gathers signals, proposes root cause, and (per configured run mode) executes or proposes mitigations.
- **Three usage patterns:** (1) automate incidents (alert → investigate → propose/execute mitigation → update ticket), (2) automate scheduled workflows (health checks, compliance sweeps), (3) ad-hoc natural-language investigation/advice ("what changed in the last hour?").
- **Five extension points:** Skills (marketplace runbooks/CLI scripts), Custom agents/"subagents" (specialist agents, several ship pre-built, more buildable in Agent Builder), Python tools (custom code), MCP servers (partner connectors — Datadog, Splunk, New Relic, Dynatrace, Elasticsearch — or any custom MCP endpoint), Agent hooks (event-triggered governance automations at lifecycle points).
- **Built-in integrations (no connector needed):** Azure Monitor (metrics/logs/alerts/workbooks), Application Insights, Log Analytics, Azure Resource Graph, Azure Resource Manager/Azure CLI (any resource type), AKS diagnostics via `kubectl`. (`azure/sre-agent/connectors`)
- **Memory/context reuse:** retains root causes, resolution steps, team preferences, and recurring patterns across investigations ("deep context," session insights).
- **IaC support (stated, preview-caveated):** "Deploy the agent, its network configuration, its identity, and its tool policies via Bicep templates and Azure CLI through the same CI/CD pipelines you use for every other Azure resource." (`azure/sre-agent/overview`, Security and governance section) — note this capability rides on the preview ARM API (§1).

---

## 3. Creation prerequisites (exact)

Source: `azure/sre-agent/create-and-set-up` (full fetch, primary authority) cross-checked with `azure/sre-agent/usage`, `azure/sre-agent/network-requirements`, `azure/sre-agent/evaluate`.

| Requirement | Detail |
|---|---|
| Azure subscription | Active subscription with permission to create resources |
| **Microsoft.App resource provider** | Must be registered on the subscription; agent creation fails with "DeploymentNotFound" if not. Verify: `az provider show -n Microsoft.App \| grep -C 15 agents` — look for `"resourcetype : agents"` and `"defaultApiVersion : 2025-05-01-preview"`. Register with `az provider register --namespace "Microsoft.App"`. (`azure/sre-agent/faq-troubleshooting`) |
| **Subscription registration/allow-listing** | If the **Region** dropdown is empty in the creation wizard, the subscription is not yet registered for SRE Agent; must file a GitHub issue against `microsoft/sre-agent` with label `registration` and the subscription ID (`azure/sre-agent/supported-regions`) — i.e., **access can be gated per-subscription even in commercial regions**, a material planning risk for a starter kit. |
| Role to create the agent | **Owner**, or **Contributor + User Access Administrator**, on the subscription or resource group where the agent is created (portal needs to deploy the resource and self-assign SRE Agent Administrator to the creating user) |
| Role to grant Azure resource access during setup | Active **Owner** or **User Access Administrator** on every scope added (directly or via inheritance); if using PIM, activate the eligible role before setup and use "Check PIM role assignments" in the picker |
| `Microsoft.Authorization/roleAssignments/write` | Needed on the creating user's account (via RBAC Administrator or User Access Administrator) |
| Network access | `*.azuresre.ai` and `sre.azure.com` must be reachable from the browser; corporate proxies/Zscaler often block `*.azuresre.ai` by default (`azure/sre-agent/network-requirements`) |
| Firewall allow-list (full list for HTTP+WebSocket) | `*.azuresre.ai`, `sre.azure.com`, `portal.azure.com`, `api.applicationinsights.io`, `api.loganalytics.io`, `api.loganalytics.azure.com`, `*.ods.opinsights.azure.com`, `management.azure.com`, `login.microsoftonline.com`, `*.login.microsoft.com` (`azure/sre-agent/network-requirements`) |

**Resources auto-created on deployment** (`create-and-set-up`, `network-requirements`):
- A **system-assigned managed identity (SAMI)** supporting agent infrastructure, and a **user-assigned managed identity (UAMI)** used for RBAC/connector auth.
- The **Azure SRE Agent resource** itself.
- **Application Insights + Log Analytics workspace** (only if "Create new" chosen at setup; otherwise links to an existing one).
- Automatic **SRE Agent Administrator** role assignment on the new agent, to the creating user.

---

## 4. Exact UI setup steps (onboarding wizard)

Source: `azure/sre-agent/create-and-set-up` (verbatim structure retained).

1. Go to **https://sre.azure.com** and sign in with Azure credentials.
2. Select **Create agent** → three-stage wizard: **Basics → Review → Deploy**.
3. **Basics** fields: Subscription; Resource group (existing or new); Agent name (unique); Region (see §6); Model provider (Azure OpenAI and/or Anthropic — options vary by subscription/region, see §7); Application Insights (create new, default, or attach existing).
   - In EUDB (EU Data Boundary) regions, the provider picker explicitly labels each option **"Covered by EU Data Boundary commitments"** or **"Excluded from EU Data Boundary. Data might be processed in the United States."**
4. **Review**: confirm subscription/resource group/agent name/region; select **Create**.
5. **Deploy**: provisioning typically takes **2–5 minutes**; creates the resources listed in §3.
6. Select **Set up your agent** → setup page has two tabs: **Quickstart** (Code, Logs, Azure resources, Incidents) and **Full setup** (Quickstart + Knowledge files).
7. **Connect code**: Code card → **+** → choose GitHub / Azure DevOps / GitLab → pick auth method (GitHub: personal account, PAT, or BYO GitHub App — **GitHub Enterprise Cloud requires a GitHub App**, preview feature, §1) → select repositories → Save.
8. **Connect logs**: Logs card → **+** → choose provider (Azure Data Explorer / Log Analytics Workspace / Application Insights, or search for others — "the complete list can vary by tenant and configuration") → fill fields → Add connector. Saving auto-assigns **Log Analytics Reader** and **Monitoring Reader** to the agent identity.
9. **Add Azure resource access (optional)**: choose scope type — **Management group / Subscription / Resource group** — then choose permission level **Reader** or **Privileged** (see §5); role assignment can take several minutes to propagate.
10. Select **Done and go to agent** to open agent chat.

**Known UI/API inconsistency limitation:** `user-roles` notes that an **Author**-only role can perform certain operations via the ARM `extendedAgents` path that the **portal UI blocks** for that same role (because the portal workflow requires `Microsoft.App/agents/memory/write` and `threads/write`, which Author lacks) — i.e., **"an operation can succeed through ARM but fail in the portal for an Author."** Document this explicitly as a known UI/RBAC limitation, not a bug to engineer around silently.

---

## 5. Identity & RBAC — three distinct layers (do not conflate)

Source: `azure/sre-agent/user-roles` (full fetch, authoritative), `azure/sre-agent/permissions` (full fetch), `azure/sre-agent/run-modes` and `azure/sre-agent/api-reference` (for the contradiction noted below).

The docs explicitly separate three control layers:

| Layer | Controls | Where configured |
|---|---|---|
| **User roles** | What *users* can do with the agent (chat, approve, configure) | Azure IAM on the agent resource |
| **Run modes** | Whether the *agent* asks before acting | Per response plan / per scheduled task |
| **Agent permissions** | What the *agent itself* can reach on Azure (with OBO as fallback) | RBAC roles on resource groups, granted to the agent's managed identity |

### 5a. User roles (four built-in, portal-documented)
`SRE Agent Reader`, `SRE Agent Standard User`, `SRE Agent Author`, `SRE Agent Administrator`. Capability matrix (chat, Agent Canvas, knowledge base, code connectors, response plans, managed resources, scheduled tasks, settings) is fully tabulated in `user-roles`. The agent creator is auto-assigned **Administrator**. Only **Administrator** can approve write actions and manage connectors/resource scopes; **Author** can design response plans/custom agents but cannot chat or approve; **Standard User** can chat/run diagnostics/request actions but not approve; **Reader** is view-only.

**⚠️ Contradiction flagged:** `api-reference` lists only **three** RBAC roles for the agent resource — "SRE Agent Administrator," "SRE Agent User," "SRE Agent Reader" — omitting **Author** entirely, and renaming "Standard User" to "User." This is inconsistent with the four-role model in `user-roles`. Treat `user-roles` as the UI-authoritative source for day-to-day administration and flag the API doc's role list as unreliable/stale for that detail.

### 5b. Agent permissions (managed identity / RBAC on resources)
Every agent gets an auto-created **user-assigned managed identity (UAMI)**. At creation, you choose one of two **permission levels** applied to selected resource groups:

| Level | Always-assigned roles | Added roles |
|---|---|---|
| **Reader** | Reader (RG), Log Analytics Reader (RG), Monitoring Reader (RG), Monitoring Contributor (subscription) | none — agent must request temporary elevation via OBO to act |
| **Privileged** | same base roles | + resource-type-specific **Contributor**-class roles auto-detected per resource type in the RG (e.g., Container App Contributor) |

If no resource groups are assigned at creation, **the managed identity has zero permissions** — nothing is implicit. Permissions can only be removed by removing the whole resource group scope, not individual roles.

**On-behalf-of (OBO) fallback:** when the managed identity lacks permission for a requested action, the agent can request the **approving user's own credentials** temporarily via OAuth2 OBO flow; credentials are not retained after the operation. **Only users with the SRE Agent Administrator role can authorize OBO requests**; **personal Microsoft accounts cannot authorize OBO under any role** — only Entra ID (work/school) accounts.

### 5c. Run modes (approval workflow)
Source: `azure/sre-agent/run-modes` (full fetch).
- Two modes are documented in the narrative page: **Review** (agent proposes, Administrator approves/denies — default) and **Autonomous** (agent executes immediately, reports after).
- Run mode is set **per response plan and per scheduled task**, not globally on the agent (though **Settings > Basics** shows an agent-level default used as fallback, itself defaulting to Review at creation).
- Review mode only shows Approve/Deny for **Azure infrastructure operations** (CLI/ARM write actions); other actions (emails, Teams posts, external queries) proceed per the agent's reasoning and response-plan instructions unless additionally gated by **Hooks** or **Tool Access Policies**.

**⚠️ Contradiction flagged:** The narrative `run-modes` page describes exactly **two** modes (Review, Autonomous). However:
- `api-reference` documents the agent property `actionConfiguration.mode` with **three** enum values: `Review`, `Automatic`, `ReadOnly`.
- `security-overview` (from search excerpt) and the general `faq` both reference a **"ReadOnly"**/**"Reader mode"** as a usable mode ("use Azure SRE Agent in Reader mode" / "Use ReadOnly for monitoring-only agents that never take action").
This is a real naming/count mismatch across official pages (two-mode UI narrative vs. three-value API enum vs. "Reader mode" FAQ wording). Recommend the starter kit treat **Review / Autonomous / ReadOnly** as the operative three-state model (since it appears consistently in three separate sources — API schema, security overview, and FAQ) and flag the `run-modes` page's "two modes" framing as likely incomplete/simplified rather than authoritative.

---

## 6. Regions, EU availability, and a confirmed regional-availability contradiction

Source: `azure/sre-agent/supported-regions` (full fetch) vs. `azure/sre-agent/faq` (full fetch) — **both fetched same session, both currently published**.

### 6a. Reference-page region list (`supported-regions`, 22 regions)
Australia East, Brazil South, Canada Central, Central India, Central US, East Asia, East US 2, **France Central**, **Italy North**, Japan East, Japan West, Korea Central, North Central US, South Africa North, South India, Southeast Asia, **Spain Central**, **Sweden Central**, **UK South**, West Central US, West US 2, West US 3.

→ **EU-relevant regions per this list:** France Central, Italy North, Spain Central, Sweden Central (all EU); UK South is not EU but often bundled in "Europe/EFTA" compliance discussions — confirm UK-specific requirements separately since UK is **not** in the EU Data Boundary.

### 6b. General FAQ page (`faq`, 3 regions)
States verbatim: *"Azure SRE Agent is currently available in: Sweden Central, East US 2, Australia East."*

**⚠️ Confirmed contradiction — do not average or infer a resolution:** These two official Learn pages, fetched on the same date, list 3 regions vs. 22 regions. **All three FAQ regions (Australia East, East US 2, Sweden Central) are a subset of the 22-region reference list** — i.e., the contradiction is about *completeness*, not conflicting membership: the FAQ page does not claim any region the reference page excludes, but it omits 19 regions the reference page includes (among them the other three EU regions: France Central, Italy North, Spain Central, plus UK South). Possible explanations (unverifiable from docs alone): the FAQ page is stale and the reference page added regions progressively; or the FAQ describes a narrower subset still gated behind the subscription-registration allow-list (§3) even though the reference page lists the wider set as "supported." **Recommend the starter kit state both lists, cite both URLs, and instruct the reader to verify actual region availability live in the creation wizard's Region dropdown for their specific subscription** — which the docs themselves recommend: "To see which regions are available for your subscription... open the Region dropdown" (`supported-regions`).

### 6c. Other regional constraints
- Agent **hosting** (compute/storage/state) is pinned to **exactly one region per agent**, chosen at creation, **immutable afterward**. Multi-region *agent redundancy* (e.g., failover or geo-distributed agent hosting) requires deploying one agent per region — this is the only sense in which "one agent per region" is true.
- **This does NOT mean monitored resources must match the agent's region.** Once granted permission, a single agent's managed identity can **investigate and manage Azure resources in any region or subscription**, regardless of where the agent itself is hosted. A single EU-hosted agent can legitimately monitor workloads across multiple regions/subscriptions; you do not need one agent per *monitored-resource* region, only one agent per *hosting* region if you choose to run agents redundantly or near-residency in more than one place.
- Region requests for unsupported regions can be filed via GitHub issue (`microsoft/sre-agent`, label `region-request`).
- Troubleshooting doc (`azure/sre-agent/faq-troubleshooting`) independently references **"Sweden Central, East US 2, or Australia East"** as the three regions checked during a specific deployment-failure diagnostic flow — a third occurrence of the narrower 3-region set, lending some weight to it being the actual commercial rollout status at a point in time that the 22-region reference page may have since superseded, or vice versa. This cannot be resolved without a live portal check.

---

## 7. Data residency / EU Data Boundary caveats

Source: `azure/sre-agent/data-privacy` (full fetch), `azure/sre-agent/model-provider-selection` (search excerpt), `azure/sre-agent/create-and-set-up`.

- **Model inference residency depends on the chosen model provider, not just the agent's region:**
  - **Azure OpenAI:** for agents deployed **in EU/EFTA regions**, inference stays inside Microsoft's EU Data Boundary (EUDB). Outside EU/EFTA, inference "can happen globally."
  - **Anthropic:** inference "can happen globally" and is **explicitly excluded** from EUDB commitments, regardless of agent region.
- **Default provider by region category:**

  | Region category | Anthropic | Azure OpenAI |
  |---|---|---|
  | Commercial regions outside EU/EFTA/UK | Default | Available |
  | **EU, EFTA, and UK** | Available (opt-in only) | **Default** |
  | Government/sovereign clouds | Not available | Default |

- **Action for EU-only platforms:** the starter kit should instruct customers with EU data-residency requirements to **explicitly select/keep Azure OpenAI** as the provider; Anthropic must be a deliberate opt-in with an acknowledged data-processing notice ("your data can be processed globally"), per `model-provider-selection`.
- **Stored data residency:** conversation history, uploaded files, and (usually) memory/knowledge search indexes are stored **in the agent's selected region** — except for specific documented cross-region search-index placements (East US 2 → Central US or East US 2; West US 2 → North Central US/West US 3/West US 2; West US 3 → North Central US/West US 3; South India → Central India). **No EU-region cross-placement exceptions are listed** in the fetched table, implying EU-region agents keep their search indexes in-region — but this is an absence-of-evidence inference, not an explicit confirmation; flag for the customer to request written confirmation if contractually required.
- **Customer Lockbox is explicitly NOT supported** for Azure SRE Agent (`data-privacy`) — material for any WAF/compliance-reliability writeup.
- **No automatic data deletion**: conversations, knowledge, memory, and connector credentials persist until manually deleted; deleting the agent removes all agent-managed data but is irreversible, with no agent-native backup/export beyond what the customer independently version-controls.
- The onboarding wizard UI itself labels each model-provider choice inline as "Covered by EU Data Boundary commitments" vs. "Excluded from EU Data Boundary. Data might be processed in the United States." when the agent is created in a EUDB region (`create-and-set-up`) — this is a genuine built-in compliance affordance worth highlighting in the starter kit as a positive control point.

---

## 8. Connectors, incident triggers, knowledge, subagents, automation

Source: `azure/sre-agent/connectors` (full fetch), `azure/sre-agent/incident-platforms` (full fetch), `azure/sre-agent/overview`.

### 8a. Built-in (no connector required)
Application Insights query, Log Analytics query, Azure Monitor metrics, Azure Resource Graph (cross-subscription resource discovery), Azure Resource Manager/Azure CLI (read+write any resource type), AKS `kubectl` diagnostics.

### 8b. Connector categories (release status not separately confirmed except where noted preview)
- **Data sources:** Log Analytics (persistent connector, adds ambient context beyond ad-hoc query), Application Insights (same), Azure Data Explorer/Kusto — both "database query" (predefined KQL) and "database indexing" (auto-learned schema for dynamic queries).
- **Source code & knowledge:** GitHub MCP server, GitHub OAuth, Azure DevOps OAuth, Azure DevOps Wiki documentation indexing.
- **Collaboration:** Microsoft Teams (notifications), Outlook (email).
- **Custom (MCP servers):** any MCP-compatible server via Streamable-HTTP (remote) or stdio (local); preconfigured one-click partner connectors include **Datadog, Splunk, New Relic, Dynatrace, Elasticsearch, Grafana** (Grafana confirmed via a YAML example in the connectors page); health-monitored via 60-second heartbeats with automatic reconnection.
- **Managed connectors (⚠️ preview):** a separate SaaS-connector system — Google Drive, SharePoint, Notion, Confluence, Trello, Planner, Box, Dropbox, Office 365 Outlook, Teams, Gmail, OneNote, Power BI, and more (`azure/sre-agent/managed-connectors`, page title states "(preview)").
- **RBAC on connectors:** only **SRE Agent Administrator** can create/edit/delete connectors; Standard User and Reader are view-only. Some connectors require external-system OAuth consent (e.g., GitHub org member) independent of SRE Agent's own RBAC.

### 8c. Incident platforms (triggers) — distinct concept from connectors
- Supported: **Azure Monitor** (native, no credentials needed — alerts from managed resource groups flow automatically, recurring alerts merged into one thread), **PagerDuty** (API-based), **ServiceNow** (ITSM integration).
- **Only one incident platform can be active at a time**; switching disconnects the previous one — a material architectural constraint for multi-tool estates.
- Each platform supports documented **read** and **write** capabilities back into the incident record (e.g., Azure Monitor: read alert details/severity/affected resources, write = acknowledge/close; PagerDuty: read incident+diagnostics, write = acknowledge/resolve/add notes; ServiceNow: read incident details, write = post discussion/acknowledge/resolve).
- **Response plans** route incidents to the correct custom agent/handling logic by filter criteria (severity, title pattern, etc.) and set the **run mode/autonomy level** for that incident type. A **default "quickstart" response plan is auto-created** the first time an incident platform is connected (Azure Monitor: handles Sev0–Sev2 autonomously by default, covers all severities Sev0–Sev4 if customized; PagerDuty: P1 autonomous by default) — **this quickstart plan runs alongside any custom plans you create and can cause duplicate or misrouted processing**; the docs explicitly instruct deleting it via Builder → Incident response plans → Table view if custom plans are added.

### 8d. Automation surfaces
- **Scheduled tasks**: proactive health checks/compliance sweeps/routine tasks on a defined schedule; results surface in the connected incident platform or notification channel; run mode (Review/Autonomous) configurable per task, defaulting to **Autonomous** per `run-modes`.
- **Skills**: discrete capability packages (`SKILL.md` + supporting files/tools) teaching the agent "how" to do something; distributable org-wide via a **Private Plugins Marketplace** (governed skill distribution model) for platform teams to publish vetted skills.
- **Custom agents ("subagents")**: specialist agents scoped to specific tool sets (e.g., a Kusto-focused database agent vs. a GitHub-focused deployment agent), built in **Agent Canvas**; several ship pre-built.
- **Python tools**: AI-generated or hand-written custom logic/API calls, tested in a playground before being attached to agents.
- **Kusto tools**: parameterized KQL queries with deterministic results, built the same way (Agent Canvas → Create → Tool → Kusto tool), requiring the **AllDatabasesViewer** role on the target ADX cluster for the agent's managed identity.
- **Agent hooks**: event-triggered automations (e.g., post-tool-call, on-stop) for policy enforcement, telemetry emission, or external approval integration — the recommended mechanism to add governance for actions that Review-mode approval does **not** cover (emails, Teams posts, external queries).
- **Tool access policies**: per-tool **allow / ask / deny** settings, layered (global admin guardrails → team-lead custom-agent overrides → user per-conversation approval), precedence depends on scope/policy in effect (exact precedence rules not detailed in the fetched overview; would need `azure/sre-agent/tool-access-policies` full fetch for exact ordering — **not yet verified**, flag as a gap).

---

## 9. Private networking constraints

Source: `azure/sre-agent/network-integration` (full fetch), `azure/sre-agent/configure-network-controls` (search excerpt), `azure/sre-agent/security-overview` (search excerpt), `azure/sre-agent/faq` (full fetch).

### 9a. Three egress modes (agent-level, switchable at runtime)
| Mode | Behavior | Default |
|---|---|---|
| **Unrestricted** | No outbound restrictions; agent can reach any internet endpoint | **Yes (default)** |
| **Limited** | Wildcard-based allow-list of hostnames; deny-all otherwise | — |
| **Azure VNet** | All non-platform outbound traffic routed through a customer-delegated subnet; NSG/firewall/custom DNS/network logs all apply | — |

Modes are switchable on a running agent; settings persist; connecting a VNet disables the other two mode cards until disconnected.

### 9b. Azure VNet mode — subnet requirements
- Dedicated subnet, **/27 or larger**, **delegated to `Microsoft.App/environments`**, same region as the agent, not shared with other services.
- Requires **Network Contributor** (or equivalent with `Microsoft.Network/virtualNetworks/subnets/join/action`) on the target subnet, plus **SRE Agent Administrator** on the agent.
- "Use VNet's private DNS" is auto-enabled on connect — required for resolving private-endpoint hostnames (e.g., Log Analytics behind AMPLS); customer must still link the relevant Private DNS zones (e.g., `privatelink.ods.opinsights.azure.com`, `privatelink.vaultcore.azure.net`) to the VNet, or the agent silently falls back to public endpoints or fails to connect.

### 9c. What always bypasses the VNet (not configurable)
- **Platform/orchestration services, model endpoints, and telemetry** always route over Microsoft's managed "SRE Agent infra network," regardless of egress mode.
- **Connector traffic never routes through the customer VNet** — it always goes over the public internet, even in Azure VNet mode. This is an explicit, non-negotiable limitation (`network-integration` → Limitations).
- **Egress-only**: there is **no inbound private-endpoint/private-link support** to reach the agent itself from inside a private network.

### 9d. Configurable bypass toggles (per-category "infra network" routing)
When in Azure VNet mode, package registries (PyPI/npm/NuGet/apt), code repositories (GitHub/GHE/Azure DevOps — each independently toggled), remote MCP server access, and arbitrary "additional hosts" can each be individually toggled to route over the managed infra network instead of the customer VNet (useful because these public services don't expose stable Azure service tags and would otherwise require unstable IP allow-lists). An **Azure Policy can restrict/disable these toggles tenant-wide** to prevent operators from routing traffic outside the VNet.
- A **Network audit** view (Settings → Workspace configuration → Inspect) shows allowed/denied egress decisions, but this covers **agent egress-policy decisions only** — it is explicitly **not** a complete network/connector/runtime/firewall/DNS/proxy audit trail.

### 9e. Do you need VNet integration at all?
Per the FAQ: **no** — the agent is fully functional in Unrestricted (default) mode, including investigating public resources, running CLI/kubectl, querying Log Analytics/App Insights with public access enabled, and using all connectors/MCP servers. VNet integration is additive, for egress control, private-endpoint reachability, audit trail, or compliance mandates — relevant triggers: Log Analytics/AKS/DB public access disabled behind AMPLS/private endpoints, mandatory firewall egress, ExpressRoute/VPN-only on-prem systems, or compliance requiring network-level visibility.

### 9f. Regional sandbox isolation (separate from VNet mode)
`security-overview` (search excerpt only, not full-fetched) states sandbox execution respects **regional boundaries** — e.g., an East US 2 agent's sandbox stays within Central US/North Central US/Canada Central — and that **dedicated, VNet-integrated sandboxes** can be configured for execution fully inside the customer VNet. This "regional isolation" list did not include any EU-region example in the fetched excerpt; **recommend a full fetch of `azure/sre-agent/security-overview` before finalizing any EU data-residency sandbox claim**, since this was only seen via search snippet, not the full page.

---

## 9g. Tool access policies — exact deny/ask controls, and how to enforce a true no-write pilot

Source: `azure/sre-agent/tool-access-policies` (full fetch) + `azure/sre-agent/permissions` (full fetch, re-verified).

### Three policy scopes (not equal power)
| Scope | Set by | Rules allowed | Covers |
|---|---|---|---|
| **Global** | Administrator, via **Settings → Permissions** in the portal (or `PUT /api/v2/agent/settings/global`) | **Allow, Ask, Deny** | Every custom agent and conversation on the agent |
| **Custom agent** | Administrator or Author | **Allow only** | One custom agent |
| **Thread** | Any user | **Allow only** | One conversation |

**Only Global scope can Deny.** Custom-agent and thread scopes can only widen access (Allow) within whatever the Global policy permits — they can never override a Global Deny.

### Evaluation order (exact, documented priority — highest wins)
1. **Hooks** (user-defined hook "allow" overrides everything below, including Global Deny; a hook "deny" blocks immediately; only Administrators can create hooks; every hook-based override is audit-logged).
2. **Tool access policies**: Deny (global only) blocks; Allow (any scope) skips approval entirely, even in Review mode; Ask (global only) pauses in Review mode but **auto-approves in Autonomous mode**.
3. **Default approval**: connector "Ask"/"RequiresApproval" tools pause for approval.
4. **Run mode** (lowest priority): Review pauses; **Autonomous auto-approves everything not already decided above**.

**Key enforcement implication:** Run mode is evaluated last. Review alone does not guarantee no writes: a tool-policy Allow or higher-priority hook Allow can bypass it. Configure Global Deny for all relevant mutation-capable tools **and verify there are no higher-priority Allow hooks** before connecting intake. Include generic execution and external-system tools in the review, not just Azure/Kubernetes write tools. Deny coverage, effective RBAC and negative tests must all pass; do not describe a partial policy as a universal guarantee.

### Exact Global Deny configuration for a no-write pilot
In portal: **Settings → Permissions** (Administrator role required). Add Deny patterns, e.g.:
```
RunAzCliWriteCommands
bash(az * delete *)
bash(az * create *)
bash(az * set *)
RunKubectlWriteCommand
RunKubectlWriteCommand(kubectl apply *)
RunKubectlWriteCommand(kubectl delete *)
ValidatePsqlCommand
```
or, for maximal safety in a pilot, deny the broad write-tool names outright (`RunAzCliWriteCommands`, `RunKubectlWriteCommand`) rather than trying to enumerate every argument pattern — patterns support `*` wildcard and the `toolGlob(argGlob)` syntax for command tools; up to 1,000 patterns per scope. Equivalent via API: `PUT https://<agent>/api/v2/agent/settings/global` with a `permissions.deny` array (exact curl example is in the fetched doc).

Read-only tools that remain useful and safe to leave on Allow/Ask: `RunAzCliReadCommands`, `RunKubectlReadCommand`, Log Analytics/App Insights/Resource Graph queries (all built-in, non-write by nature).

### Reader permission preset — exact implications, including subscription-level Monitoring Contributor and OBO
Source: `azure/sre-agent/permissions` (re-confirmed).
- Choosing **Reader** assigns resource-group read roles but also subscription-scope **Monitoring Contributor**, regardless of the Reader/Privileged choice. This role is write-capable and **must not be characterized as an ack/close-only exception**: inspect its actual role definition and effective scope. If the assignment violates the approved access boundary, block onboarding or use sanitized evidence; do not silently remove service-managed roles or assume the product supports that configuration.
- Under Reader, **any other write action requires On-Behalf-Of (OBO)**: the managed identity has no write RBAC, so the agent must request the approving user's own Entra credentials, temporarily, per action. **Only a user holding the SRE Agent Administrator role can authorize an OBO prompt**; personal Microsoft accounts can never authorize OBO. This means that even with Reader-level agent permissions, **a human Administrator can still manually approve a write via OBO** — Reader-level RBAC alone is *not* a hard technical block on writes, it only raises the bar to "requires an explicit human OBO approval each time." **For a true no-write pilot, combine Reader-level permissions with a Global Deny tool-access policy (above)** — the Global Deny blocks the tool call before OBO is even reached (Deny is evaluated above "default approval"/OBO in the priority table), closing the human-approval loophole that Reader-alone permissions leave open.

**Net guidance:** before granting scopes or connecting intake, configure the required Global Deny coverage, exclude higher-priority Allow hooks and unnecessary mutation-capable tools, and test the boundary. Inspect the Reader preset's effective roles; obtain explicit risk acceptance or block onboarding if the generated access is unsuitable. Do not equate Reader or Review with enforced read-only access.

---

## 9h. Exact safe Azure Monitor response-plan setup — neutralizing Autonomous default before alert intake

Source: `azure/sre-agent/azure-monitor-alerts` (full fetch) + `azure/sre-agent/response-plan` (full fetch) + `azure/sre-agent/incident-platforms` (full fetch, re-confirmed).

### The risk this addresses
Connecting Azure Monitor as the incident platform **auto-creates a default "quickstart" response plan** that is **Autonomous by default**, targeting **Sev0, Sev1, Sev2** alerts out of the box (Azure Monitor supports Sev0–Sev4; quickstart only matches the top three unless you customize it). The Azure Monitor **scanner polls every 1 minute**, with an **initial lookback of 1 day** on first connect — meaning **pre-existing alerts up to 24 hours old can be picked up and auto-actioned within minutes of connecting**, before you have had a chance to review or reconfigure the quickstart plan, if you connect without first neutralizing it.

### Exact step sequence to avoid unintended autonomous action on connect
1. **Before connecting**, apply the Global Deny tool-access policy from §9g (this is your backstop even if the quickstart plan activates faster than you can react).
2. Go to **Builder → Incident platform**, select **Azure Monitor**, and **Save** (uses the agent's managed identity — no credentials needed; confirm **Monitoring Contributor** is present on the target subscription(s), per §9g, or alerts won't surface per the troubleshooting note in `azure-monitor-alerts`).
3. **Immediately** (the scanner begins within ~1 minute) go to **Builder → Incident response plans**, switch to **Table view**.
4. Locate the auto-created plan (named `quickstart_handler`). You have two safe options — pick one **before** doing anything else:
   - **Option A — Turn off**: select its checkbox → **Turn off** in the toolbar → confirm. This fully disables routing for that plan immediately (status badge → Off); its filter configuration is preserved if you want to inspect/reuse it later.
   - **Option B — Edit to Review**: open the plan via its plan-ID link, change **Agent autonomy level** from **Autonomous (Default)** to **Review**, and **Save**. This keeps Sev0–2 intake active but forces human approval on every proposed action (subject to the §9g priority caveat that a Global Allow/hook could still bypass Review — hence doing §9g first).
   - Recommended for a true pilot: **do both** — turn the quickstart plan off, then build your own scoped plan (step 5) explicitly in Review mode.
5. Create your own response plan: **Builder → Agent Canvas → Create → Trigger → Incident response plan**. Fill in:
   - **Incident response plan name** (descriptive, e.g. `pilot-sev1-readonly`).
   - **Severity**: select only the specific level(s) you want in-scope for the pilot (e.g., Sev1 only — do not select "all").
   - **Title contains** (optional): add a keyword to further narrow matches (e.g., restrict to one app's alert-rule naming convention).
   - **Response custom agent**: select the custom agent that should handle these (or the default agent).
   - **Agent autonomy level**: **explicitly select "Review"** — do not accept the "Autonomous (Default)" pre-selection. (The portal UI defaults every *new* plan to Autonomous; you must actively change it.) If you do select/accept Autonomous, the portal surfaces an **"Autonomous mode acknowledgment"** dialog (ℹ️ icon) summarizing agent boundaries, model limitations, and operator responsibilities — read/require this acknowledgment as a governance gate even outside a pilot.
   - **Reinvestigation cooldown** (Azure Monitor only): leave **Enabled** (default) with the default **3-hour** cooldown unless you have a specific reason to disable it — disabling it on a noisy alert rule "can significantly increase token consumption" (documented warning) since every single fire opens a fresh investigation instead of merging into one thread.
6. Select **Next** to preview matching historical incidents (default lookback: **last 30 days for Azure Monitor**, 90 days for PagerDuty/ServiceNow). Use this to confirm your filter is neither too broad (too many matches) nor too narrow (zero — acceptable for genuinely new alert rules).
7. Select **Create** to save; confirm the plan shows **Status: On** in the grid.
8. **Validate safely before widening scope**: use the documented test pattern — set **Title contains** to a unique marker (e.g., `"[TEST] CPU spike"`), fire/create a matching test incident, and confirm the agent investigates and (in Review mode) proposes without auto-executing. Only after this validation should you remove the test-title restriction or widen severity coverage.
9. Only after both the quickstart plan is neutralized (step 4) and your own scoped Review-mode plan is validated (step 8) should you consider widening severity coverage or re-enabling broader autonomous handling — and only incrementally, per the product's own recommendation ("Start with review mode. Observe what the agent recommends for two to four weeks... switch those specific triggers to Autonomous," `run-modes`).

### Why order matters
Because the scanner starts shortly after connection and a default plan is created, apply and test the effective no-mutation boundary **before** connection. This includes Global Deny coverage, no higher-priority Allow hooks, reviewed tool/connector capabilities and effective permissions. Disable the quickstart plan immediately afterward. If this boundary cannot be demonstrated, do not connect intake.

---

## 10. Pricing (carried forward from prior turn, for completeness in this file)

Source: `azure/sre-agent/pricing-billing` (full fetch) and `azure.microsoft.com/en-us/pricing/details/sre-agent/` (full fetch).

- Billing unit: **Azure Agent Unit (AAU)**, shared meter across "all prebuilt Azure agents."
- **Always-on (fixed):** 4 AAUs per agent-hour, from creation until deletion (stopping an agent does **not** stop always-on billing — only deletion does).
- **Active flow (variable):** metered per-token across 4 token types (input/output/cache-read/cache-write) at model-specific AAU rates:

  | Model | Input | Output | Cache read | Cache write |
  |---|---|---|---|---|
  | Claude Opus 4.6 | 100 | 500 | 10 | 125 |
  | GPT 5.3 Codex | 35 | 280 | 3.5 | 0 |
  | GPT 5.2 | 35 | 280 | 3.5 | 0 |

  (AAUs per 1M tokens.)
- Monthly active-flow spending limit configurable (500–1,000,000 AAU); hitting it suspends chat/actions (not always-on billing) until next month or a manual increase.
- **No concrete $/€ retail rate per AAU is published statically** on the Learn billing page or the azure.microsoft.com pricing page as of 20-10-2026 — the pricing table renders literal **"$-"** placeholders requiring an interactive region/currency selection the static fetch could not resolve. **However, the parent/orchestrating researcher has since verified exact retail rates directly via the Azure Retail Prices API** (productName "Azure Agent Unit", skuName "SRE", serviceName "Foundry Tools", meterName "SRE Agent Unit", unitOfMeasure "1"): **West Europe EUR 0.1197 / USD 0.136**, **France Central EUR 0.0968 / USD 0.11** (per AAU). Full URLs and meter IDs for this verified rate are recorded separately in **`costs.md`** in this same `drafts\azure-sre-foundation-starterkit` folder — cite that file (not this one, and not a re-fetch of the interactive calculator) as the authoritative source for €/AAU figures in the starter kit.
- **⚠️ Contradiction flagged (trial):** `evaluate` doc describes a 30-day always-on-fee waiver trial (up to 3 agents); pricing page FAQ states free/trial/Dev-Test AAUs are "not available." Unresolved — present both to the customer.

---

## 11. Gaps, uncertainties, and recommended follow-ups

1. **Region count contradiction (§6)** — 22-region reference page vs. 3-region FAQ/troubleshooting pages. Not resolvable from docs; must be confirmed live in the portal per subscription before the starter kit commits to an EU region list.
2. **Run-mode count/name contradiction (§5c)** — "Review/Autonomous" (2) vs. `actionConfiguration.mode` = `Review/Automatic/ReadOnly` (3) vs. FAQ's "Reader mode" wording. Recommend validating the actual portal UI (not just docs) before the starter kit's governance section is finalized.
3. **User-role count contradiction (§5a)** — four portal roles (`user-roles`) vs. three API-reference roles (`api-reference`, missing Author). Author's ARM-vs-portal capability mismatch is itself documented as a known gap, not just an inconsistency between pages.
4. **Trial/pricing contradiction (§1, §10)** — evaluate-trial doc vs. pricing-page FAQ. No retail $/€ rate found; flagged, not fabricated.
5. **Tool Access Policy precedence** — ~~resolved~~. Full page fetched this pass (`azure/sre-agent/tool-access-policies`); exact precedence and evaluation order is now documented in §9g. **Key takeaway retained as a flag, not a gap:** run mode is the lowest-priority control — do not present "Review mode" alone as sufficient write-prevention in the starter kit; Global Deny tool-access policy is the actual enforcement mechanism.
6. **EU-region sandbox isolation specifics (§9f)** — `security-overview` was seen only via search snippet (regional sandbox pinning example used East US 2, not an EU region); a full fetch is recommended before asserting EU-region sandbox data never leaves the EU/EFTA boundary.
7. **Data residency for search indexes in EU regions** — the cross-region placement table in `data-privacy` lists exceptions only for US/India regions; absence of an EU-region row implies in-region storage but this is an inference, not an explicit statement — flagged for customer confirmation if contractually material.
8. **No GA date found** — no Microsoft Learn "what's new"/announcement page confirming a formal GA date for the overall SRE Agent product was located in this pass (searches returned unrelated Azure Pipelines/DevOps "GA" results); the product's actual release-state label (GA vs. preview vs. "early access") beyond the per-feature preview flags in §1 remains **unconfirmed** — recommend checking `azure.microsoft.com/en-us/updates/` or the product's official blog directly if an authoritative GA/preview label is a hard requirement for the starter kit's cover page.
9. Per the user's explicit instruction, **Subscription Vending, AI Landing Zones, and the AKS accelerator were not independently re-verified** in this file beyond the brief CAF/ALZ landing-zone-accelerator pointers already on record from the prior research turn (`aka.ms/alz/accelerator`, `Azure/bicep-lz-vending` sub-vending AVM module, `aka.ms/avm`) — if the starter kit needs precise, current setup steps for those three items, a dedicated follow-up fetch pass is required; this report should not be cited as authoritative for them.

---

## 12. Primary source URLs cited in this report

- https://learn.microsoft.com/azure/sre-agent/overview
- https://learn.microsoft.com/azure/sre-agent/create-and-set-up
- https://learn.microsoft.com/azure/sre-agent/usage
- https://learn.microsoft.com/azure/sre-agent/supported-regions
- https://learn.microsoft.com/azure/sre-agent/faq
- https://learn.microsoft.com/azure/sre-agent/faq-troubleshooting
- https://learn.microsoft.com/azure/sre-agent/data-privacy
- https://learn.microsoft.com/azure/sre-agent/model-provider-selection
- https://learn.microsoft.com/azure/sre-agent/permissions
- https://learn.microsoft.com/azure/sre-agent/user-roles
- https://learn.microsoft.com/azure/sre-agent/run-modes
- https://learn.microsoft.com/azure/sre-agent/api-reference
- https://learn.microsoft.com/azure/sre-agent/connectors
- https://learn.microsoft.com/azure/sre-agent/managed-connectors
- https://learn.microsoft.com/azure/sre-agent/incident-platforms
- https://learn.microsoft.com/azure/sre-agent/network-integration
- https://learn.microsoft.com/azure/sre-agent/network-requirements
- https://learn.microsoft.com/azure/sre-agent/configure-network-controls
- https://learn.microsoft.com/azure/sre-agent/security-overview
- https://learn.microsoft.com/azure/sre-agent/connect-github-enterprise-cloud
- https://learn.microsoft.com/azure/sre-agent/tool-access-policies
- https://learn.microsoft.com/azure/sre-agent/response-plan
- https://learn.microsoft.com/azure/sre-agent/azure-monitor-alerts
- https://learn.microsoft.com/azure/sre-agent/pricing-billing
- https://learn.microsoft.com/azure/sre-agent/evaluate
- https://azure.microsoft.com/en-us/pricing/details/sre-agent/
- https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/implementation-options (context only, not re-verified this pass)

*(End of report.)*
