# Azure Foundational Platform Research — SRE Agent Starter Kit

**Scope:** CAF Azure Landing Zones (ALZ), subscription vending (official automation), Microsoft AI Landing Zone accelerator, AKS baseline / AKS Landing Zone Accelerator. EU Public Cloud generic reference, IT-only, Bicep + Azure Verified Modules (AVM) preference, **no deployment performed**.
**Researched:** 2026-10-20, via Microsoft Learn (live fetch) and official Microsoft/Azure GitHub repositories (live fetch, not cached knowledge).
**Out of scope (researched elsewhere):** Azure SRE Agent product features. This document makes **no claim** of native SRE Agent connectors to any accelerator, and **no claim** that any accelerator automatically enforces policy or performs subscription vending without the platform team's pipeline/approval step. Where a pattern is not stated verbatim in a primary source, it is explicitly labeled **"Proposed integration pattern"**.

---

## 1. CAF Azure Landing Zone design areas (primary foundation)

Source: *Azure landing zone design areas and conceptual architecture*, Microsoft Learn — `https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas` (fetched 2026-10-20).

An Azure landing zone follows **8 design areas**, labeled A–I in the CAF reference diagram:

| # | Design area | Objective (verbatim from source) |
|---|---|---|
| A | Azure billing and Microsoft Entra tenant | "Proper tenant creation, enrollment, and billing setup are important early steps." |
| B | Identity and access management | "Identity and access management is a primary security boundary in the public cloud. It's the foundation for any secure and fully compliant architecture." |
| C | Resource organization | "As cloud adoption scales, considerations for subscription design and management group hierarchy have an impact on governance, operations management, and adoption patterns." |
| E | Network topology and connectivity | "Networking and connectivity decisions are an equally important foundational aspect of any cloud architecture." |
| F | Security | "Implement controls and processes to protect your cloud environments." |
| D/G/H | Management | "For stable, ongoing operations in the cloud, a management baseline is required to provide visibility, operations compliance, and protect and recover capabilities." |
| C/D | Governance | "Automate auditing and enforcement of governance policies." |
| I | Platform automation and DevOps | "Align the best tools and templates to deploy your landing zones and supporting resources." |

(Note: the CAF page itself groups "Management" across legend letters D, G, H and "Governance" across C, D — this is the official grouping, not a transcription error.)

Source confirms an Azure landing zone has exactly **two components**: *Platform landing zone* (centralized governance/shared resources, one per Entra tenant) and *Workload landing zones* (per-workload environments operating inside platform guardrails) — `https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/` (fetched 2026-10-20).

### Ownership model (platform vs. workload) — explicit from CAF

- **Platform team owns**: management group hierarchy, centralized/shared resources (connectivity, identity, security monitoring, management), and the **workload-landing-zone distribution mechanism** (i.e., subscription vending).
- **Workload team owns**: all resources inside their workload landing zone subscription(s) across dev/test/prod, within inherited policy guardrails.
- Source: *What is an Azure landing zone?* — platform landing zone / workload landing zone subsections, same URL as above.

---

## 2. Subscription vending — official automation modules

### 2.1 Process (CAF guidance)

Source: *Subscription vending* (design area) — `https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/subscription-vending`, and *Subscription vending implementation guidance* (Azure Architecture Center) — `https://learn.microsoft.com/azure/architecture/landing-zones/subscription-vending` (both fetched 2026-10-20).

Three-party flow: **CCoE** (business rules/approval) → **workload team** (request) → **platform team** (create/configure via IaC) → **workload team** (budget update, deploy, operate).

Recommended automation architecture (explicit in source, Gitflow-based):
1. Data collection tool (ITSM ticket or Power Apps/low-code portal) gathers requirements: budget, owner, networking needs, criticality/confidentiality, environment count.
2. Approval triggers the **request pipeline**: creates a subscription parameter file (JSON/YAML/TFVARS), opens a **pull request** in source control.
3. A **linting/validation stage runs on the PR** (schema + IP-range availability check); **optional manual review gate** for human sign-off before merge.
4. Merge to `main` triggers the **deployment pipeline**, which runs the IaC module (Bicep/Terraform) to create and configure the subscription.
5. Deployment pipeline tasks (explicit table in source): Identity (Entra resources, workload identities) → Governance (management group placement, RBAC, Azure Policy assignment, Defender for Cloud enrollment) → Networking (VNet + peering to hub) → Budgets → Reporting (IPAM commit, notify requester).
6. Post-deployment: workload team updates budget and deploys; platform retains governance control (can move subscription between management groups later).

