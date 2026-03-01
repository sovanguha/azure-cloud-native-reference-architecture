// ============================================================
// Azure Service Bus Worker — .NET 8 Sample
// Pattern: Idempotent message processor with circuit breaker
// Auth: Managed Identity (DefaultAzureCredential) — no secrets
// ============================================================

using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Azure;
using OrderPlatform.Worker;

var builder = Host.CreateApplicationBuilder(args);

// ── Configuration ─────────────────────────────────────────────
var sbNamespace = builder.Configuration["ServiceBus:Namespace"]
    ?? throw new InvalidOperationException("ServiceBus:Namespace is required");
var topicName   = builder.Configuration["ServiceBus:TopicName"] ?? "orders";
var subName     = builder.Configuration["ServiceBus:SubscriptionName"] ?? "payment-subscription";

// ── Azure Clients (Managed Identity — no connection strings) ──
builder.Services.AddAzureClients(clients =>
{
    // DefaultAzureCredential: Managed Identity in AKS, developer credential locally
    var credential = new DefaultAzureCredential();

    clients.AddServiceBusClientWithNamespace(sbNamespace)
           .WithCredential(credential);

    clients.ConfigureDefaults(opts =>
        opts.Diagnostics.IsLoggingEnabled = true);
});

// ── Application Services ──────────────────────────────────────
builder.Services.AddSingleton<IIdempotencyStore, RedisIdempotencyStore>();
builder.Services.AddSingleton<IPaymentGateway, PaymentGatewayClient>();
builder.Services.AddSingleton<ICircuitBreaker, CircuitBreaker>(sp =>
    new CircuitBreaker(
        failureThreshold: 5,
        openDurationSeconds: 30,
        logger: sp.GetRequiredService<ILogger<CircuitBreaker>>()
    ));

builder.Services.AddHostedService<PaymentWorker>(sp =>
    new PaymentWorker(
        sp.GetRequiredService<ServiceBusClient>(),
        topicName, subName,
        maxConcurrentCalls: int.Parse(builder.Configuration["Worker:MaxConcurrentCalls"] ?? "10"),
        sp.GetRequiredService<IIdempotencyStore>(),
        sp.GetRequiredService<IPaymentGateway>(),
        sp.GetRequiredService<ICircuitBreaker>(),
        sp.GetRequiredService<ILogger<PaymentWorker>>()
    ));

// ── Health Checks (AKS liveness + readiness probes) ──────────
builder.Services.AddHealthChecks()
    .AddAzureServiceBusTopicSubscription(
        sp => sp.GetRequiredService<ServiceBusAdministrationClient>(),
        topicName, subName,
        name: "servicebus")
    .AddCheck<CircuitBreakerHealthCheck>("circuit-breaker");

builder.Services.AddHostedService<HealthCheckBackgroundService>();

// ── Observability ─────────────────────────────────────────────
builder.Services.AddApplicationInsightsTelemetryWorkerService(
    builder.Configuration["ApplicationInsights:ConnectionString"]);
builder.Logging.AddApplicationInsights();

var host = builder.Build();
await host.RunAsync();
