# Platform use-case catalogue

**Reference design, 20-10-2026.** These are proposed operational patterns using Microsoft frameworks, not a Microsoft-certified solution or a list of native SRE Agent integrations. Follow [the shared setup](setup-guide.md) first. Start with manual, read-only investigations; automate incident intake only after the same investigation works and scope checks pass.

**Common contract for every case:** approved resource IDs and UTC time window; signal and source link; observed versus expected behavior; evidence-backed hypothesis with uncertainty; missing evidence; platform/workload owner; proposed action, approval, validation, and rollback. Record incident/thread IDs in the team's system of record. An empty query result is not proof of health. Test production-affecting failures only in an approved isolated environment.

**Execution contract:** SRE Agent investigates. Existing ALZ/vending/accelerator pipelines remain authoritative for change. Human-created change requests are sufficient for this starter kit. Automatic PR creation, pipeline triggering, cost exports, and scorecards require separately authorized integration; no such connector is deployed here.

## Prioritization and benefit map

Benefits below are hypotheses to measure against a pre-pilot baseline, not product guarantees. CAF/ALZ supplies enterprise/platform governance; WAF assesses the quality of platform services as workloads and the applications consuming them.

| ID / priority | Use case | CAF/ALZ area | Primary WAF pillars | CCoE benefit | Platform / Azure team benefit | Agent placement |
|---|---|---|---|---|---|---|
| UC01 / P1 | Subscription-vending failure triage | Subscription organization; automation | Operational Excellence, Reliability | Standardized onboarding evidence and exception handling | Less time reconstructing failed pipeline stages | Combine - platform agent |
| UC02 / P1 | Vended subscription readiness and drift | Governance; identity; management | Security, Operational Excellence | Consistent baseline and exception register | Faster, explicit go/no-go handover | Combine - platform agent |
| UC03 / P1 | Shared DNS and private connectivity | Networking | Reliability, Security | Safer handling of shared-service blast radius | Faster separation of DNS, routing, policy, and service issues | Combine - platform agent |
| UC04 / P1 | Change-correlated platform incidents | Platform automation | Reliability, Operational Excellence | Auditable change-to-incident feedback | Faster identification of suspect changes | Combine - platform agent (orchestrator) |
| UC05 / P1 | Monitoring onboarding and blind spots | Management | Operational Excellence, Reliability | Coverage rather than dashboard-count reporting | Fewer incidents with missing evidence | Combine - platform agent |
| UC06 / P2 | AI landing-zone platform onboarding | Networking; identity; governance | Security, Reliability | Reusable AI platform acceptance criteria | Faster escalation of private endpoint, DNS, or identity faults | Combine; split if separate AI team, model/residency or boundary |
| UC07 / P2 | AI platform capacity and throttling | Subscription organization; management | Performance Efficiency, Cost Optimization | Evidence-based quota/capacity investment | Distinguish quota, deployment, throttling, and dependency failure | Combine with UC06 wherever the AI platform agent lives |
| UC08 / P1 | AKS baseline node/pod platform triage | Management; networking | Reliability, Performance Efficiency | Consistent managed-platform support boundary | Less manual correlation of node, pod, and Azure events | Combine; split if dedicated AKS team, network path or incident platform |
| UC09 / P2 | AKS upgrade readiness and regression | Automation; management | Reliability, Operational Excellence | Controlled lifecycle and accountable risk acceptance | Safer upgrade preparation and rollback decisions | Combine with UC08 wherever the AKS agent lives |
| UC10 / P2 | Platform backup and restore assurance | Management; business continuity | Reliability, Security | Evidence of recoverability, not just backup configuration | Faster diagnosis of failed jobs and test restores | Combine - platform agent |
| UC11 / P2 | Platform cost and telemetry anomaly | Governance; management | Cost Optimization, Performance Efficiency | Cost attribution and optimization backlog | Isolate ingestion, scale, and agent-usage cost drivers | Combine; split only for separate FinOps budget/team |
| UC12 / P1 | Incident-to-WAF improvement loop | Governance; platform automation | All five pillars | Repeatable evidence for governance reviews | Less manual incident narrative and runbook upkeep | Combine - runs in every agent |