**Important caveat from source:** creating an Azure subscription programmatically requires a commercial agreement (EA/MCA/MPA role); without it, subscription creation is a manual step, but all *configuration* can still be automated.

### 2.2 Verified official automation modules (fetched directly)

- **Bicep AVM pattern module — `avm/ptn/lz/sub-vending`**, repo `Azure/bicep-registry-modules`, path `avm/ptn/lz/sub-vending/README.md` (fetched; SHA `38814d0d...`). Reference: `br/public:avm/ptn/lz/sub-vending:<version>`. Wiki: `https://github.com/Azure/bicep-lz-vending/wiki`.
  - Shorthand link (CAF-published): `https://aka.ms/lz-vending/bicep`.
- **Terraform AVM pattern module — `avm-ptn-alz-sub-vending`**, published at `https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest` (CAF-cited). Shorthand link: `https://aka.ms/lz-vending/tf`.
- Both modules are explicitly described in CAF as the way to "adopt a subscription vending model regardless of your commercial agreement," orchestrated via GitHub Actions or Azure DevOps Pipelines.

### 2.3 Subscription vending "product lines" (ownership-relevant)

Source: *Establish common subscription vending product lines* — `https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/subscription-vending-product-lines` (fetched 2026-10-20). Defines 5 common product lines platform teams should offer: **Corp connected**, **Online**, **Tech platform** (explicitly includes the AKS-as-a-platform pattern: "an AKS platform team manages a fleet of clusters … workload team only maintains their application"), **Shared application portfolio**, **Sandbox**. Relevant for the starter kit because an "AKS tech platform" subscription is a named, CAF-sanctioned pattern distinct from a one-off workload subscription — it changes who owns cluster-level telemetry/ops vs. namespace-level workload ops.

---

## 3. Platform landing zone implementation options (IaC accelerator)

Source: *Platform landing zone implementation options* — `https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/implementation-options` (fetched 2026-10-20).

- **Recommended path:** *Azure Landing Zones IaC Accelerator* (`https://aka.ms/alz/accelerator`), using **AVM** for Bicep (`https://aka.ms/alz/acc/bicep`) or Terraform (`https://aka.ms/alz/acc/tf`). Four-phase setup: **Phase 0 Planning** (choose IaC language + VCS) → **Phase 1 Prerequisites** (credentials/subscriptions) → **Phase 2 Bootstrap** (PowerShell module bootstraps Azure + VCS CI/CD assets) → **Phase 3 Run** (customize IaC, trigger pipelines).
- **Alternative:** *Azure platform landing zone portal accelerator* (`https://aka.ms/alz/portal`) — GUI-based ARM/Bicep deploy-to-Azure button; explicitly called out as **lower flexibility, harder to version-control**, recommended only for orgs without IaC capability.
- Verified repo: `Azure/alz-terraform-accelerator` — "starter modules for the Azure Landing Zones IaC Terraform Accelerator" (README fetched).
- Verified repo (classic/legacy): `Azure/ALZ-Bicep` — README explicitly states: *"With Bicep AVM now generally available and set as the default in the ALZ Accelerator for Bicep, we're beginning the deprecation process for classic ALZ-Bicep."* → **current guidance is to use the AVM-based Bicep accelerator (`aka.ms/alz/acc/bicep`), not the legacy `ALZ-Bicep` repo.** This is a material, dated finding for any starter kit referencing ALZ-Bicep.
- Baseline policy set referenced for extension: `https://aka.ms/alz/policies`.

---

## 4. Microsoft AI Landing Zone accelerator

Repo verified: **`Azure/AI-Landing-Zones`** (GitHub, README fetched directly, SHA `44a3fc7a...`). Docs site: `https://azure.github.io/AI-Landing-Zones/`.

