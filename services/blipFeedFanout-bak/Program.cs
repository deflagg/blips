using System.Globalization; // RU formatting
using Microsoft.Azure.Cosmos;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.OpenApi.Models;
using BlipFeedFanout.Infrastructure;
using BlipFeedFanout.Models;
using Microsoft.Net.Http.Headers;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Azure.Identity;
using Gremlin.Net.Driver;
using Azure.ResourceManager.CosmosDB;
using Gremlin.Net.Structure.IO.GraphSON;


var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseKestrel((context, options) =>
{
    options.Configure(context.Configuration.GetSection("Kestrel"));
});

// ---------- Swagger ----------
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "BlipFeedFanout API", Version = "v1" });
});


// ---------- Options  GremlinClient (singleton) ----------
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
        var o = sp.GetRequiredService<IOptions<GremlinOptions>>().Value;

        // Managed Identity / Service Principal via DefaultAzureCredential
        var cred = new Azure.Identity.DefaultAzureCredential();

        // 1) Get an AAD access token for Cosmos DB data plane
        var token = cred.GetToken(
            new Azure.Core.TokenRequestContext(new[] { "https://cosmos.azure.com/.default" })
        ).Token;

        // 2) Connect with SASL PLAIN: username = resource path, password = AAD token
        var server = new Gremlin.Net.Driver.GremlinServer(
            $"{o.Cloud!.AccountName}.gremlin.cosmos.azure.com",
            443,
            enableSsl: true,
            username: $"/dbs/{o.Common.DatabaseId}/colls/{o.Common.GraphId}",
            password: token
        );

        return new GremlinClient(server, new GraphSON2MessageSerializer());
    }
});

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

// ---------- Event Hubs (producer) ----------
builder.Services.Configure<EventHubsOptions>(builder.Configuration.GetSection("EventHubs"));

builder.Services.AddSingleton<EventHubProducerClient>(sp =>
{
    var opts = sp.GetRequiredService<IOptions<EventHubsOptions>>().Value;
    if (!opts.Enabled || string.IsNullOrWhiteSpace(opts.ConnectionString))
        throw new InvalidOperationException("Event Hubs is disabled or missing ConnectionString.");

    return new EventHubProducerClient(opts.ConnectionString!, opts.EventHubName);
});



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
builder.Services.AddSingleton<IPersonRepository>(sp =>new PersonRepository(sp.GetRequiredService<GremlinClient>()));

var app = builder.Build();

app.Logger.LogInformation("ENV={Env}", app.Environment.EnvironmentName);

app.UseCors("AllowAll");

app.UseSwagger();
app.UseSwaggerUI();


app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = reg => reg.Tags.Contains("live")   // run only the failing check
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = reg => reg.Tags.Contains("ready")  // run only the ready checks
});



// ---------- Users endpoints ----------
var accounts = app.MapGroup("/accounts").WithTags("Accounts");

// tiny helper to surface RU like your Core API endpoints do
static void SetRu(HttpResponse res, double ru) =>
    res.Headers["x-ms-request-charge"] = ru.ToString("0.###", CultureInfo.InvariantCulture);



app.Run();