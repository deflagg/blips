using System.Net;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace BlipFeed.Infrastructure;

public interface ICosmosInitializer
{
    Task InitializeAsync(CancellationToken ct = default);
}

public sealed class CosmosSchema
{
    public List<DatabaseSpec> Databases { get; init; } = new();
}

public sealed class DatabaseSpec
{
    public string Id { get; init; } = default!;
    public int? Throughput { get; init; }  // null => serverless or shared container throughput
    public List<ContainerSpec> Containers { get; init; } = new();
}

public sealed class ContainerSpec
{
    public string Id { get; init; } = default!;
    public string PartitionKeyPath { get; init; } = default!;
    public int? Throughput { get; init; } // null => rely on DB throughput / serverless
    public List<string[]>? UniqueKeySets { get; init; } // e.g., [ ["/email"], ["/tenantId","/username"] ]
    public int? DefaultTtlSeconds { get; init; } // e.g., -1 (off) or N seconds
    public bool? ExcludeAllFromIndexing { get; init; } // optional convenience
}


public sealed class CosmosInitializer : ICosmosInitializer
{
    private readonly CosmosClient _client;
    private readonly ILogger<CosmosInitializer> _logger;
    private readonly CosmosSchema _schema;

    public CosmosInitializer(
        CosmosClient client,
        IOptions<CosmosSchema> schemaOptions,
        ILogger<CosmosInitializer> logger)
    {
        _client = client;
        _schema = schemaOptions.Value;
        _logger = logger;
    }

    public async Task InitializeAsync(CancellationToken ct = default)
    {
        foreach (var dbSpec in _schema.Databases)
        {
            _logger.LogInformation("Ensuring Cosmos DB '{DbId}' exists.", dbSpec.Id);

            Database db;
            try
            {
                // First try without throughput (works for serverless or when you'll set container-level throughput)
                var dbResp = await _client.CreateDatabaseIfNotExistsAsync(dbSpec.Id, cancellationToken: ct);
                db = dbResp.Database;
            }
            catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.BadRequest && dbSpec.Throughput is not null)
            {
                _logger.LogWarning("DB creation without throughput failed; retrying with {RU} RU. Error: {Msg}",
                    dbSpec.Throughput, ex.Message);

                var dbResp = await _client.CreateDatabaseIfNotExistsAsync(
                    dbSpec.Id,
                    throughput: dbSpec.Throughput,
                    cancellationToken: ct);

                db = dbResp.Database;
            }

            foreach (var cSpec in dbSpec.Containers)
            {
                await EnsureContainerAsync(db, cSpec, ct);
            }

            _logger.LogInformation("Cosmos DB '{DbId}' ready.", dbSpec.Id);
        }
    }

    private async Task EnsureContainerAsync(Database db, ContainerSpec spec, CancellationToken ct)
    {
        _logger.LogInformation("Ensuring container '{ContainerId}' in DB '{DbId}'.",
            spec.Id, db.Id);

        var props = new ContainerProperties(spec.Id, spec.PartitionKeyPath);

        // Unique keys
        if (spec.UniqueKeySets is { Count: > 0 })
        {
            props.UniqueKeyPolicy ??= new UniqueKeyPolicy();
            foreach (var set in spec.UniqueKeySets)
            {
                var uk = new UniqueKey();
                foreach (var path in set)
                {
                    uk.Paths.Add(path);
                }
                props.UniqueKeyPolicy.UniqueKeys.Add(uk);
            }
        }

        // TTL
        if (spec.DefaultTtlSeconds.HasValue)
        {
            props.DefaultTimeToLive = spec.DefaultTtlSeconds;
        }

        // Indexing convenience: exclude all (you can refine later per-path)
        if (spec.ExcludeAllFromIndexing == true)
        {
            props.IndexingPolicy = new IndexingPolicy
            {
                IndexingMode = IndexingMode.Consistent,
                Automatic = true,
                IncludedPaths = { }, // none
                ExcludedPaths = { new ExcludedPath { Path = "/*" } }
            };
        }

        try
        {
            // Try creation without throughput first
            await db.CreateContainerIfNotExistsAsync(props, throughput: null, cancellationToken: ct);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.BadRequest)
        {
            var ru = spec.Throughput ?? 400; // minimal dedicated RU fallback
            _logger.LogWarning("Container creation without throughput failed; retrying with {RU} RU. Error: {Msg}", ru, ex.Message);

            await db.CreateContainerIfNotExistsAsync(props, throughput: ru, cancellationToken: ct);
        }

        _logger.LogInformation("Container '{ContainerId}' ready in DB '{DbId}'.", spec.Id, db.Id);
    }
}
