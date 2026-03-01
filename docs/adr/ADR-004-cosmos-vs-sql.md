# ADR-004: Cosmos DB for Inventory, Azure SQL for Payment Records

**Date:** 2024-10-10  
**Status:** ✅ Accepted  
**Deciders:** Sovan Guha (Solution Architect), Data Lead, Compliance Officer  
**Context:** Data store selection for order processing — payment capture records and inventory reservation state

---

## Context & Problem

Two distinct data domains with fundamentally different characteristics:

**Payment records:**
- Require ACID transactions (debit must match credit, always)
- Regulatory requirement: immutable audit trail, 7-year retention
- Strong consistency mandatory — no stale reads permitted
- Schema is stable and well-understood
- Relatively low volume: ~500 writes/minute peak

**Inventory state:**
- Global product catalogue: ~2M SKUs
- Write-heavy during flash sales: ~5,000 reservation updates/second peak
- Read-heavy for product lookup: ~50,000 reads/second
- Partition by productId for horizontal scale
- Eventual consistency acceptable for reads (stock display)
- Strong consistency required for reservation commits only

---

## Decision Drivers

- Payment records: ACID compliance is non-negotiable (financial regulation)
- Inventory: horizontal scalability must handle 10x traffic spikes without re-architecture
- Minimise operational overhead — prefer managed PaaS
- Cost: right-size to workload characteristics (not over-provision)
- Cosmos DB DP-420 certification already held by architect — team capability exists

---

## Options Considered

### Option A: Azure SQL for Both

**Pros:**
- Single data platform, simpler operations
- Full ACID, familiar to team
- Azure SQL Hyperscale can scale reads horizontally

**Cons:**
- ❌ Vertical scaling model doesn't match inventory's horizontal scale requirement
- ❌ Schema migrations required for product catalogue evolution
- ❌ At 5,000 writes/second, Azure SQL Premium tier becomes expensive (DTU model)
- ❌ Geographic distribution requires complex SQL replication setup

---

### Option B: Cosmos DB for Both

**Pros:**
- Consistent platform
- Horizontal scale for both domains

**Cons:**
- ❌ **Cosmos DB does not support multi-document ACID transactions across containers** (only within a partition)
- ❌ Payment records require cross-record consistency that Cosmos DB cannot guarantee without complex application-level coordination
- ❌ Auditors require relational query capability for payment reports — Cosmos DB SQL API is limited for JOIN-heavy audit queries

---

### Option C: Azure SQL for Payments, Cosmos DB for Inventory ✅ CHOSEN

Right tool for each data domain.

**Azure SQL for Payments:**
- ✅ Full ACID transactions — debit/credit atomically committed
- ✅ Row-level security for PCI DSS compliance
- ✅ Built-in auditing to Azure Storage (7-year log retention)
- ✅ Read replicas for reporting workloads
- ✅ Azure SQL Ledger (immutable, cryptographically verified audit trail)
- ✅ Familiar to compliance and audit teams

**Cosmos DB (NoSQL API) for Inventory:**
- ✅ Partition key = `productId` — horizontal scale with no hot partitions
- ✅ 99.999% availability SLA with multi-region writes
- ✅ `etag`-based optimistic concurrency for reservation commits (prevents overselling)
- ✅ Change Feed enables real-time inventory events downstream
- ✅ Scale RU/s up during flash sales, down overnight — FinOps aligned
- ✅ Schema flexibility for product attribute variations across 2M SKUs

---

## Decision

**Azure SQL for payment records. Cosmos DB (NoSQL API) for inventory.**

The core principle: **choose the data store that makes the hard problem easy**. ACID compliance is the hard problem for payments — Azure SQL solves it natively. Horizontal scale at 5,000 writes/second is the hard problem for inventory — Cosmos DB solves it natively.

---

## Implementation Notes

**Cosmos DB Partition Key Strategy:**
```
Container: inventory-reservations
Partition key: /productId
```
- Each productId's reservations are co-located in the same partition
- Reservation check + commit is a single-partition transaction (ACID within partition)
- Avoids cross-partition transactions which are eventually consistent

**Idempotency on Cosmos DB:**
```csharp
// Use messageId as idempotency key — upsert with condition
var options = new ItemRequestOptions
{
    IfMatchEtag = existingItem.ETag  // Optimistic concurrency
};
await container.UpsertItemAsync(reservation, 
    new PartitionKey(reservation.ProductId), options);
```

**Azure SQL Ledger for Payment Audit:**
```sql
CREATE TABLE PaymentCaptures
(
    PaymentId       UNIQUEIDENTIFIER NOT NULL,
    CorrelationId   UNIQUEIDENTIFIER NOT NULL,
    Amount          DECIMAL(18,2)    NOT NULL,
    CapturedAt      DATETIME2        NOT NULL,
    -- Ledger columns added automatically:
    -- ledger_start_transaction_id, ledger_end_transaction_id
    -- ledger_start_sequence_number, ledger_end_sequence_number
)
WITH (LEDGER = ON);
```

---

## Consequences

**Positive:**
- Payment ACID compliance met without complex application coordination
- Inventory scales to 5,000 writes/second by adding RU/s — no re-architecture
- Cosmos DB Change Feed triggers Bridge Worker → Kafka streaming pipeline for analytics
- Flash sale auto-scale: RU/s bumped 2 hours before sale, reduced after

**Negative:**
- Two data platforms to monitor and operate
- Team needs Cosmos DB proficiency — mitigated by DP-420 certification held
- Data access patterns must be designed partition-key-first — requires architectural discipline

**Cost Estimate (monthly):**
- Azure SQL Business Critical (4 vCores): ~£400/month
- Cosmos DB 10,000 RU/s (autoscale 1,000–10,000): ~£80/month base + consumption
- Total: ~£480/month vs £650/month for SQL-only at equivalent inventory scale

---

## References
- [Cosmos DB Partition Key Design](https://learn.microsoft.com/en-us/azure/cosmos-db/partitioning-overview)
- [Azure SQL Ledger](https://learn.microsoft.com/en-us/azure/azure-sql/database/ledger-overview)
- [Cosmos DB Change Feed](https://learn.microsoft.com/en-us/azure/cosmos-db/change-feed)
- [Optimistic Concurrency in Cosmos DB](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/database-transactions-optimistic-concurrency)
