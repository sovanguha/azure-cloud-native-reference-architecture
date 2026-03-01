# ADR-005: Use orderId as Kafka Partition Key

**Date:** 2024-10-18  
**Status:** ✅ Accepted  
**Deciders:** Sovan Guha (Solution Architect), Data Engineering Lead  
**Context:** Kafka partitioning strategy for order event streams (payments.stream, inventory.stream)

---

## Context & Problem

The Bridge Worker publishes order events to Kafka topics consumed by Analytics and Fraud Detection consumer groups. Kafka routes messages to partitions based on a **partition key** — this decision determines throughput, ordering guarantees, and consumer parallelism.

We evaluated four candidate partition keys: `orderId`, `customerId`, `timestamp`, and `orderStatus`.

---

## Why Partition Key Selection Is Critical

A poor partition key choice leads to **hot partitions** — one partition receives disproportionately more messages than others. Hot partitions:
- Create a processing bottleneck that cannot be parallelised
- Cause consumer lag to accumulate on one partition while others are idle
- Degrade end-to-end latency unpredictably
- Cannot be fixed without re-partitioning (requires topic recreation)

---

## Candidate Keys Evaluated

### Option A: `timestamp` ❌ REJECTED

**Problem — Severe Hot Partition Risk**

During peak ordering (e.g., lunch hour, flash sales), thousands of orders arrive within the same second. With `hash(timestamp) mod N`, all events in the same second map to the same partition.

```
12:00:00.000 → partition 2  ← 3,000 events/second all go here
12:00:01.000 → partition 7  ← next second, 3,000 events/second go here
```

**Result:** Extreme hot partitions during peak. Analytics consumer lags by minutes during sale events. **Rejected.**

---

### Option B: `orderStatus` ❌ REJECTED

**Problem — Extreme Cardinality Imbalance**

OrderStatus values: `Placed`, `PaymentCaptured`, `InventoryReserved`, `Shipped`, `Completed`, `Cancelled`

With 6 possible values and 3 partitions:
- `Placed` events dominate (every order starts here) → 40% of all events → hot partition
- `Cancelled` events are rare → one partition almost always idle

**Result:** Structural hot partition that worsens as order volume grows. **Rejected.**

---

### Option C: `customerId` ⚠️ CONDITIONALLY ACCEPTABLE

**Analysis:**

```
hash("cust-00123") mod 3 = partition 0  ← all events for this customer
hash("cust-00456") mod 3 = partition 1
hash("cust-00789") mod 3 = partition 2
```

**Pros:**
- ✅ Events for the same customer are ordered — useful for fraud detection (sequence of customer actions)
- ✅ Reasonably even distribution if customer IDs are UUIDs

**Cons:**
- ❌ **VIP customer problem:** If a B2B customer places 1,000 orders per minute (e.g., enterprise account), all their events hit one partition
- ❌ Not useful for per-order event correlation in analytics (analytics join on orderId, not customerId)
- ❌ GDPR complication: customerId in the partition key makes it harder to delete all events for a customer (would need to know which partition)

**Acceptable for fraud detection use case specifically, but not as the primary partition key.**

---

### Option D: `orderId` ✅ CHOSEN

**Analysis:**

```
hash("ord-a1b2c3") mod 3 = partition 0  ← all events for this order
hash("ord-d4e5f6") mod 3 = partition 1
hash("ord-g7h8i9") mod 3 = partition 2
```

**Distribution:**
Order IDs are UUIDs (v4) — cryptographically random. `hash(UUID) mod N` produces near-perfectly uniform distribution across partitions regardless of order volume distribution.

**Ordering guarantee:**
All events for order `ord-a1b2c3` — `PlaceOrder`, `PaymentCaptured`, `InventoryReserved` — land on the same partition in arrival sequence. Analytics can reconstruct the complete order lifecycle in order without cross-partition joins.

**Pros:**
- ✅ **Even distribution** — UUIDs are random, no hot partitions possible
- ✅ **Per-order event ordering** — Analytics receives order events in sequence
- ✅ **Fraud detection** — complete event sequence per order for anomaly detection
- ✅ **No VIP problem** — one large customer's orders spread evenly across partitions (each order has a unique ID)
- ✅ **Simple implementation** — `producer.send(new ProducerRecord<>(topic, orderId, event))`

**Cons:**
- ❌ Events for the same *customer* are not ordered across partitions — acceptable, we do not have this requirement
- ❌ Cannot reconstruct per-customer event sequence from Kafka alone — acceptable, use Cosmos DB Change Feed for customer-level queries

---

## Decision

**Use `orderId` as the Kafka partition key for all order event streams.**

`orderId` (UUID v4) provides uniform distribution, per-order event ordering, and no structural hot partition risk under any load pattern.

---

## Implementation

**Bridge Worker — Producer Configuration:**
```csharp
var config = new ProducerConfig
{
    BootstrapServers = kafkaBootstrap,
    // Key serialiser handles orderId string → bytes → hash
};

using var producer = new ProducerBuilder<string, OrderEvent>(config)
    .SetValueSerializer(new JsonSerializer<OrderEvent>())
    .Build();

await producer.ProduceAsync(
    topic: "orders.payments",
    message: new Message<string, OrderEvent>
    {
        Key   = orderEvent.OrderId,   // ← partition key
        Value = orderEvent
    });
```

**Topic Configuration:**
```
Topic: orders.payments
Partitions: 3          (start small; increase as throughput demands)
Replication factor: 3  (tolerate 2 broker failures)
Retention: 7 days
Cleanup policy: delete (not compact — we want full event history)
```

**Partition Count Guidance:**

| Throughput | Recommended Partitions |
|---|---|
| < 1,000 events/sec | 3 |
| 1,000–10,000 events/sec | 6–12 |
| > 10,000 events/sec | 12–24 |

*Start at 3. Partitions can only be increased, never decreased. Increase before you hit the limit, not after.*

---

## Consequences

**Positive:**
- Zero hot partition risk — uniform distribution guaranteed by UUID randomness
- Per-order event ordering enables Analytics to reconstruct order lifecycle
- Adding more consumer instances scales linearly up to partition count
- KEDA Consumer Lag scaler: `target lag per instance = 1000 messages` → scales Analytics consumers automatically

**Negative:**
- If consumer group instance count > partition count, excess instances are idle — document this constraint clearly
- Partition count increase requires careful coordination (rebalancing in-flight)

**Monitoring:**
```
Alert: consumer lag > 10,000 messages on any partition → scale out consumer group
Alert: max partition offset - min partition offset > 50% of average → hot partition forming
```

---

## References
- [Kafka Partitioning Strategy — Confluent](https://www.confluent.io/blog/how-to-increase-number-of-partitions-in-kafka-topic/)
- [KEDA Kafka Consumer Lag Scaler](https://keda.sh/docs/scalers/apache-kafka/)
- [Hot Partition Anti-pattern](https://aws.amazon.com/builders-library/avoiding-insurmountable-queue-backlogs/)
