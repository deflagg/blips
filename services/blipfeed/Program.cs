using System.Globalization; // RU formatting
using Microsoft.Azure.Cosmos;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.OpenApi.Models;
using BlipFeed.Contracts;
using BlipFeed.Infrastructure;
using BlipFeed.Models;
using Microsoft.Net.Http.Headers;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Azure.Identity;
using Azure.ResourceManager.CosmosDB;
using Gremlin.Net.Driver;
using Gremlin.Net.Structure.IO.GraphSON;
using Azure.Core;

using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.StackExchangeRedis;
using System.Text.Json.Serialization;


var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseKestrel((context, options) =>
{
    options.Configure(context.Configuration.GetSection("Kestrel"));
});

// ---------- Swagger ----------
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Blips API", Version = "v1" });
});

// ---------- Options + CosmosClient (singleton) --------
builder.Services.Configure<CosmosOptions>(builder.Configuration.GetSection("Cosmos"));

builder.Services.AddSingleton<CosmosClient>(sp =>
{
    var opt = sp.GetRequiredService<IOptions<CosmosOptions>>().Value;

    // Allow quick override to force IPv4 if needed (helps on some stacks)
    var endpoint = opt.Endpoint;


    var clientOptions = new CosmosClientOptions
    {
        ApplicationName = "Blips.BlipFeed",
        ConnectionMode = ConnectionMode.Gateway,   // emulator-friendly (unchanged)
        LimitToEndpoint = true,                    // (unchanged)
        SerializerOptions = new CosmosSerializationOptions
        {
            PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
        }
    };

    // DEV-ONLY: if hitting the emulator, bypass proxy and trust self-signed cert
    if (!string.IsNullOrWhiteSpace(endpoint) &&
        (endpoint.Contains("localhost", StringComparison.OrdinalIgnoreCase) ||
         endpoint.Contains("127.0.0.1")))
    {
        clientOptions.HttpClientFactory = () =>
        {
            var handler = new HttpClientHandler
            {
                UseProxy = false,
                Proxy = null,
                ServerCertificateCustomValidationCallback =
                    HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
            };

            return new HttpClient(handler, disposeHandler: true)
            {
                Timeout = TimeSpan.FromSeconds(65)
            };
        };
        
        return new CosmosClient(endpoint, opt.Key, clientOptions);

    }

    //return new CosmosClient(endpoint, key, clientOptions);
    return new CosmosClient(endpoint, new DefaultAzureCredential(), clientOptions);
});

// ---------- Gremlin (Person graph) ----------
builder.Services.Configure<GremlinOptions>(builder.Configuration.GetSection("PersonGraphDB"));

builder.Services.AddSingleton<GremlinClient>(sp =>
{
    var options = sp.GetRequiredService<IOptions<GremlinOptions>>().Value;
    var username = $"/dbs/{options.Common.DatabaseId}/colls/{options.Common.GraphId}";

    if (options.Mode == GremlinMode.Emulator)
    {
        var emulator = options.Emulator ?? throw new InvalidOperationException("Person graph emulator configuration missing.");
        var server = new GremlinServer(
            hostname: emulator.Host,
            port: emulator.Port,
            enableSsl: false,
            username: username,
            password: emulator.AuthKey);

        return new GremlinClient(server, new GraphSON2MessageSerializer());
    }
    else
    {
        var cloud = options.Cloud ?? throw new InvalidOperationException("Person graph cloud configuration missing.");
        var token = new DefaultAzureCredential().GetToken(new TokenRequestContext(new[] { "https://cosmos.azure.com/.default" })).Token;
        var server = new GremlinServer(
            hostname: $"{cloud.AccountName}.gremlin.cosmos.azure.com",
            port: 443,
            enableSsl: true,
            username: username,
            password: token);

        return new GremlinClient(server, new GraphSON2MessageSerializer());
    }
});

builder.Services.AddSingleton<IPersonRepository>(sp =>
    new PersonRepository(sp.GetRequiredService<GremlinClient>()));

// ---------- Redis Cache --------
builder.Services.Configure<RedisOptions>(builder.Configuration.GetSection("BlipsCache"));

// Add distributed cache using those options; fallback to memory cache if disabled/missing
var cacheCfg = builder.Configuration.GetSection("BlipsCache").Get<RedisOptions>() ?? new();
if (cacheCfg.Enabled && !string.IsNullOrWhiteSpace(cacheCfg.ConnectionString))
{
    builder.Services.AddStackExchangeRedisCache(o =>
    {
        o.Configuration = cacheCfg.ConnectionString;
        o.InstanceName = cacheCfg.InstanceName;
    });
}
else
{
    builder.Services.AddDistributedMemoryCache(); // keeps the app running even if Redis is off
}


