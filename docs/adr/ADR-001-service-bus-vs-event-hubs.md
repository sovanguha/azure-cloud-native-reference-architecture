# ADR-001: Use Azure Service Bus for Workflow Messaging (not Event Hubs)

**Date:** 2024-09-15  
**Status:** ✅ Accepted  
**Deciders:** Sovan Guha (Solution Architect), Engineering Lead, Product Owner  
**Context:** Order processing async workflow — PlaceOrder → Payment → Inventory → Notification

---

## Context & Problem

We needed an async messaging backbone for the order processing workflow. Two Azure services were evaluated:
- **Azure Service Bus** — enterprise message broker with queues and topics
- **Azure Event Hubs** — high-throughput event streaming platform

Both could technically handle our message volumes (~500 orders/minute peak). The decision required analysing the fit against our specific workflow requirements.

---

## Decision Drivers

- Messages must be **processed exactly once** (payment captures, inventory reservations)
- Failed messages must be **held and retried** without data loss
- Different subscriber types need **independent processing** (payment ≠ inventory ≠ notification)
- Message order must be **preserved per order** (not globally)
- Operations team needs ability to **inspect and replay** failed messages
- Peak load: **500 messages/minute** with spikes to 2,000

---

## Options Considered

### Option A: Azure Service Bus Topics + Subscriptions ✅ CHOSEN

**How it works:** Publisher sends to a topic. Each subscriber (payment, inventory, notification) has an independent subscription with its own message lock, retry policy, and dead-letter queue.

**Pros:**
- ✅ Built-in dead-letter queue (DLQ) — failed messages preserved automatically
- ✅ Message lock prevents duplicate processing across competing consumers
- ✅ Per-subscription retry policies (exponential backoff, max delivery count)
- ✅ `partitionKey` property enables ordering per order ID
- ✅ Peek/complete/abandon/defer — full workflow control
- ✅ Sessions for ordered, stateful message processing
- ✅ KEDA scaler available (`azure-servicebus` trigger)
- ✅ 64KB–256KB message size — sufficient for our payloads

**Cons:**
- ❌ Not designed for high-volume streaming (Event Hubs handles millions/sec; we don't need this)
- ❌ Message retention limited to 14 days (not a constraint for our use case)
- ❌ Higher per-operation cost vs Event Hubs at extreme scale

---

### Option B: Azure Event Hubs

**How it works:** Events written to partitioned log. Consumers maintain their own offset, reading at their own pace. No concept of message lock or acknowledgement.

**Pros:**
- ✅ Extreme throughput (millions of events/second)
- ✅ Long retention — replay from any point in time
- ✅ Kafka-compatible API
- ✅ Lower cost per event at high volume

**Cons:**
- ❌ **No dead-letter queue** — you must build your own DLQ logic
- ❌ **No per-message retry** — you must implement retry outside Event Hubs
- ❌ **No competing consumer model** — all consumers in a group see all messages; partition count caps parallelism
- ❌ At-least-once delivery with consumer offset management — duplicate handling is entirely your responsibility
- ❌ No message lock — two consumers can process the same message simultaneously if offset not committed

---

## Decision

**Use Azure Service Bus Topics with subscriptions for the order processing workflow.**

Event Hubs is the right choice for **streaming analytics** (we use it via the Bridge Worker for Kafka). Service Bus is the right choice for **workflow messaging** where reliability, retry, and dead-lettering are first-class requirements.

The workflow messaging problem is a **reliability problem**, not a **throughput problem**. Our peak of 2,000 msg/min is well within Service Bus Standard tier capacity (10M operations/month).

---

## Consequences

**Positive:**
- DLQ is automatic — operations team can inspect failed messages in Azure Portal
- KEDA scales worker pools on queue depth without custom code
- `partitionKey = orderId` gives us ordering guarantees per order for free
- Dead-letter alerting via Azure Monitor is trivial to configure

**Negative:**
- Service Bus Standard tier: ~£0.10/million operations. At 2,000/min × 60 × 24 × 30 ≈ 86M ops/month = ~£8.60/month — acceptable
- Message size cap (256KB) requires large payloads to be stored in Blob and referenced by pointer — not currently needed

**Risk Mitigations:**
- Bridge Worker reads from Service Bus and publishes to Kafka/Event Hubs for analytics consumers — best of both worlds
- Monitor DLQ depth in Azure Monitor; alert if depth > 10 messages

---

## References
- [Azure Service Bus vs Event Hubs — Microsoft Docs](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview)
- [Competing Consumers Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/competing-consumers)
- [KEDA Azure Service Bus Scaler](https://keda.sh/docs/scalers/azure-service-bus/)