**Agent placement:** by default all twelve use cases run in **one platform-operations agent**, each as a custom agent, response plan, or scheduled task. Split to a separate agent only for a recorded trigger: team/on-call, permissions boundary, incident platform, model/data residency, budget, tenant, or hosting region/network. Production versus test alone is not a trigger while the agent is read-only and in Review mode. With write access or Autonomous plans, separate prod and non-prod. Details and implementation per use case: [agent-topology.md](agent-topology.md#5-per-use-case-placement).

## UC01 - Subscription-vending failure triage

**Owner:** subscription-vending service owner; billing/subscription administrator retains creation authority. **Signal:** failed vending workflow, stuck stage, or onboarding target exceeded.

**Set up:**
1. Inventory the real vending workflow: request validation, authorization, subscription creation or reuse, management-group placement, baseline policy, networking, diagnostics, and handover. Record which steps are implemented and their owners.
2. Retain sanitized GitHub Actions/Azure DevOps run logs, deployment operation errors, request ID, subscription ID, and timestamps. Never pass PATs, OIDC tokens, or raw secret-bearing pipeline variables to the agent.
3. Provide an approved log extract and runbook through supported knowledge/chat features. Azure Activity Log shows Azure operations, not every CI stage; use the correct CI evidence. A CI-to-SRE trigger is a custom integration unless explicitly supported in your deployment.
4. Ask the agent to classify policy denial, RBAC, invalid input, subscription/billing constraints, quota, throttling, and transient provider error. It must cite the failed operation and explain which evidence is missing.
5. Let the pipeline owner approve a corrected request or code change and re-run only the failed/idempotent stage. Do not create a replacement subscription automatically.

**Exercise / pass:** feed a known sandbox policy-denied deployment. The report identifies the assignment/error and correct owner; no automatic policy exemption, RBAC grant, or billing action occurs. The corrected run reaches the documented acceptance checks.

**Measure:** median/p90 time from workflow failure to correct owning team; repeat-run success; duplicate subscriptions; misrouted escalations. **Prompt:** "Using this sanitized failed vending run and approved subscription scope, identify the failing stage and evidence. Propose the smallest pipeline/request correction; do not create subscriptions, grant access, or change policy."

**Basis:** [CAF vending guidance](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/subscription-vending); [ALZ IaC accelerator](https://azure.github.io/Azure-Landing-Zones/accelerator/).

## UC02 - Vended subscription readiness and drift

**Owner:** platform governance owner; security owns security exceptions. **Signal:** vending handover, periodic baseline review, or new Policy noncompliance.

**Set up:**
1. Define the acceptance manifest: intended management group; policy assignments and approved exemptions; owner/cost tags; monitoring destination; budget owner; network/IPAM allocation; authorized RBAC; Defender configuration where required.
2. Capture desired state from version-controlled ALZ/vending configuration. Query actual inventory and Policy state through Azure Resource Graph/Policy using the approved scope. Include evaluation timestamps: policy results are not instantaneous.
3. Compare effective/inherited state, not only resource-local settings. Use the PolicyResources example in `queries\starter-queries.kql` in **Resource Graph**, not Log Analytics.
4. Ask SRE Agent to produce "pass / fail / unknown / accepted exception" per criterion, linked to evidence. A manual evidence bundle is acceptable if no approved query tool is available.
5. Reject handover on missing required evidence. Correct via the existing pipeline; policy remediation tasks or identity changes require their own explicit authority.

**Exercise / pass:** omit a required tag from an approved sandbox resource. Detect the relevant noncompliance after policy evaluation, identify the owner, and confirm correction without granting access or creating an exemption.

**Measure:** first-pass handover rate; critical baseline coverage; time-to-correct; exception age. **Benefit:** CCoE receives a defensible acceptance decision; teams avoid discovering missing diagnostics during an incident.

**Basis:** [ALZ design areas](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-areas); [Azure Policy overview](https://learn.microsoft.com/en-us/azure/governance/policy/overview).

## UC03 - Shared DNS and private-endpoint connectivity

**Owner:** central network/DNS platform team; application owner supplies the failing flow. **Signal:** approved synthetic transaction fails or Connection Monitor reports a failure.

**Set up:**
1. Publish expected source subnet, destination FQDN, private endpoint/IP, private DNS zone/link, forwarding path, ports, UDR/firewall path, and workload owner. Use a dependency map rather than exposing all network inventories.
2. Enable the relevant existing network monitoring: Connection Monitor where supported, firewall diagnostic logs, and endpoint/service metrics. Keep probe credentials out of runbooks.
3. Collect DNS resolution and connectivity results **from the affected network path** using the approved probe or operator. An agent-side shell test outside that VNet is not equivalent.
4. Ask the agent to correlate recent network changes and distinguish name resolution, route/NSG/firewall denial, endpoint approval, service authorization, and provider outage.
5. Network owner reviews changes to private DNS, peering, UDRs, firewalls, or endpoint configuration through IaC. Never "fix" the issue by opening public access or disabling a firewall.

**Exercise / pass:** use a deliberately misconfigured DNS record/link in a dedicated test zone. The report identifies the wrong resolution path. Restore only that sandbox configuration and prove the end-to-end probe recovers.

**Measure:** time to localize fault; correct network/workload attribution; shared-service change failure rate. **Benefit:** faster troubleshooting without expanding the blast radius.

**Basis:** [Network Watcher](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-overview); [AI platform networking guidance in the AI landing-zone accelerator](https://github.com/Azure/AI-Landing-Zones).

## UC04 - Change-correlated platform incident

**Owner:** platform incident commander and the relevant change owner. **Signal:** meaningful service-health/SLO alert after a release.

**Set up:**
1. Export subscription Activity Logs, retain deployment/run identifiers, and preserve workload error/latency metrics. Align timestamps to UTC and record monitoring lag.
2. Start with the failed-operation and successful-write queries supplied in this kit. Add a specific resource ID and bounded incident window before use.
3. Ask the agent to construct a timeline and rank suspect changes by affected resources and dependency evidence. "A write occurred first" is correlation, not a proven root cause.
4. Have the change owner assess last-known-good state, stateful migration risks, and rollback versus roll-forward. Follow established emergency-change procedures.
5. Validate recovery against the original synthetic/user flow and error/latency signal, not merely a successful deployment.

**Exercise / pass:** replay a known sandbox deployment regression. The agent identifies the relevant run and explicitly separates observations from hypothesis. An authorized rollback or fix restores the health signal.

**Measure:** time-to-first-supported-hypothesis; percentage of findings accepted by responders; change-related recurrence. **Benefit:** auditable feedback from incidents into release quality.

**Basis:** [WAF safe deployments, OE:11](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/safe-deployments).

## UC05 - Monitoring onboarding and blind spots

**Owner:** observability platform team; each resource owner owns telemetry content. **Signal:** new subscription/cluster handover, absent expected telemetry, or a failed test alert.

**Set up:**
1. Define required coverage by resource type using the existing ALZ monitoring baseline and AMBA where appropriate. Include telemetry freshness, alert ownership, and notification delivery.
2. Verify diagnostic policy assignments/remediation, DCR associations/agents where needed, resource-specific logs, managed Prometheus, workspace authorization, retention, and private DNS/connectivity.
3. Compare inventory with actual expected signals. Absence of records may mean no events, disabled collection, ingestion lag, filtering, or access denial; require an independent source test.
4. Send a harmless sandbox event and test alert. Prove both human on-call delivery and SRE incident intake; a working email alone does not prove agent intake.
5. Track missing coverage as a handover defect; repair using the standard onboarding pipeline. Do not suppress security/audit logs to reduce noise.

**Exercise / pass:** use an intentionally uninstrumented sandbox resource and detect its absence, then onboard and prove the known event and test alert arrive.

**Measure:** critical-resource coverage; evidence freshness; end-to-end alert test success; time to repair a collection gap. **Benefit:** CCoE reports operational readiness; teams get usable evidence when paged.

**Basis:** [AMBA](https://azure.github.io/azure-monitor-baseline-alerts/); [WAF observability, OE:07](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/observability).

## UC06 - AI landing-zone platform acceptance

**Owner:** AI platform team with network, identity, and security owners. **Signal:** new AI landing-zone deployment or failed approved dependency test.

**Status/boundary:** the Microsoft AI landing-zone accelerator is explicitly **preview** in the researched repository. It provisions an application/workload landing-zone foundation. The central platform team supplies its governance, connectivity, identities, and operational contract; it does not become a second ALZ platform hierarchy.

**Set up:**
1. Pin the approved AI landing-zone accelerator version and selected scenario. Record its actual deployed services, regions, identities, dependencies, private endpoints, DNS, and egress design; not every deployment has identical services.
2. Define platform acceptance tests: authorized managed-identity authentication, required private resolution, approved network reachability, diagnostic coverage, policy compliance, and available service/deployment capacity.
3. Use synthetic non-sensitive test input. Never ingest production prompts, generated content, secrets, or customer documents into troubleshooting context without separate data approval.
4. Supply failed deployment operations, sanitized service diagnostics, and **source-network** test results. Ask the agent to localize platform versus model/application failures.
5. Apply a correction through the accelerator/IaC repository and re-run the acceptance suite. Workload teams remain responsible for model quality, application safety, and business behavior.

**Exercise / pass:** break an isolated test private-DNS association, detect the resulting dependency failure, restore via approved IaC, and verify private resolution plus the authorized synthetic request.

**Measure:** AI platform time-to-ready; handover defect rate; repeat DNS/identity incidents. **Benefit:** reusable AI guardrails without confusing SRE operations with AI governance.

**Basis:** [Microsoft AI landing zones](https://github.com/Azure/AI-Landing-Zones); [CAF AI ready guidance](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ai/ready).

## UC07 - AI platform capacity and throttling

**Owner:** AI platform capacity owner; workload owner sets demand/SLO; FinOps approves cost implications. **Signal:** elevated throttling, request failures, latency, or rejected deployments.

**Set up:**
1. Inventory the selected provider/model deployment type, assigned quotas, limits, region, actual utilization, and scale/reservation commitments. Do not assume quota implies physical capacity.
2. Enable the specific service's supported metrics and sanitized diagnostics. Record status/error codes and retry behavior without logging prompt contents.
3. Ask the agent to distinguish rate limits, token/request limits, backend capacity, failed deployment, network errors, and application retry storms. Compare demand with the approved service limits and time window.
4. Propose quota requests, load shaping, approved retry/backoff, or capacity changes as options with cost and residency implications. No automatic region/model switch or reservation purchase.
5. The capacity and workload owners approve changes and repeat a bounded load test against agreed latency/error targets.

**Exercise / pass:** run an approved capped synthetic load or replay a sanitized historical throttling incident. The correct constraint is identified; no uncontrolled scale-out or spend occurs.

**Measure:** throttled-request ratio; p95 latency; quota lead time; capacity headroom; cost per approved transaction. **Benefit:** evidence-driven investment rather than reflexive overprovisioning.

**Basis:** [AI landing-zone accelerator](https://github.com/Azure/AI-Landing-Zones); [WAF Performance Efficiency](https://learn.microsoft.com/en-us/azure/well-architected/performance-efficiency/).

## UC08 - AKS platform triage

**Owner:** AKS platform team owns cluster/node/system services; workload team owns application manifests and code. **Signal:** node readiness, pod availability, API/system-service health, or meaningful application-flow alert.

**Set up:**
1. Record the actual AKS accelerator/baseline variant, private API access, node pools, CNI/IP allocation, identities, registry, DNS, storage dependencies, and support boundaries.
2. Enable the approved mix of Container Insights, managed Prometheus, AKS control-plane diagnostic logs, and Activity Logs. These are separate telemetry sources; collecting one does not enable all others.
3. Grant only the necessary approved Azure and Kubernetes read permissions. Azure resource Reader alone does not guarantee Kubernetes API access. Avoid cluster-admin.
4. Query node/pod events and correlate node-pool operations, scheduler constraints, IP exhaustion, registry access, resource pressure, and dependency issues. Use the KubePodInventory sample only if that table is collected.
5. Recommend the owning team's runbook. Scaling, pod restarts, drains, manifest edits, and node replacement are changes, not read-only diagnostics.

**Exercise / pass:** create an intentionally unschedulable pod in an isolated test namespace, without breaking shared nodes. The agent identifies the scheduling evidence and the workload/platform owner; the authorized manifest correction restores the test.

**Measure:** time to classify cluster versus workload fault; repeated pages; time to supported mitigation. **Benefit:** less escalation ping-pong and more consistent AKS operations.

**Basis:** [AKS landing-zone accelerator](https://github.com/Azure/AKS-Landing-Zone-Accelerator); [AKS baseline](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks/baseline-aks).

## UC09 - AKS upgrade readiness and regression

**Owner:** AKS service owner; application owners approve disruption and compatibility. **Signal:** upgrade planning window, unsupported-version risk, failed node-pool operation, or post-upgrade SLO degradation.

**Set up:**
1. Capture supported/target versions, node images, maintenance windows, surge/quota/IP headroom, API deprecations, admission policies, storage dependencies, disruption budgets, and workload replica readiness.
2. Feed the relevant read-only inventory, runbooks, change plan, and preflight results to the agent. A checklist is not an automated compatibility guarantee.
3. Ask for blockers, unknowns, owner, and a go/no-go recommendation. Confirm a staging/canary cluster or pool strategy consistent with the chosen AKS design.
4. Execute the approved upgrade through existing tooling. Do not promise an in-place Kubernetes version downgrade: recovery may require an alternate cluster or redeployment and tested data recovery.
5. Correlate post-change metrics/events and validate the original user flows during the agreed observation window.

**Exercise / pass:** detect a deliberately blocked test disruption budget or insufficient preflight capacity before upgrade. Run only an approved sandbox upgrade; prove health or execute the tested recovery plan.

**Measure:** preflight defect detection; upgrade success rate; disruption duration; supported-version compliance. **Benefit:** predictable lifecycle governance without agent-driven disruptive maintenance.

**Basis:** [AKS landing-zone accelerator](https://github.com/Azure/AKS-Landing-Zone-Accelerator); [WAF safe deployments](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/safe-deployments).

## UC10 - Backup and restore assurance

**Owner:** platform continuity/backup owner; workload/data owner approves restore and validates data. **Signal:** failed/missing backup job, protected-item gap, or scheduled recovery exercise.

**Set up:**
1. Identify which platform components actually require backup and which are rebuilt from IaC. Register the approved RTO, RPO, data owner, region, retention, restore target, and recovery dependencies.
2. Configure the relevant backup service's supported monitoring and alerts. Capture job IDs, last successful recovery points, immutability/access controls where applicable, and dependency failures.
3. Ask SRE Agent to explain gaps and failed jobs using service evidence. "Last job succeeded" does not prove restore usability or RTO/RPO compliance.
4. Plan an isolated restore/rebuild, capacity and network access checks, verification steps, and cleanup. Never overwrite production or trigger regional failover automatically.
5. Conduct the authorized exercise and attach measured recovery time/data-loss evidence, not a compliance assertion.

**Exercise / pass:** restore an approved non-sensitive sandbox artifact/service into an isolated target, validate integrity and a user flow, and compare measured results to the approved targets.

**Measure:** restore-test pass rate; measured RTO/RPO; age of last verified recovery; failed-job time-to-owner. **Benefit:** CCoE can distinguish backup posture from demonstrated recoverability.

**Basis:** [WAF Reliability](https://learn.microsoft.com/en-us/azure/well-architected/reliability/); [Azure Backup documentation](https://learn.microsoft.com/en-us/azure/backup/).

## UC11 - Platform cost and telemetry anomaly

**Owner:** platform FinOps owner, with observability and service owners. **Signal:** budget/cost anomaly, ingestion spike, excessive agent activity, or unexpected scale.

**Set up:**
1. Agree allocation tags, platform service boundaries, daily cost/usage views, retention settings, expected traffic, and an approved cost envelope. Cost data can arrive later than operational metrics.
2. Supply a sanitized Cost Management export or approved read-only query output, the workspace Usage query, resource changes, and SRE Agent usage/billing information. Cost integration is a custom pattern unless a supported connector is verified.
3. Ask for a ranked breakdown and likely drivers with explicit uncertainty. Workspace Usage estimates ingestion contribution, not final charges or all monitoring costs.
4. Recommend optimizations with reliability/security tradeoffs: log filtering only where approved, retention review, noisy alert reduction, bounded investigation windows, capacity rightsizing, or removal of redundant pilot agents.
5. Service owners approve any change, measure savings against a comparable period, and ensure observability and recovery do not degrade. Budgets notify; they do not inherently cap spend or stop agents.

**Exercise / pass:** replay a sanitized historic ingestion/agent-usage spike. Identify the source and a reversible intervention without deleting resources or suppressing mandatory evidence.

**Measure:** EUR per investigated incident; GB per platform service; false-positive investigation rate; realized savings; telemetry-gap count. **Benefit:** keep the operations assistant from becoming an unmanaged cost center.

**Basis:** [WAF Cost Optimization](https://learn.microsoft.com/en-us/azure/well-architected/cost-optimization/); [SRE Agent pricing](https://azure.microsoft.com/en-us/pricing/details/sre-agent/).

## UC12 - Incident-to-WAF improvement loop

**Owner:** platform service owner accountable; CCoE curates reusable standards; responders validate findings. **Signal:** incident closure or monthly platform review.

**Set up:**
1. Define the incident record: affected service/user flow, detection, impact, UTC timeline, evidence, uncertainty, human decisions, mitigation, recovery verification, and follow-up owners.
2. Ask the agent to draft a blameless summary using the approved incident context. Responders must confirm the root cause; the agent's narrative is not a forensic finding.
3. Map each improvement to a specific ALZ design area and relevant WAF pillar. Use the assessment table in `README.md`; this is evidence preparation, not an official WAF score or certification.
4. Human-review a runbook/IaC/monitoring improvement request with owner, priority, due date, acceptance test, and release gate. Publish only approved, sanitized content.
5. Track recurrence, action closure, and whether the proposed preventive control actually detects/prevents the failure in a sandbox exercise.

**Exercise / pass:** compare an agent-generated summary with a known incident. Require source-backed observations, explicit unknowns, correct owners, and no invented root cause. Verify one approved improvement against a repeat test.

**Measure:** actionable follow-up closure; repeat-incident rate; responder editing time; unsupported-claim rate. **Benefit:** CCoE turns incident evidence into reusable standards; teams reduce repetitive documentation without outsourcing accountability.

**Basis:** [WAF framework](https://learn.microsoft.com/en-us/azure/well-architected/); [WAF observability](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/observability).

**Next:** for proactive, pillar-specific checks rather than incident-driven ones, see [waf-pillar-use-cases.md](waf-pillar-use-cases.md) (W1 Reliability to W5 Performance Efficiency).