// ---------- CORS ------------
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll",
        builder => builder.AllowAnyOrigin()
                          .AllowAnyMethod()
                          .AllowAnyHeader()
                          .WithExposedHeaders(
            "x-ms-request-charge", // <- RU header you set
            "ETag",
            "Location",
            "x-ms-activity-id",
            "x-ms-request-duration"));
});

builder.Services
        .AddHealthChecks()
        .AddCheck("self", () => HealthCheckResult.Healthy(), tags: new[] { "ready" });

// ---------- App Services ----------
builder.Services.AddSingleton<IBlipsRepository, CosmosBlipsRepository>();
builder.Services.AddSingleton<ICosmosInitializer, CosmosInitializer>();

var app = builder.Build();

app.Logger.LogInformation("ENV={Env}", app.Environment.EnvironmentName);

app.UseCors("AllowAll");

// Create DB/container automatically in Development
if (app.Environment.IsDevelopment())
{
    await app.Services.GetRequiredService<ICosmosInitializer>().InitializeAsync();
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = reg => reg.Tags.Contains("live")   // run only the failing check
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = reg => reg.Tags.Contains("ready")  // run only the ready checks
});


// ---------- Blips endpoints ----------
var group = app.MapGroup("/blips").WithTags("Blips");

// GET /blips/{id}?userId=...
// group.MapGet("/{id}", async Task<Results<Ok<BlipDto>, NotFound>> (
//     string id,
//     string userId,
//     IBlipsRepository repo,
//     HttpResponse res,
//     CancellationToken ct) =>
// {
//     var found = await repo.GetAsync(id, userId, ct);
//     if (found is null) return TypedResults.NotFound();

//     var (item, etag) = found.Value;
//     res.Headers.ETag = $"\"{etag}\"";
//     return TypedResults.Ok(item.ToDto());
// })
// .WithName("GetBlip");


// GET /blips?userId=...&pageSize=20&continuation   Token=...
group.MapGet("/", async (
    string userId,
    int pageSize,
    string? continuationToken,
    IBlipsRepository repo,
    IPersonRepository personRepo,
    IDistributedCache cache,
    IOptions<RedisOptions> cacheOptions,
    CancellationToken ct) =>
{
    pageSize = pageSize <= 0 ? 20 : Math.Min(pageSize, 100);

    var options = new JsonSerializerOptions(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    string cacheKey = $"tl:home:{userId}";

    try
    {
        var cachedJson = await cache.GetStringAsync(cacheKey, ct);
        if (!string.IsNullOrWhiteSpace(cachedJson))
        {
            var cached = JsonSerializer.Deserialize<ListBlipsResponse>(cachedJson, options);
            if (cached?.Items is { } itemsFromCache)
            {
                return Results.Ok(new { items = itemsFromCache, continuationToken = cached.ContinuationToken, ru = 0.0 });
            }
        }
    }
    catch { /* fall back to DB */ }

    var (following, followingRu) = await personRepo.ListFollowingIdsAsync(userId, ct);
    if (following.Count == 0)
    {
        var emptyResponse = new ListBlipsResponse(Array.Empty<BlipDto>(), null, followingRu);

        try
        {
            var ttl = TimeSpan.FromSeconds(Math.Max(5, cacheOptions.Value.FeedTtlSeconds));
            await cache.SetStringAsync(
                cacheKey,
                JsonSerializer.Serialize(emptyResponse, options),
                new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = ttl },
                ct);
        }
        catch { /* ignore */ }

        return Results.Ok(new { items = emptyResponse.Items, continuationToken = emptyResponse.ContinuationToken, ru = emptyResponse.Ru });
    }

    var (items, token, ru) = await repo.ListAsync(following, pageSize, continuationToken, ct);
    var dtoItems = items.Select(i => i.ToDto()).ToList();
    var response = new ListBlipsResponse(dtoItems, token, ru + followingRu);

    try
    {
        var ttl = TimeSpan.FromSeconds(Math.Max(5, cacheOptions.Value.FeedTtlSeconds));
        await cache.SetStringAsync(
            cacheKey,
            JsonSerializer.Serialize(response, options),
            new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = ttl },
            ct);
    }
    catch { /* ignore */ }

    return Results.Ok(new { items = response.Items, continuationToken = response.ContinuationToken, ru = response.Ru });
});


// run
app.Run();


public sealed record ListBlipsResponse(
    [property: JsonPropertyName("items")] IReadOnlyList<BlipDto> Items,
    [property: JsonPropertyName("continuationToken")] string? ContinuationToken,
    [property: JsonPropertyName("ru")] double Ru
);