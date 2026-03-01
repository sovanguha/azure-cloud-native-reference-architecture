# ADR-002: AKS for Worker Pools, App Service for Public APIs

**Date:** 2024-09-20  
**Status:** ✅ Accepted  
**Deciders:** Sovan Guha (Solution Architect), Platform Lead, FinOps Lead  
**Context:** Hosting strategy for Order API (public-facing) and Service Bus worker pools (background processing)

---

## Context & Problem

We needed to decide compute hosting for two distinct workload types:

1. **Public API tier** — HTTP request/response, needs TLS termination, custom domains, WAF integration
2. **Worker pools** — background message processors, need event-driven autoscaling based on queue depth (not HTTP traffic)

The instinct was to host everything on AKS for consistency. This ADR evaluates whether that uniformity is worth the operational cost.

---

## Decision Drivers

- Worker pools must scale to zero during off-peak hours (cost driver)
- Workers must scale out based on **Service Bus queue depth**, not CPU/memory
- Public APIs need WAF, SSL, custom domain management
- Operations team is not yet Kubernetes-native — we need manageable complexity
- Target: deploy new worker type in under 1 sprint with minimal platform work

---

## Options Considered

### Option A: Everything on AKS

One platform for all workloads.

**Pros:**
- Consistent deployment model, single platform to operate
- Full control over networking, resource limits, pod scheduling
- Kubernetes-native KEDA available for queue-depth scaling

**Cons:**
- AKS cluster is always-on cost (~£200–400/month for a baseline cluster) even if workers are idle
- Operations overhead: certificate management, ingress controller (nginx/AGIC), node pool management
- Ingress + AGIC configuration needed for public API — adds complexity
- Team learning curve for teams not yet Kubernetes-native

---

### Option B: App Service for APIs, AKS for Workers ✅ CHOSEN

Split hosting by workload type.

**App Service** for public-facing HTTP APIs:
- ✅ Built-in TLS, custom domain, deployment slots (blue-green)
- ✅ Autoscales on HTTP RPS/CPU — the right signal for HTTP workloads
- ✅ Azure Application Gateway + WAF integrates natively
- ✅ Built-in managed certificates — zero certificate rotation toil
- ✅ Simpler operational model for HTTP APIs

**AKS** for Service Bus worker pools:
- ✅ KEDA scales workers on queue depth (not CPU) — exactly right for queue processors
- ✅ Scale to zero when queue is empty — major cost saving for off-peak hours
- ✅ Independent scaling per worker type (payment ≠ inventory ≠ notification)
- ✅ Kubernetes resource limits prevent noisy-neighbour problems between worker types

**Cons:**
- ❌ Two platforms to manage — increases operational surface area
- ❌ Networking must be designed carefully (App Service VNet Integration → AKS subnet → Service Bus private endpoint)

---

### Option C: Azure Container Apps

Fully managed containers with KEDA built-in.

**Pros:**
- KEDA built-in, scale-to-zero native
- Less operational overhead than AKS
- Works for both HTTP and queue-based workloads

**Cons:**
- Less control over networking than AKS (important for financial services compliance)
- Not yet mature for complex enterprise requirements at time of decision (Sept 2024)
- Limited support for Windows containers (some legacy workers)

*Container Apps is a strong candidate for future re-evaluation when team familiarity increases.*

---

## Decision

**App Service for public HTTP APIs. AKS with KEDA for Service Bus worker pools.**

The key insight is that **the right autoscaling signal differs by workload type**. HTTP APIs should scale on request rate. Queue workers should scale on queue depth. Forcing both onto the same platform means compromising on one of them.

---

## Consequences

**Positive:**
- Workers scale to zero overnight → estimated 35–40% reduction in compute cost vs always-on
- App Service handles TLS/WAF with no operational overhead
- KEDA queue-depth scaling is precise — workers appear within 30 seconds of queue depth rising

**Negative:**
- Two deployment pipelines (one for App Service, one for AKS helm charts)
- VNet integration requires careful subnet planning — documented in [04-security-zero-trust.md](../architecture/04-security-zero-trust.md)

**Review trigger:** Re-evaluate Azure Container Apps in Q1 2026 when platform matures further.

---

## References
- [Azure App Service Documentation](https://learn.microsoft.com/en-us/azure/app-service/)
- [KEDA on AKS](https://learn.microsoft.com/en-us/azure/aks/keda-about)
- [Azure Container Apps KEDA](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
