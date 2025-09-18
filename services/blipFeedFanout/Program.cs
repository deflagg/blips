using blipFeedFanout;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Azure.Identity;
using Gremlin.Net.Driver;
using Gremlin.Net.Structure.IO.GraphSON;
using Azure.Messaging.EventHubs.Consumer;
using Azure.Messaging.EventHubs;
using StackExchange.Redis;

// your existing namespaces
using BlipFeedFanout.Infrastructure;

var builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings
{
    ContentRootPath = AppContext.BaseDirectory,  // <— key line
    Args = args
});

builder.Services.AddHostedService<Worker>();

// ---------- Gremlin ----------
builder.Services.Configure<GremlinOptions>(builder.Configuration.GetSection("PersonGraphDB"));

builder.Services.AddSingleton<GremlinClient>(sp =>
{
    var s = sp.GetRequiredService<IOptions<GremlinOptions>>().Value;
    var username = $"/dbs/{s.Common.DatabaseId}/colls/{s.Common.GraphId}";

    if (s.Mode == GremlinMode.Emulator)
    {
        var emu = s.Emulator!;
        var server = new GremlinServer(
            hostname: emu.Host,
            port: emu.Port,
            enableSsl: false,
            username: username,
            password: emu.AuthKey
        );
        return new GremlinClient(server, new GraphSON2MessageSerializer());
    }
    else
    {
        var token = new DefaultAzureCredential().GetToken(
            new Azure.Core.TokenRequestContext(new[] { "https://cosmos.azure.com/.default" })
        ).Token;

        var server = new GremlinServer(
            $"{s.Cloud!.AccountName}.gremlin.cosmos.azure.com",
            443,
            enableSsl: true,
            username: username,
            password: token
        );

        return new GremlinClient(server, new GraphSON2MessageSerializer());
    }
});

// ---------- Redis (IDistributedCache + native ops via multiplexer) ----------
builder.Services.Configure<RedisOptions>(builder.Configuration.GetSection("BlipsCache"));

var cacheCfg = builder.Configuration.GetSection("BlipsCache").Get<RedisOptions>() ?? new();
if (cacheCfg.Enabled && !string.IsNullOrWhiteSpace(cacheCfg.ConnectionString))
{
    builder.Services.AddStackExchangeRedisCache(o =>
    {
        o.Configuration = cacheCfg.ConnectionString;
        o.InstanceName = cacheCfg.InstanceName;
    });

    // Native Redis ops (sorted sets, etc.)
    builder.Services.AddSingleton<IConnectionMultiplexer>(_ =>
        ConnectionMultiplexer.Connect(cacheCfg.ConnectionString));
}
else
{
    builder.Services.AddDistributedMemoryCache();
    // No IConnectionMultiplexer registered -> worker will log and skip Redis fanout
}

// Optional: your people repo
builder.Services.AddSingleton<IPersonRepository>(sp =>
    new PersonRepository(sp.GetRequiredService<GremlinClient>()));

// ---------- Event Hubs (consumer) ----------
builder.Services.Configure<EventHubsOptions>(builder.Configuration.GetSection("EventHubs"));
builder.Services.Configure<TimelineOptions>(builder.Configuration.GetSection("Timeline"));

builder.Services.AddSingleton<EventHubConsumerClient>(sp =>
{
    var opts = sp.GetRequiredService<IOptions<EventHubsOptions>>().Value;
    if (!opts.Enabled || string.IsNullOrWhiteSpace(opts.ConnectionString) || string.IsNullOrWhiteSpace(opts.EventHubName))
        throw new InvalidOperationException("Event Hubs is disabled or not configured (ConnectionString/EventHubName).");

    var group = string.IsNullOrWhiteSpace(opts.ConsumerGroup)
        ? EventHubConsumerClient.DefaultConsumerGroupName
        : opts.ConsumerGroup!;

    return new EventHubConsumerClient(group, opts.ConnectionString!, opts.EventHubName);
});

var host = builder.Build();
host.Run();


// ---------- Options (define here if you don't have shared types) ----------
namespace blipFeedFanout
{
    public sealed class TimelineOptions
    {
        public int MaxItems { get; set; } = 1000;             // trim after fanout
    }
}
