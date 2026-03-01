// ============================================================
// PaymentWorker — Idempotent Service Bus Message Processor
// 
// Key patterns demonstrated:
//   1. Idempotency via messageId check before processing
//   2. Circuit breaker protecting downstream payment gateway
//   3. Structured logging with correlationId for distributed tracing
//   4. MaxConcurrentCalls cap (back-pressure)
//   5. Managed Identity auth (no connection strings)
// ============================================================

using Azure.Messaging.ServiceBus;
using System.Text.Json;

namespace OrderPlatform.Worker;

public sealed class PaymentWorker : BackgroundService
{
    private readonly ServiceBusClient     _client;
    private readonly string               _topicName;
    private readonly string               _subscriptionName;
    private readonly int                  _maxConcurrentCalls;
    private readonly IIdempotencyStore    _idempotency;
    private readonly IPaymentGateway      _gateway;
    private readonly ICircuitBreaker      _circuitBreaker;
    private readonly ILogger<PaymentWorker> _logger;

    private ServiceBusProcessor? _processor;

    public PaymentWorker(
        ServiceBusClient client,
        string topicName,
        string subscriptionName,
        int maxConcurrentCalls,
        IIdempotencyStore idempotency,
        IPaymentGateway gateway,
        ICircuitBreaker circuitBreaker,
        ILogger<PaymentWorker> logger)
    {
        _client             = client;
        _topicName          = topicName;
        _subscriptionName   = subscriptionName;
        _maxConcurrentCalls = maxConcurrentCalls;
        _idempotency        = idempotency;
        _gateway            = gateway;
        _circuitBreaker     = circuitBreaker;
        _logger             = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var options = new ServiceBusProcessorOptions
        {
            // ── Back-pressure: cap concurrent processing ──────
            MaxConcurrentCalls = _maxConcurrentCalls,
            // Pre-fetch: buffer ahead for throughput
            PrefetchCount = _maxConcurrentCalls * 2,
            // Auto-complete disabled: we control complete/abandon explicitly
            AutoCompleteMessages = false,
            // Lock renewal handled automatically by SDK
            MaxAutoLockRenewalDuration = TimeSpan.FromMinutes(5),
            ReceiveMode = ServiceBusReceiveMode.PeekLock
        };

        _processor = _client.CreateProcessor(
            _topicName, _subscriptionName, options);

        _processor.ProcessMessageAsync += HandleMessageAsync;
        _processor.ProcessErrorAsync   += HandleErrorAsync;

        _logger.LogInformation(
            "PaymentWorker starting. Topic={Topic} Subscription={Sub} MaxConcurrent={Max}",
            _topicName, _subscriptionName, _maxConcurrentCalls);

        await _processor.StartProcessingAsync(stoppingToken);

        // Block until cancellation
        await Task.Delay(Timeout.Infinite, stoppingToken)
                  .ContinueWith(_ => { }, CancellationToken.None);

        await _processor.StopProcessingAsync();
    }

    private async Task HandleMessageAsync(ProcessMessageEventArgs args)
    {
        var messageId     = args.Message.MessageId;
        var correlationId = args.Message.CorrelationId ?? Guid.NewGuid().ToString();

        // ── Structured log context ───────────────────────────
        using var scope = _logger.BeginScope(new Dictionary<string, object>
        {
            ["MessageId"]     = messageId,
            ["CorrelationId"] = correlationId,
            ["DeliveryCount"] = args.Message.DeliveryCount
        });

        _logger.LogInformation("Processing payment message");

        try
        {
            // ── 1. Idempotency check ─────────────────────────
            if (await _idempotency.HasBeenProcessedAsync(messageId))
            {
                _logger.LogWarning(
                    "Duplicate message detected — already processed. Completing without action.");
                await args.CompleteMessageAsync(args.Message);
                return;
            }

            // ── 2. Deserialise payload ────────────────────────
            var placeOrder = JsonSerializer.Deserialize<PlaceOrderMessage>(
                args.Message.Body.ToString())
                ?? throw new InvalidOperationException("Failed to deserialise PlaceOrderMessage");

            // ── 3. Circuit breaker check ──────────────────────
            if (_circuitBreaker.IsOpen)
            {
                _logger.LogWarning(
                    "Circuit breaker OPEN — deferring message for {Delay}s",
                    _circuitBreaker.RetryAfterSeconds);

                // Defer: message stays in Service Bus, redelivered after lock expires
                await args.AbandonMessageAsync(args.Message,
                    new Dictionary<string, object>
                    {
                        ["DeferReason"] = "CircuitBreakerOpen",
                        ["RetryAfter"]  = DateTime.UtcNow.AddSeconds(_circuitBreaker.RetryAfterSeconds)
                    });
                return;
            }

            // ── 4. Process payment ────────────────────────────
            var result = await _gateway.CapturePaymentAsync(
                orderId:       placeOrder.OrderId,
                amount:        placeOrder.Amount,
                correlationId: correlationId,
                cancellationToken: args.CancellationToken);

            // ── 5. Mark as processed (idempotency store) ──────
            await _idempotency.MarkProcessedAsync(
                messageId, expiry: TimeSpan.FromHours(24));

            _logger.LogInformation(
                "Payment captured. OrderId={OrderId} PaymentRef={PaymentRef}",
                placeOrder.OrderId, result.PaymentReference);

            // ── 6. Complete (remove from subscription) ────────
            await args.CompleteMessageAsync(args.Message);

            _circuitBreaker.RecordSuccess();
        }
        catch (PaymentGatewayException ex) when (ex.IsTransient)
        {
            // Transient failure — abandon for retry
            _circuitBreaker.RecordFailure();
            _logger.LogWarning(ex,
                "Transient payment gateway error. DeliveryCount={Count}",
                args.Message.DeliveryCount);
            await args.AbandonMessageAsync(args.Message);
        }
        catch (Exception ex)
        {
            // Permanent failure — dead-letter for manual inspection
            _logger.LogError(ex, "Permanent failure processing payment message");
            await args.DeadLetterMessageAsync(args.Message,
                deadLetterReason: "PermanentProcessingFailure",
                deadLetterErrorDescription: ex.Message);
        }
    }

    private Task HandleErrorAsync(ProcessErrorEventArgs args)
    {
        _logger.LogError(args.Exception,
            "Service Bus processor error. Source={Source} EntityPath={Path}",
            args.ErrorSource, args.EntityPath);
        return Task.CompletedTask;
    }

    public override async ValueTask DisposeAsync()
    {
        if (_processor is not null)
            await _processor.DisposeAsync();
        await base.DisposeAsync();
    }
}

// ── Domain Models ─────────────────────────────────────────────

public record PlaceOrderMessage(
    string OrderId,
    string CustomerId,
    decimal Amount,
    List<OrderItem> Items,
    string MessageId,
    string CorrelationId,
    DateTimeOffset Timestamp);

public record OrderItem(
    string ProductId,
    int Quantity,
    decimal UnitPrice);
