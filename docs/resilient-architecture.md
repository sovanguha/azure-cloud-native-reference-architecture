A resilient architecture means your application should be available for customers while recovering from failure.
Making your architecture resilient includes applying best practices to recover your application from increased loads due to more user requests, 
malicious attacks, and architectural component failure. Resiliency needs to be used in all architectural layers, including infrastructure, 
application, database, security, and networking. A resilient architecture should recover from failure within a desired amount of time.

![Application architecture resiliency using a DNS server](./diagrams/resiliency-architecture-using-dnsserver.png)

• Redundancy is a crucial aspect of building resilient systems. 

• Use the CDN to distribute and cache static content such as videos, images, and static web pages 
near the user’s location so that your application will still be available.

• Once traffic reaches a region, use a load balancer to route traffic to a fleet of servers so that 
your application can still run even if one location fails within your region.

• Use autoscaling to add or remove servers based on user demand. As a result, your application 
should not be impacted by individual server failures.

• Create a standby database to ensure the high availability of the database, meaning that your 
application should be available in the event of a database failure.