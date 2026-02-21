
• When a user types a website address into the browser, the user request reaches out to the DNS server to load the website.
  The DNS requests for the website are routed by Amazon Route 53 to the server where the web applications are being hosted.
• The user base is global, and users continue browsing for products to purchase as the website as an extensive product catalog 
  with static images and videos. A content distribution network like Amazon CloudFront caches and delivers static assets to users.
• The catalog contents, such as static product images and videos, and other application data, such as log files, are stored in Amazon S3.
• Users will browse the website from multiple devices; for example, they will add items to a cart from their mobile 
  and then make a payment on a desktop. A persistent session store, such as DynamoDB, is required to handle user sessions. 
  DynamoDB is a NoSQL database where you don’t need to provide a fixed schema, so it is a great storage option for product catalogs and attributes.
• Amazon ElastiCache is used as a caching layer for the product to reduce read and write operations on the database to provide
  high performance and reduce latency.
• A convenient search feature is vital for product sales and business success. Amazon CloudSearch helps to build scalable search
  capability by loading the product catalog from DynamoDB. You can also use Amazon Kendra for an AI-powered search engine. 
• A recommendation can encourage users to buy additional products based on browsing history and past purchases. 
  A separate recommendation service can consume the log data stored on Amazon S3 and provide potential product recommendations to the user.
• The e-commerce application can also have multiple layers and components that require frequent deployment. AWS Elastic Beanstalk handles
  the auto-provisioning of the infrastructure, deploys the application, handles the load by applying auto-scaling, and monitors the application.