### 4.1 What it is (verbatim facts from README)
- It is an **application (workload) landing zone**, not a platform landing zone — "meant to act as a foundation for various use cases... which can be deployed with or without platform landing zone."
- Two composable reference architectures: **Agent Landing Zone** (Foundry-hosted orchestrator agent + chat UI, optional Container Apps hosting, optional ingestion Container App) and **AI Gateway Landing Zone** (APIM as AI Gateway in front of Foundry models).
- **IaC = Bicep and Terraform, both built on Azure Verified Modules (AVM).** Confirms Bicep-AVM alignment for this starter kit.
- Explicitly "designed and tested for Azure Public Cloud but can be leveraged in Azure Government and Sovereign Cloud" — supports an EU-generic reference use.
- **Status: in preview** (explicit "Roadmap" section, "currently in preview").
- Region constraint: full ALZ-pattern deployment is currently supported only in a specific region list (includes `germanywestcentral`, `swedencentral`, `francecentral`, `norwayeast`, `polandcentral`, `switzerlandnorth`, `uksouth` as EU-relevant options) — gated on co-availability of AI Services, AI Search, Container Apps, Cosmos DB, ACR, App Configuration, Key Vault, and zonal compute in each region.
- Does **not** itself deploy the sample agent application when using the plain infra Bicep/Terraform path — only the azd+Bicep guided flow deploys the full app; **Terraform app-layer integration is explicitly "not yet validated."**

### 4.2 Verified module/repo references (from README table)
| Component | Type | Verified link |
|---|---|---|
| Foundry infrastructure | Terraform | `https://registry.terraform.io/modules/Azure/avm-ptn-aiml-ai-foundry/azurerm/latest` |
| Foundry infrastructure | Bicep (AVM pattern) | `Azure/bicep-registry-modules` → `avm/ptn/ai-ml/ai-foundry` (directory exists, confirmed via repo listing) |
| Agent Landing Zone infra | Terraform | `https://aka.ms/ailz/terraform` |
| Agent Landing Zone infra | Bicep | `https://aka.ms/ailz/bicep` |
| Agent LZ infra + app (azd) | Guide | `https://azure.github.io/AI-Landing-Zones/agent-landing-zone/` |
| AI Gateway LZ | Terraform | `https://aka.ms/ailz/aigateway/terraform` |
| AI Gateway LZ | Bicep | `https://aka.ms/ailz/apim` |

**Gap found:** `Azure/bicep-registry-modules` also reserves `avm/ptn/ai-ml/landing-zone` (a combined AI-ML landing-zone pattern module), but direct inspection shows it currently contains **only `metadata.json`** (module display name + telemetry prefix registered, owners listed) — **no implementation yet**. Do not reference this as a usable module; it is a placeholder/reserved AVM module ID as of this research date.

### 4.3 Design governance
- CAF explicit stance: **"AI workloads don't require a different Azure landing zone architecture or governance model."** Platform teams extend the existing baseline (Azure Policy, networking) rather than building AI-specific management groups. Source: *Architecture and governance for AI* — `https://learn.microsoft.com/azure/cloud-adoption-framework/ai/ready` (fetched 2026-10-20).
- Internet-facing AI workloads → Online management group; internal → Corp ("Internal") management group — same existing ALZ hierarchy, no new groups.
- AI Landing Zone repo ships its own extended **design checklist** aligned to CAF + Well-Architected AI workload guidance (`https://azure.github.io/AI-Landing-Zones/architecture/design-checklist/`).

---

## 5. AKS baseline and AKS Landing Zone Accelerator

### 5.1 AKS baseline reference architecture
Source: *Baseline architecture for an Azure Kubernetes Service (AKS) cluster* — `https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks` (fetched 2026-10-20, full page). Reference implementation repo verified: **`mspnp/aks-baseline`**.

