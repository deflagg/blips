namespace blipFeedFanout;

using System.Text.Json;
using Azure.Messaging.EventHubs.Consumer;
using Azure.Messaging.EventHubs;
using Gremlin.Net.Driver;
using Microsoft.Extensions.Options;
using StackExchange.Redis;
using System.Text.Json.Serialization;
using BlipFeedFanout.Models;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly EventHubConsumerClient _consumer;
    private readonly GremlinClient _gremlin;
    private readonly IConnectionMultiplexer? _redis; // null if no Redis configured
    private readonly EventHubsOptions _eh;
    private readonly TimelineOptions _timeline;
    private readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web);

    public Worker(
        ILogger<Worker> logger,
        EventHubConsumerClient consumer,
        GremlinClient gremlin,
        IOptions<EventHubsOptions> eh,
        IOptions<TimelineOptions> timeline,
        IConnectionMultiplexer? redis = null)
    {
        _logger = logger;
        _consumer = consumer;
        _gremlin = gremlin;
        _redis = redis;
        _eh = eh.Value;
        _timeline = timeline.Value;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Fanout worker starting… ConsumerGroup={Group} StartFromEarliest={Earliest}",
            _consumer.ConsumerGroup, _eh.StartFromEarliest);

        // spin up a loop per partition so we have explicit control over starting positions
        var partitions = await _consumer.GetPartitionIdsAsync(stoppingToken);
        var tasks = partitions.Select(id => ProcessPartitionAsync(id, stoppingToken)).ToArray();

        try
        {
            await Task.WhenAll(tasks);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // graceful shutdown
        }
    }

    private async Task ProcessPartitionAsync(string partitionId, CancellationToken ct)
    {
        var start = _eh.StartFromEarliest ? EventPosition.Earliest : EventPosition.Latest;
        _logger.LogInformation("Reading partition {PartitionId} from {Start}", partitionId, start);

        await foreach (var pe in _consumer.ReadEventsFromPartitionAsync(partitionId, start, ct))
        {
            if (pe.Data is null) continue;

            try
            {
                await HandleEventAsync(pe.Data, ct);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error handling event on partition {PartitionId}", partitionId);
            }
        }
    }

    private record BlipCreated(string? type, string id, string userId, string text, DateTimeOffset ts);

    private static RedisKey HomeZKey(string userId) => $"z:home:{userId}";
    //private static RedisKey UserZKey(string userId) => $"z:user:{userId}";

    // Keep only the newest `max` items by removing the lowest ranks.
    private static Task TrimTimelineAsync(IDatabase db, RedisKey key, int max)
        => db.SortedSetRemoveRangeByRankAsync(key, 0, -max - 1);

    private async Task HandleEventAsync(EventData e, CancellationToken ct)
    {
        var schemaOk = e.Properties.TryGetValue("schema", out var s) && string.Equals(s?.ToString(), "blip.v1", StringComparison.Ordinal);
        var srcOk    = e.Properties.TryGetValue("source", out var src) && string.Equals(src?.ToString(), "blip-writer", StringComparison.Ordinal);
        var isJson   = string.Equals(e.ContentType, "application/json", StringComparison.OrdinalIgnoreCase);

        if (!schemaOk || !srcOk || !isJson)
        {
            _logger.LogDebug("Skipping non-blip event (ContentType={CT})", e.ContentType);
            return;
        }

        var payload = e.EventBody.ToString(); // <-- full JSON from the writer
        var msg = JsonSerializer.Deserialize<BlipCreated>(payload, _json);
        if (msg is null || !string.Equals(msg.type, "blip.created", StringComparison.Ordinal))
        {
            _logger.LogDebug("Skipping event with missing/invalid type");
            return;
        }

        _logger.LogInformation("blip.created id={Id} user={User} at={Ts:O}", msg.id, msg.userId, msg.ts);

        if (_redis is null)
        {
            _logger.LogWarning("Redis not configured; skipping fanout");
            return;
        }

        var db = _redis.GetDatabase();
        var score = msg.ts.ToUnixTimeMilliseconds();

        // 1) Author's own timeline gets the full JSON
        // var authorKey = UserZKey(msg.userId);
        // Add/refresh author timeline entry
        // await db.SortedSetAddAsync(authorKey, payload, score).ConfigureAwait(false);
        // await TrimTimelineAsync(db, authorKey, _timeline.MaxItems).ConfigureAwait(false);

        // 2) Followers -> home feeds (full JSON)
        IReadOnlyList<string> followerIds = Array.Empty<string>();
        try
        {
            var script = "g.V().has('person','personId',uid).in('follows').values('personId')";
            var rs = await _gremlin.SubmitAsync<string>(
                        script,
                        new Dictionary<string, object?> { ["uid"] = msg.userId })
                    .ConfigureAwait(false);
            followerIds = rs.ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Gremlin follower lookup failed for {UserId}", msg.userId);
        }

        if (followerIds.Count > 0)
        {
            var batch = db.CreateBatch();
            var tasks = new List<Task>(2 * followerIds.Count);

            foreach (var fid in followerIds)
            {
                var homeKey = HomeZKey(fid);
                tasks.Add(batch.SortedSetAddAsync(homeKey, payload, score));
                tasks.Add(TrimTimelineAsync(batch, homeKey, _timeline.MaxItems));
            }

            batch.Execute();
            await Task.WhenAll(tasks).ConfigureAwait(false);
        }
    }


    private static async Task TrimTimelineAsync(IDatabaseAsync db, string key, int maxItems)
    {
        if (maxItems <= 0) return;

        var len = await db.SortedSetLengthAsync(key);
        var excess = len - maxItems;
        if (excess > 0)
        {
            await db.SortedSetRemoveRangeByRankAsync(key, 0, excess - 1);
        }
    }
}
