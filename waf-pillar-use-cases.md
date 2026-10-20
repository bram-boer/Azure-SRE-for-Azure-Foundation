# WAF pillar use cases: one per pillar

**Reference date: 20-10-2026.** This file contains five deep-dive use cases, one for each [Azure Well-Architected Framework](https://aka.ms/waf) pillar. Each one looks at the shared Azure foundation from a **platform point of view**:
- ALZ platform
- subscription vending
- the AI landing zone
- the AKS accelerator

Each use case maps to the official WAF checklist codes. Each also reuses the [common contract and execution contract](use-cases.md), the [setup guide](setup-guide.md), and the [agent-topology rules](agent-topology.md).

**Positioning:**
- These use cases do **not** replace the [Azure Well-Architected Review assessment](https://learn.microsoft.com/en-us/assessments/azure-architecture-review/), Azure Advisor, Defender for Cloud, Cost Management, or a SOC.
- The agent turns their signals into **recurring, evidence-backed, owner-routed findings** for each landing zone.
- The CCoE uses those findings in its governance cadence.

All five use cases start **read-only, with each scheduled task and response plan explicitly set to Review**. New tasks and plans default to Autonomous.

## Overview

| ID | WAF pillar | Use case | Primary checklist codes | Trigger | Extends |
|---|---|---|---|---|---|
| W1 | Reliability | Platform resilience and recovery-readiness review | RE:03, RE:04, RE:05, RE:09, RE:10 | Weekly scheduled task; Resource Health / Service Health alert | UC10 |
| W2 | Security | Security baseline drift and exposure triage | SE:01, SE:04, SE:05, SE:06, SE:08, SE:10 | Daily scheduled task; new high-severity recommendation | UC02 |
| W3 | Cost Optimization | Landing-zone cost anomaly and waste review | CO:03, CO:04, CO:07, CO:08, CO:10, CO:14 | Cost anomaly/budget alert; weekly scheduled task | UC11 |
| W4 | Operational Excellence | Post-deployment health gate and out-of-band change detection | OE:05, OE:06, OE:08, OE:10, OE:11 | HTTP trigger after a pipeline run; daily scheduled task | UC04 |
| W5 | Performance Efficiency | Shared-platform capacity and quota headroom | PE:01, PE:02, PE:04, PE:05, PE:11 | Weekly scheduled task; throttling or scale-failure alert | UC07, UC08 |

**Agent placement:** all five run in the **platform-operations agent**. Each runs as its own custom agent (`waf-reliability`, `waf-security`, `waf-cost`, `waf-opex`, `waf-performance`) with a scheduled task or response plan. Separate agents are needed only when an [A1-A7 trigger](agent-topology.md#2-requirements-that-trigger-a-separate-agent) applies. Typical cases:
- **W2:** a SOC or security team that runs its own on-call, or that requires a separate identity or approver group (A1/A2).
- **W3:** a FinOps team that requires its own budget cap (A5).

**Common prerequisite:** Resource Graph queries need Reader on the target scope and a tool path the agent can use, such as Azure CLI `az graph query` (needs the `resource-graph` extension) or `az rest` against the Resource Graph REST API, if the tool is allowed. If no approved tool path exists, supply a scheduled export as knowledge. Cost data needs Cost Management Reader, or an export. Validate both in the [effective-access test](setup-guide.md#4-prove-effective-access-not-labels). All example queries are in [queries\starter-queries.kql](queries/starter-queries.kql).

---

## W1 - Reliability: platform resilience and recovery-readiness review

**Owner:** platform reliability lead. Each workload or landing-zone owner accepts their own risks.

**Question it answers:** "Can our shared platform services and accelerator deployments actually meet the reliability tier we promised each landing zone?"

**Why this pillar:**
- **RE:04:** targets must exist before they can be measured.
- **RE:05:** check redundancy, such as zones and instances.
- **RE:09:** DR must be tested, not just configured.
- **RE:10:** health must be continuously measured.
- **RE:03:** each finding links to a failure mode.

**Signals and evidence:**
- Advisor **HighAvailability** recommendations (`advisorresources`).
- Zone configuration of hub/shared resources: Azure Firewall, Application Gateway, public IPs, gateways (SKU ending in `AZ`), Private DNS Resolver, Key Vault, and AKS node pools (`properties.agentPoolProfiles[].availabilityZones`).
- Resource Health availability history (`healthresources`) and Service Health events.
- Backup job and restore-test evidence (UC10), ASR replication health, and the declared tier/RTO/RPO tag from vending.

**Set up:**
1. **Declare targets in vending.** Add a `reliability-tier` tag (for example T1-T3) and an RTO/RPO reference to the vending request and the acceptance manifest (UC02). Without targets this use case can only report configuration, not risk (RE:04).
2. **Write a tier matrix** as a knowledge file. For each tier, list the minimum controls: zone-redundant SKUs, minimum instance or node count, backup policy, cross-region DR pattern, and restore-test frequency. Base it on the [WAF service guides](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/) for the services you run (for example [AKS](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-kubernetes-service)).
3. **Create the `waf-reliability` custom agent.** Its instruction: compare the actual configuration against the tier matrix. Each finding records:
   - the gap
   - the failure mode it exposes (RE:03)
   - the affected flows or landing zones
   - the evidence
   - a recommended IaC change
   - the owner
4. **Add a weekly scheduled task in Review mode.** Scope it to the platform/connectivity subscriptions plus a sample of vended landing zones. Add a response plan for Resource Health "Unavailable/Degraded" alerts on shared hub services.
5. **Route the output** as a reliability risk register entry per landing zone. Changes go through the ALZ/AKS IaC pipeline. **Fault injection** (RE:08) is out of scope for the agent. Run it with [Azure Chaos Studio](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-overview) in an approved environment, and let the agent analyze the results.

**Example prompt:** "For the subscriptions in scope, list shared platform resources whose zone or instance configuration does not meet the tier matrix for their `reliability-tier` tag. Add open HighAvailability Advisor recommendations, and landing zones with no restore test in the required interval. For each gap, state the failure mode, evidence, owner, and the IaC change. Do not modify resources."

**Exercise / pass:** in a sandbox, deploy a non-zonal public IP or a single-node AKS pool into a T1-tagged landing zone. The weekly report flags it with the correct tier rule, failure mode, and owner. No resource is changed.

**Measures:** percentage of T1/T2 landing zones that meet the tier matrix; open HighAvailability recommendations by age; restore tests within interval; mean time to detect a reliability gap after vending.

**Benefit:** the **CCoE** gets an evidence-based view of reliability promises versus reality per landing zone. **Platform teams** find single points of failure before an incident, not during one.

**Basis:** [Reliability checklist](https://learn.microsoft.com/en-us/azure/well-architected/reliability/checklist); [Advisor reliability](https://learn.microsoft.com/en-us/azure/advisor/advisor-high-availability-recommendations); [Resource Health](https://learn.microsoft.com/en-us/azure/service-health/resource-health-overview).

## W2 - Security: security baseline drift and exposure triage

**Owner:** platform security owner. Security exceptions stay with the security governance process. **SecOps/SOC** keeps ownership of threat detection and response (SE:10, SE:12).

**Question it answers:** "Which landing zones have drifted from the ALZ security baseline or opened new exposure, who owns the fix, and how urgent is it?"

**Why this pillar:**
- **SE:01:** measure against the baseline.
- **SE:04 and SE:06:** check segmentation and network exposure.
- **SE:05:** check privileged access.
- **SE:08:** check hardening.

The agent **triages posture**; it does not hunt threats.

**Signals and evidence:**
- Defender for Cloud secure score and unhealthy high-severity assessments (`securityresources`).
- Noncompliance on ALZ security policy initiatives (`policyresources`, UC02).
- PaaS resources with `publicNetworkAccess = Enabled` where the landing-zone archetype (corp/online) forbids it.
- New Owner, Contributor, or User Access Administrator assignments at subscription scope (Activity Log `Microsoft.Authorization/roleAssignments/write`).

**Set up:**
1. **Capture the baseline** as a knowledge file: per archetype (corp, online, AI, AKS), the required policy initiatives, network exposure rules, privileged-role rules (PIM-only, no standing Owner), and the Defender plans expected.
2. **Create the `waf-security` custom agent.** Its instruction: classify each finding as exposure, drift, identity, or hardening. Map it to the SE code, the archetype rule, the evidence, and the owner. Mark as "accepted exception" only when an exemption with an expiry date exists.
3. **Add a daily scheduled task in Review mode.** Add a response plan for a Defender-for-Cloud high-severity *recommendation* alert if you route those through Azure Monitor. Do **not** route Defender *security alerts* (threats) to this agent; they belong in the SOC process or SIEM.
4. **Apply guardrails:**
   - Deny write tools for this custom agent through tool access policies.
   - Never grant, remove, or exempt access.
   - Remove secrets and tokens from evidence.
   - Exposure findings on critical-infrastructure scopes go to the security owner immediately, not into a weekly batch.
5. **Route** each finding to the landing-zone owner through the standard work-item process. Close it when policy or Defender re-evaluation shows it as healthy.

**Example prompt:** "Since yesterday, list in-scope landing zones with new high-severity unhealthy Defender assessments, new public network access on PaaS resources in corp archetypes, or new privileged role assignments at subscription scope. Classify each finding, map it to the SE checklist code and the baseline rule, and name the owner. Do not change access or create exemptions."

**Exercise / pass:** in a sandbox corp landing zone, enable public network access on a storage account. The daily task classifies it as exposure (SE:06) with the correct owner and evidence. No change or exemption is made by the agent.

**Measures:** secure-score trend per landing zone; mean time from drift to owner acknowledgement; baseline deviations older than 30 days; standing privileged assignments.

**Benefit:** the **CCoE** sees baseline adherence across all vended subscriptions without manual reviews. **Platform and security teams** get triaged, owner-routed findings instead of raw recommendation lists.

**Basis:** [Security checklist](https://learn.microsoft.com/en-us/azure/well-architected/security/checklist); [Defender for Cloud secure score](https://learn.microsoft.com/en-us/azure/defender-for-cloud/secure-score-security-controls); [ALZ security design area](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/security).

## W3 - Cost Optimization: landing-zone cost anomaly and waste review

**Owner:** FinOps lead or platform cost owner. Landing-zone owners own their spend.

**Question it answers:** "Why did this landing zone's spend deviate, and what platform waste can we remove safely?"

**Why this pillar:**
- **CO:03:** review daily cost data and detect anomalies.
- **CO:04:** set guardrails such as budgets and policy.
- **CO:07:** remove unused components.
- **CO:08:** right-size non-prod environments.
- **CO:10:** manage log and data retention cost.
- **CO:14:** consolidate shared resources.

**Signals and evidence:**
- Cost Management anomaly alerts and budget alerts per vended subscription. Vending should create the budget.
- Advisor **Cost** recommendations with estimated savings.
- Orphaned resources: unattached disks, unassociated public IPs, empty App Service plans, idle gateways.
- Log Analytics ingestion by table (`Usage`).
- AKS node utilization; AI provisioned-throughput (PTU) utilization.
- The SRE Agent's own AAU consumption.

**Set up:**
1. **Make vending create a budget and alert** for every subscription, with the owner and cost-center tags (CO:04). This use case depends on that baseline.
2. **Give the agent read-only cost evidence:** Cost Management Reader, or a scheduled cost export, plus Reader for Resource Graph. Confirm the agent's tool path can read cost data before relying on it.
3. **Create the `waf-cost` custom agent.** Its instruction: for anomalies, explain the driver (meter, resource, change, or volume) with evidence. For waste, list candidates with estimated monthly savings in **EUR**, the risk of removal, and the owner. Never delete; propose only.
4. **Add a response plan** for anomaly and budget alerts, plus a **weekly scheduled task** for waste and the Advisor Cost review. Both in Review mode.
5. **Feed approved findings** into the FinOps backlog. Removal or resizing happens through IaC or the owner after confirmation. Non-prod schedule changes (CO:08) need the environment owner's agreement.

**Example prompt:** "For the anomaly alert on subscription X, identify the meters and resources responsible for the increase compared with the previous 14 days, and correlate it with changes and deployments. Then list orphaned resources and open Advisor Cost recommendations in scope, with estimated monthly savings in EUR, removal risk, and owner. Do not delete or resize anything."

**Exercise / pass:** in a sandbox, leave an unattached managed disk and an unassociated public IP, and generate a Log Analytics ingestion spike. The weekly report lists all three with savings estimates and owners. The anomaly analysis names the responsible table.

**Measures:** time from anomaly to explained driver; savings identified versus realized per month; orphaned resource count; percentage of vended subscriptions with budgets; cost of the agent itself versus savings.

**Benefit:** the **CCoE** sees cost accountability per landing zone, with explained anomalies. **Platform teams** spend less time digging through cost analysis, and get a safe waste-removal backlog.

**Basis:** [Cost Optimization checklist](https://learn.microsoft.com/en-us/azure/well-architected/cost-optimization/checklist); [cost anomalies](https://learn.microsoft.com/en-us/azure/cost-management-billing/understand/analyze-unexpected-charges); [Advisor cost](https://learn.microsoft.com/en-us/azure/advisor/advisor-cost-recommendations).

## W4 - Operational Excellence: post-deployment health gate and out-of-band change detection

**Owner:** platform engineering or DevOps lead, who owns the ALZ, vending, and AKS pipelines.

**Question it answers:** "Did this platform deployment leave the environment healthy, and which changes bypassed our IaC pipelines?"

**Why this pillar:**
- **OE:05:** IaC is the source of truth.
- **OE:06:** the supply chain promotes changes through gates.
- **OE:11:** safe deployment with health validation and rollback.
- **OE:08:** structured incident handling.
- **OE:10:** reliable automation.

**Signals and evidence:**
- Pipeline completion events (deployment name, commit, and scope).
- `resourcechanges` in Resource Graph, using `clientType` and `changedBy` to separate pipeline from portal/CLI changes. Retention is limited (about 14 days), so export it if needed.
- Activity Log, AMBA alerts fired after the deployment, Resource Health, and policy compliance change.

**Set up:**
1. **Call the agent's HTTP trigger** as a non-blocking step after the ALZ, vending, or AKS pipeline deploys. Pass the deployment ID, commit, scope, and time window. Keep the pipeline's own gates authoritative. The agent's verdict is advisory until it is proven.
2. **Create the `waf-opex` custom agent.** Its instruction: compare post-deployment health (new alerts, Resource Health, policy noncompliance, error rates) against the pre-deployment window. Return **Healthy / Investigate / Recommend rollback**, with evidence. Every rollback goes through the pipeline and is decided by the release owner.
3. **Add a daily scheduled task** to detect **out-of-band changes**: changes in platform subscriptions whose `clientType` or `changedBy` is not the pipeline identity. Report each one with the resource, the actor, and the matching IaC file to reconcile.
4. **Record each deployment verdict** with the release record (OE:08), and turn repeat failures into pipeline test improvements (OE:09).
5. **Start in Review mode.** Do not let the agent re-run pipelines or approve releases. Pipeline triggering is a separate, authorized integration.

**Example prompt:** "Deployment D finished at time T in scope S. Compare alerts, Resource Health, and policy compliance for the 60 minutes before and after T. Return Healthy, Investigate, or Recommend rollback, with evidence and the owning stage. Separately, list changes in platform subscriptions in the last 24 hours that were not made by the pipeline identity."

**Exercise / pass:** in a sandbox, (a) deploy a change that triggers a known AMBA alert. The agent returns "Investigate" or "Recommend rollback" with the alert as evidence. (b) Make a manual portal change to an NSG rule. The daily task lists it as out-of-band, with the actor.

**Measures:** change failure rate; time to detect a bad deployment; out-of-band changes per month, trending down; drift reconciled in IaC within the target time.

**Benefit:** the **CCoE** gets evidence that "IaC-only" is followed, plus a measurable change-failure rate. **Platform teams** catch bad releases quickly and spend less effort on ClickOps drift.

**Basis:** [Operational Excellence checklist](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/checklist); [safe deployments (OE:11)](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/safe-deployments); [Resource Graph change analysis](https://learn.microsoft.com/en-us/azure/governance/resource-graph/how-to/get-resource-changes); [SRE Agent HTTP triggers](https://learn.microsoft.com/en-us/azure/sre-agent/http-triggers).

## W5 - Performance Efficiency: shared-platform capacity and quota headroom

**Owner:** platform capacity owner. The AI platform owner covers model quotas; the AKS platform owner covers cluster capacity.

**Question it answers:** "Before the next landing zones or workloads arrive, do the shared platform and accelerators have enough capacity, quota, and address space? Where are we already throttled?"

**Why this pillar:**
- **PE:01:** targets for platform flows.
- **PE:02:** capacity planning before demand.
- **PE:04:** consistent measurement.
- **PE:05:** scale units.
- **PE:11:** respond to live issues.

At platform level, performance often fails on **limits**, not CPU.

**Signals and evidence:**
- Subscription and regional quotas (vCPU per family, AI model TPM/PTU) via the Azure Quotas API.
- Subnet IP usage in hub and spoke networks (`az network vnet list-usage`).
- Azure Firewall throughput and SNAT metrics; gateway bandwidth.
- AKS scheduling and scale failures (`KubeEvents`).
- AI throttling (HTTP 429) metrics.
- The pipeline of upcoming vending requests.

**Set up:**
1. **Write a capacity plan** as a knowledge file (PE:02). Include the expected landing zones per quarter, the AKS node growth, the AI model and region plan, the IP address plan, and the headroom threshold that triggers action (for example 70% warning, 85% critical).
2. **Create the `waf-performance` custom agent.** Its instruction: for each limit, report usage, threshold, trend, projected exhaustion date, and owner. Distinguish **quota** from **capacity** from **throttling** from **misconfiguration** (as in UC07/UC08).
3. **Add a weekly scheduled task** for headroom. Add response plans for AI 429 alerts and AKS scale-failure alerts. Both in Review mode.
4. **Output** a capacity request (quota increase, new subnet range, scale-unit change) through the normal process. The agent never files support or quota requests itself.
5. **Each quarter, compare** the forecast with actuals, and update the capacity plan and vending intake.

**Example prompt:** "For the in-scope subscriptions and regions, report vCPU and AI model quota usage, subnet address usage in hub and spoke networks, and AKS scheduling or scale failures in the last 7 days. For each limit, give usage, threshold, trend, projected exhaustion date, and owner. Classify throttling as quota, capacity, or configuration. Do not request quota changes."

**Exercise / pass:** in a sandbox, fill a small AKS subnet, or set a low node-pool max count and schedule pods beyond it. The task reports the `FailedScheduling` or scale failure, classifies it correctly, and names the owner and the next action.

**Measures:** limits above the warning threshold; incidents caused by quota or address exhaustion (target: zero); lead time between a capacity warning and resolution; time to classify throttling.

**Benefit:** the **CCoE** can scale the vending pipeline and accelerators without capacity surprises, and plan investment from evidence. **Platform, AI, and AKS teams** get early warnings and faster classification of throttling.

**Basis:** [Performance Efficiency checklist](https://learn.microsoft.com/en-us/azure/well-architected/performance-efficiency/checklist); [Azure quotas](https://learn.microsoft.com/en-us/azure/quotas/quotas-overview); [AKS baseline](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks/baseline-aks).

---

## Rollout order

| Phase | Use cases | Rationale |
|---|---|---|
| 1 | W4 (out-of-band changes), W2 | Lowest data dependency (Resource Graph and Activity Log). The CCoE governance value is immediately visible. |
| 2 | W3, W5 | Need cost data access and a capacity plan, but deliver quick, measurable value. |
| 3 | W1, W4 health gate | Need reliability tiers declared in vending and a pipeline HTTP-trigger integration. |

**Combined output:** feed the five pillar reports into UC12 (incident-to-WAF loop), and into a quarterly **WAF posture review per landing zone** for the CCoE. Use the [Well-Architected Review](https://learn.microsoft.com/en-us/assessments/azure-architecture-review/) for the formal assessment; the agent supplies the evidence between assessments.