Key architectural facts:
- Hub-and-spoke network topology; hub holds Azure Firewall, Bastion, gateway subnet; spoke holds App Gateway (WAF v2), internal LB subnet, node pools, Private Link subnet (ACR + Key Vault), optional private API server subnet.
- **GitOps is the recommended cluster/workload operations model**, using **Flux** via the **"GitOps with Flux v2" AKS cluster extension** (AKS-managed extension, confirmed in `mspnp/aks-baseline` README as an "in-cluster OSS component… [AKS-managed extension]").
- Explicit GitOps control model (from Learn page, "Cluster and workload operations" section): *"Flux has read-only access to the Git repository... Developers don't have direct access to the Kubernetes API through kubectl... You can have branch policies on your Git server so that multiple developers can then approve changes through a pull request before the change is applied to production."* → **this is the primary-source basis for an approval-gated GitOps pattern** (branch protection + PR review = the gate; Flux only ever pulls, never receives pushed `kubectl` commands).
- `mspnp/aks-baseline` repo structure (verified via `.github/copilot-instructions.md`): `network-team/` (Bicep: hub/firewall/peering), `workload-team/` (Bicep: AKS/ACR/KeyVault/AppGW/monitoring, `cluster-stamp.bicep` takes a `gitOpsBootstrappingRepoBranch` parameter and provisions a Flux `GitRepository` source scoped to namespace `flux-system`), `cluster-manifests/` (the actual GitOps-managed baseline K8s config, pulled automatically post-bootstrap), `workload/` (sample Kustomize app manifests).
- Bootstrapping note (explicit from `docs/deploy/05-bootstrap-prep.md`): *"If you are running a fleet of clusters, a GitOps approach is highly recommended for uniformity and easier governance. When running only a few clusters, GitOps might be seen as 'too much'..."* — a real trade-off callout, not a blanket mandate.

