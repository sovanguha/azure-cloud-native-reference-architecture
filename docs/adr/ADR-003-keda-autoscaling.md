# ADR-003: Use KEDA for Event-Driven Autoscaling on Queue Depth

**Date:** 2024-10-01  
**Status:** ✅ Accepted  
**Deciders:** Sovan Guha (Solution Architect), Platform Engineering Lead  
**Context:** Autoscaling strategy for Service Bus worker pools on AKS

---

## Context & Problem

Worker pods processing Azure Service Bus messages need autoscaling. Kubernetes' built-in Horizontal Pod Autoscaler (HPA) scales on CPU and memory. For queue processors, **CPU is the wrong signal** — a worker with an empty queue has 0% CPU but still needs 0 pods. A worker with a full queue may not be CPU-bound but needs 20 pods.

We needed autoscaling based on **Service Bus queue depth** (number of messages awaiting processing).

---

## Decision Drivers

- Scale-out must trigger when queue depth exceeds a threshold, not when CPU spikes
- Scale-to-zero during off-peak hours to minimise cost
- Each worker pool must scale independently (payment, inventory, notification, bridge)
- Scale-out must be fast: pods available within 60 seconds of queue depth rising
- Target SLA: messages processed within 30 seconds of delivery under normal load

---

## Options Considered

### Option A: Kubernetes HPA (CPU/Memory)

**Pros:**
- Built into Kubernetes — no additional components
- Well understood by operations teams

**Cons:**
- ❌ **Wrong signal for queue processors** — CPU lags significantly behind queue depth
- ❌ Cannot scale to zero (HPA minimum is 1 replica)
- ❌ Queue depth spikes cause message backlog before CPU eventually rises and triggers scale-out
- ❌ In testing: 10,000 message queue spike → HPA triggered after 4 minutes. KEDA triggered in 28 seconds.

---

### Option B: KEDA (Kubernetes Event-Driven Autoscaler) ✅ CHOSEN

KEDA extends Kubernetes HPA with external metric sources. The `azure-servicebus` scaler reads queue/topic subscription message count directly from Service Bus.

**Configuration:**
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: payment-worker-scaledobject
spec:
  scaleTargetRef:
    name: payment-worker
  minReplicaCount: 0        # Scale to zero when queue empty
  maxReplicaCount: 20       # Cap for downstream protection
  cooldownPeriod: 300       # 5 min before scale-in (avoid thrashing)
  triggers:
    - type: azure-servicebus
      metadata:
        topicName: orders
        subscriptionName: payment-subscription
        namespace: orders-servicebus-ns
        messageCount: "50"   # Target: 1 pod per 50 messages
      authenticationRef:
        name: keda-servicebus-auth
```

**Pros:**
- ✅ Scales on the **right signal** — queue depth, not CPU
- ✅ Scale-to-zero supported natively — pods drop to 0 when queue is empty
- ✅ Independent `ScaledObject` per worker pool — payment scales independently from inventory
- ✅ `messageCount` threshold tunable per worker type (payment: 50, notification: 200)
- ✅ GA in AKS — Microsoft managed add-on available: `az aks enable-addons --addons keda`
- ✅ Workload Identity integration — KEDA authenticates to Service Bus via Managed Identity (no secrets)

**Cons:**
- ❌ Additional component in the cluster (though managed via AKS add-on reduces this concern)
- ❌ Cold start delay when scaling from zero — addressed by `minReplicaCount: 1` during business hours via scheduled scaling

---

### Option C: Azure Functions with Service Bus Trigger

**Pros:**
- Managed autoscaling built-in
- Scale-to-zero native

**Cons:**
- ❌ Execution time limit (10 min default, 60 min max on Premium plan)
- ❌ Payment processing workflows may exceed limits under high load
- ❌ Less control over concurrency and resource limits
- ❌ Consistent cost model harder to predict — consumption plan pricing unpredictable at scale

*Azure Functions remains a good option for simple, short-lived message handlers. Not suitable for complex, long-running payment workflows.*

---

## Decision

**Use KEDA with the `azure-servicebus` scaler for all Service Bus worker pools on AKS.**

KEDA is the architecturally correct solution because it aligns the scaling signal with the actual workload driver. This was validated in load testing: KEDA triggered scale-out in 28 seconds vs 4+ minutes for CPU-based HPA.

---

## Implementation Notes

**Managed Identity Authentication (no secrets):**
```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-servicebus-auth
spec:
  podIdentity:
    provider: azure-workload
```

**Scaling Parameters by Worker Type:**

| Worker | minReplicas | maxReplicas | messageCount threshold | cooldownPeriod |
|---|---|---|---|---|
| Payment Worker | 0 (2 during hours) | 20 | 50 | 300s |
| Inventory Worker | 0 (2 during hours) | 30 | 100 | 180s |
| Notification Worker | 0 | 50 | 200 | 120s |
| Bridge Worker | 0 (1 during hours) | 10 | 25 | 300s |

**Scheduled Scaling for Cold Start:**
Use a KEDA `CronJob` or AKS node pool schedule to set `minReplicaCount: 2` during business hours (06:00–22:00 IST), reverting to 0 overnight.

---

## Consequences

**Positive:**
- Scale-to-zero overnight: estimated **35% reduction in worker compute cost**
- Scale-out in <30 seconds — messages processed within SLA under peak load
- Payment workers scale to 20 independently from inventory workers scaling to 30
- Zero credentials for KEDA → Service Bus connection (Managed Identity)

**Negative:**
- Cold start from zero: first message after quiet period may take 45–60 seconds to process
- Mitigation: scheduled minimum replicas during business hours

---

## References
- [KEDA Azure Service Bus Scaler](https://keda.sh/docs/scalers/azure-service-bus/)
- [AKS KEDA Add-on](https://learn.microsoft.com/en-us/azure/aks/keda-about)
- [KEDA Workload Identity](https://keda.sh/docs/authentication-providers/azure-workload-identity/)
