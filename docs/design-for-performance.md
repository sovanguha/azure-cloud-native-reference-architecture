Like resiliency, the solutions architect needs to consider performance at every layer of architecture design.

Better performance means increased user engagement and return on investment.

High-performance applications are designed to handle application slowness due to external factors such as a slow internet connection.

In an ideal environment, as your application workload increases, automated scaling mechanisms start handling additional requests without
impacting application performance. But in the real world, your application latency goes down for a short duration when scaling takes effect.

Choose the correct input/output operations per second (IOPS) for storage. You need high IOPS for write-intensive applications to reduce
latency and increase disk write speed.

To achieve higher performance, apply caching at every layer of your architecture design. Caching makes your data locally available 
to users or keeps data in memory to serve an ultra-fast response.

The following are considerations for adding caching to various layers of your application design:
• Use the browser cache on the user’s system to load frequently requested web pages.
• Use the DNS cache for quick website lookup.
• Use the CDN cache for high-resolution images and videos that are near the user’s location.
• At the server level, maximize the memory cache to serve user requests.
• Use cache engines such as Redis and Memcached to serve frequent queries from the caching engine.
• Use the database cache to serve frequent queries from memory.
• Take care of cache expiration, which is the process by which data stored in the cache becomes outdated and is marked for update or removal. 
  Cache eviction, on the other hand, is the process by which data is removed from the cache, typically to make room for new data. 