### 5.2 Telemetry / monitoring (primary source — AKS baseline "Monitor and collect logs and metrics")
Explicit recommendations from the Learn page:
- **Logs**: `ContainerLogV2` schema into a Log Analytics workspace, configured via **Data Collection Rules (DCRs)** as Azure resources (preferred over ConfigMap for reusable, Bicep-managed config; the two methods must not be mixed — ConfigMap wins if both are enabled, causing hard-to-debug drift).
- **Metrics**: **Azure Monitor managed Prometheus** workspace; recommended **Prometheus alert rules for Kubernetes** (`https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-metric-alerts`) as the **default production alerting path**; an Azure Monitor **health model (preview)** is called out as optional, not required for every baseline deployment.
- **Control-plane/resource logs to enable on most clusters**: `cluster-autoscaler`, `kube-controller-manager`, `kube-audit-admin` (not `kube-audit`, which is a redundant superset), `guard` (Entra ID + Azure RBAC audit).
- **Network metrics**: platform + Prometheus node network metrics by default; "Advanced Container Networking Services" only for workloads sensitive to packet-level TCP/UDP/DNS behavior.
- **Cost control**: `ContainerLogV2` table defaults to **Basic plan** (cheaper ingestion, since Defender for Containers/baseline alerts don't query it); switch to Analytics plan only if query volume grows.
- **Self-healing**: liveness/readiness probes trigger pod restarts; this is cluster-native, not a separate telemetry pipeline.

### 5.3 AKS Landing Zone Accelerator (distinct repo, explicitly scoped narrower than ALZ)
Repo verified: **`Azure/AKS-Landing-Zone-Accelerator`** (README fetched). Key facts:
- Explicitly builds on **both** the AKS baseline reference architecture **and** Azure Landing Zones — but is scoped **only to the landing-zone subscription itself**: *"assumed that an appropriate platform foundation is already setup... policies and governance should already be in place... this is not mandatory, it just enhances it."*
- Offers Bicep/Terraform/ARM "Scenarios," notably `AKS-Secure-Baseline-PrivateCluster` and `AzureML-on-Private-AKS`.
- Points to a sibling tool, **`Azure/Aks-Construction`** ("AKS Construction Helper"), a web-based Bicep templating tool for quick CLI/CI deployment — useful as a faster-start alternative, not the canonical production path.
- Cross-link confirms `Azure/AKS-Construction`'s own docs ("referencearchs.md") describe itself as feeding into the parent `AKS-Landing-Zone-Accelerator` project.

### 5.4 Verified AVM module for AKS compute
`Azure/bicep-registry-modules` → `avm/res/container-service/managed-cluster` exists (directory confirmed) — the AVM resource module for `Microsoft.ContainerService/managedClusters`, usable as the Bicep building block inside either `mspnp/aks-baseline`-style or AKS-LZ-Accelerator-style deployments (not itself a full landing zone).

### 5.5 Azure Monitor Baseline Alerts (AMBA) — supporting telemetry catalogue
Repo verified: **`Azure/azure-monitor-baseline-alerts`** (README fetched). Purpose: "best practice guidance around key alerts, metrics, and their thresholds" per-service, plus "Patterns/Scenarios" guidance **including Azure Landing Zones**, with ready-to-deploy Azure Policy definitions/initiatives for alert deployment. Relevant as the canonical source of *which metrics/thresholds* to wire into a starter kit's telemetry baseline (platform-owned, policy-deployed alerting), separate from the AKS-specific Prometheus rules above.

---

## 6. 8–12 platform operational use cases (telemetry + ownership)

These are derived directly from the primary sources above. Each use case states **what telemetry a starter kit would need**, and **who owns it under CAF's platform-vs-workload model** (facts); integration into an "SRE Agent" workflow is marked as a **proposed pattern**, since SRE Agent connectors are out of scope here.

| # | Use case | Telemetry required | Ownership (CAF-sourced) | Source |
|---|---|---|---|---|
| 1 | Subscription vending pipeline health (PR→deploy success/failure, drift between requested vs. deployed parameters) | Pipeline run status (GitHub Actions/Azure DevOps run logs), IaC plan/apply diff output, PR merge/approval audit trail | **Platform** owns pipeline; **CCoE** owns approval policy | §2.1, Architecture Center subscription-vending guidance |
| 2 | Management-group/policy drift detection for vended subscriptions | Azure Policy compliance state, management-group assignment change events | **Platform** | §1 (Governance design area), §2.1 |
| 3 | Subscription budget threshold breach | Cost Management budget alert, tag-based cost allocation reports | **Shared**: platform creates preliminary budget; **workload** updates/owns ongoing budget | §2.1 ("Update subscription budget") |
| 4 | IPAM/network allocation conflicts during vending | IPAM reservation status, VNet peering state, address-space overlap checks | **Platform** (hub/peering), workload owns subnets within corp-connected product line | §2.1, §2.3 |
| 5 | AI Landing Zone region/service co-availability gating | Regional service-availability checks (AI Services, AI Search, Container Apps, Cosmos DB, ACR, App Config, Key Vault, zonal compute) before deploy | **Platform** (regional footprint decision), **workload** (deploy-time validation) | §4.1 |
| 6 | AI Landing Zone Foundry model/agent deployment compliance | Azure Policy evaluation for approved Foundry models/Foundry Tools/AI Search | **Platform** (policy baseline extension), **workload** (model selection within policy) | §4.3, CAF AI "ready" article |
| 7 | AKS cluster GitOps reconciliation health (Flux) | Flux `GitRepository`/`Kustomization` reconciliation status, sync drift, last-applied commit SHA | **Platform** (cluster-wide `cluster-manifests` baseline config) vs **workload** (app-level Kustomize manifests) — split ownership by directory, confirmed in `mspnp/aks-baseline` repo structure | §5.1 |
| 8 | AKS control-plane/API audit trail | `kube-audit-admin`, `guard` (Entra/RBAC audit) resource logs | **Platform** | §5.2 |
| 9 | AKS cluster autoscaler and capacity health | `cluster-autoscaler` logs, Prometheus node/pod metrics, recommended Prometheus alert rules | **Platform** (cluster-level), **workload** (pod-level resource requests/HPA) | §5.2 |
| 10 | AKS network observability (node/packet level) | Managed Prometheus network metrics; Advanced Container Networking Services for packet-level cases | **Platform** | §5.2 |
| 11 | Tech-platform (AKS-as-a-service) chargeback/ops boundary | Namespace-to-subscription mapping, per-tenant resource quota consumption | **Platform** owns cluster; **workload team** owns namespace/app — explicit CAF "tech platform product line" split | §2.3 |
| 12 | Baseline alert coverage completeness (any workload) | AMBA policy-initiative compliance (are baseline alerts for deployed resource types actually present?) | **Platform** (defines/deploys via Policy), **workload** (cannot opt out of inherited policy) | §5.5 |

---

## 7. Setup steps per accelerator (as documented; no deployment performed)

### 7.1 ALZ platform landing zone (IaC accelerator)
1. Phase 0 — choose IaC language (Bicep/Terraform) and VCS (GitHub/Azure DevOps).
2. Phase 1 — prepare credentials/subscriptions (identity, management, connectivity subscriptions as prerequisites).
3. Phase 2 — run the published PowerShell bootstrap module to scaffold the VCS repo, pipelines, and initial Azure resources.
4. Phase 3 — customize AVM-based IaC parameters, trigger CI/CD to deploy management groups, policy, hub networking.
(Source: §3; exact tool invocation/parameters not reproduced here — see `aka.ms/alz/accelerator` for current CLI/parameter reference, not fetched in full detail in this pass.)

### 7.2 Subscription vending integration
1. Stand up data-collection/ITSM intake capturing budget, owner, networking, classification.
2. Wire intake to a request pipeline that emits a JSON/YAML/TFVARS parameter file per subscription and opens a PR.
3. Add CI validation (schema lint + IP availability check) and a manual-approval gate before merge.
4. On merge, deployment pipeline runs `avm/ptn/lz/sub-vending` (Bicep) or `avm-ptn-alz-sub-vending` (Terraform) with one dedicated Terraform state file per subscription (explicit recommendation).
5. Pipeline performs identity/governance/networking/budget/reporting tasks per the table in §2.1.
(Source: §2.1–2.2.)

### 7.3 AI Landing Zone accelerator integration
1. Confirm target region is in the supported co-availability list (§4.1) for a full-pattern deployment; otherwise expect partial/unsupported deployment.
2. Choose Agent Landing Zone and/or AI Gateway Landing Zone (independently deployable).
3. For infra-only: consume the Bicep (`aka.ms/ailz/bicep`) or Terraform (`aka.ms/ailz/terraform`) module directly, both built on AVM `avm-ptn-aiml-ai-foundry` / `avm/ptn/ai-ml/ai-foundry`.
4. For infra+sample app: follow the azd+Bicep guided flow (Terraform app layer not yet validated per source).
5. Apply/extend the existing ALZ policy baseline (`aka.ms/alz/policies`) for approved AI services rather than creating new management groups (§4.3).
6. Review the AI Landing Zone design checklist (`azure.github.io/AI-Landing-Zones/architecture/design-checklist/`) against CAF/WAF AI design areas before go-live.

### 7.4 AKS baseline / AKS Landing Zone Accelerator integration
1. Decide placement: standalone `mspnp/aks-baseline`-style deployment vs. `Azure/AKS-Landing-Zone-Accelerator` "Scenario" (e.g., `AKS-Secure-Baseline-PrivateCluster`) layered under an existing platform landing zone subscription.
2. Deploy network team Bicep (hub: firewall, Bastion, gateway) then workload team Bicep (`cluster-stamp.bicep`: AKS, ACR, Key Vault, App Gateway, monitoring; parameterized with `gitOpsBootstrappingRepoBranch`).
3. Let the **GitOps-with-Flux-v2 AKS extension** bootstrap from `cluster-manifests/` automatically on cluster creation (no manual `kubectl` required for baseline config).
4. Configure Log Analytics + DCRs for `ContainerLogV2`, enable `cluster-autoscaler`/`kube-controller-manager`/`kube-audit-admin`/`guard` resource logs, enable managed-Prometheus workspace and recommended Prometheus alert rules (§5.2).
5. Optionally layer AMBA policy initiatives (`Azure/azure-monitor-baseline-alerts`) for platform-wide baseline alert coverage across resource types beyond AKS.
6. Reserve `kubectl` direct access for emergency break-fix only, per explicit source guidance.

---

## 8. Safe, approval-gated GitOps handling — pattern basis

Primary-source elements (facts):
- Flux has **read-only** Git access; it only reconciles, never receives pushed commands — eliminates a class of "who ran kubectl" incidents by design (§5.1).
- The gate is **Git branch protection + pull-request review**, not a Flux-native feature — "branch policies on your Git server so that multiple developers can then approve changes through a pull request before the change is applied to production" (§5.1).
- Subscription vending applies the identical pattern one layer up: PR-based parameter file + lint validation + **optional manual review gate** before the merge that triggers deployment (§2.1).

**Proposed integration pattern (not sourced from an SRE Agent doc — the agent itself is out of scope):** a starter kit can standardize on "two gated Git flows" — (a) subscription-vending parameter PRs gated by CCoE/platform approval, and (b) `cluster-manifests`/workload Kustomize PRs gated by platform/workload code owners — and treat both PR queues as a single "pending platform change" telemetry surface an agent could read (open PR count, age, approval state, last Flux/pipeline reconciliation result). This specific aggregation is **not** documented in any fetched primary source; it is an inference to validate separately against SRE Agent capabilities.

---

## 9. Failure drills and success metrics (as stated in primary sources; otherwise inferred)

**Explicitly stated in sources:**
- AKS baseline: recommends deploying *any* change (architecture, workload, cluster config) to **at least one pre-production cluster first**, running tests/validation at each stage before promoting to production — the closest thing to a documented "drill" process (§5.1/"Workload and cluster deployment strategies").
- AKS baseline: liveness/readiness probes as the automatic self-healing/failure-recovery mechanism at pod level (§5.2).
- Subscription vending: budgets are explicitly **not hard limits**, only alerting thresholds — a stated operational constraint relevant to any "cost failure drill" (§2.1).

**Not found as explicit, named "failure drill" or "success metric" catalogues** in the CAF/AKS-baseline/AI-Landing-Zone primary sources reviewed. A starter kit should therefore treat the following as **proposed, not sourced**, success-metric candidates derived from the telemetry already identified in §6: Flux reconciliation success rate, subscription-vending pipeline lead time (request→ready), AMBA alert-rule coverage percentage, pre-prod→prod promotion gate pass rate, kube-audit-admin anomaly count. These should be validated against actual customer requirements before being presented as "best practice," since Microsoft Learn does not currently publish them as such.

---

## 10. Verified AVM module candidates (summary table)

| Module | Repo / registry | Status |
|---|---|---|
| `avm/ptn/lz/sub-vending` (Bicep) | `Azure/bicep-registry-modules` | ✅ Implemented, documented (CAF-linked) |
| `avm-ptn-alz-sub-vending` (Terraform) | Terraform Registry, `Azure/avm-ptn-alz-sub-vending` | ✅ Implemented, documented (CAF-linked) |
| `avm/ptn/ai-ml/ai-foundry` (Bicep) | `Azure/bicep-registry-modules` | ✅ Directory confirmed; referenced by AI-Landing-Zones README |
| `avm-ptn-aiml-ai-foundry` (Terraform) | Terraform Registry | ✅ Referenced by AI-Landing-Zones README (not independently re-verified beyond the link) |
| `avm/ptn/ai-ml/landing-zone` (Bicep) | `Azure/bicep-registry-modules` | ⚠️ **Reserved only** — `metadata.json` exists, no implementation. Do not use/cite as functional. |
| `avm/res/container-service/managed-cluster` (Bicep) | `Azure/bicep-registry-modules` | ✅ Directory confirmed (AKS resource-level AVM module) |
| ALZ Bicep accelerator (current) | `aka.ms/alz/acc/bicep` | ✅ Current recommended path (AVM-based) |
| `Azure/ALZ-Bicep` (classic) | GitHub | ⚠️ **Being deprecated** per repo's own README — do not recommend for new builds |

---

## 11. Unresolved constraints / gaps for the starter kit author

1. **AI Landing Zone is explicitly "preview"** and Terraform app-layer deployment is explicitly "not yet validated" by Microsoft — any starter-kit guidance should flag this maturity level rather than present it as GA.
2. **`avm/ptn/ai-ml/landing-zone` AVM pattern module is a placeholder**, not usable; the actual AI Landing Zone IaC lives in the separate `Azure/AI-Landing-Zones` repo via `aka.ms/ailz/*` shortlinks, which is a naming trap worth calling out.
3. **No official Microsoft Learn source was found that directly combines "AKS Landing Zone Accelerator" ownership/telemetry guidance with "subscription vending" automation** — the connection in §2.3 (tech-platform product line ↔ AKS-as-a-service) is the closest documented bridge; a fuller joint pattern would need to be authored, not cited.
4. **No official "failure drill" or "success metric" framework** was located for ALZ, subscription vending, the AI Landing Zone, or the AKS baseline — §9's metrics are proposed, not sourced, and must be labeled as such downstream.
5. **Classic `Azure/ALZ-Bicep` deprecation timeline** was stated qualitatively ("beginning the deprecation process") without a firm end-of-support date in the fetched README; confirm current status before referencing in any customer-facing material.
6. Region support list for AI Landing Zone full-pattern deployment is **time-sensitive** (explicitly evolving — "given the pace of innovation") and should be re-verified at time of actual use rather than hardcoded from this report.
7. This research did not fetch the full AVM AKS `managed-cluster` module README (only confirmed directory existence) — parameter-level detail for that module was out of scope for this pass and would need a follow-up fetch if the starter kit needs exact AVM parameter names.
