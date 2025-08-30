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

// ---------- Options + CosmosClient (singleton) ---------
builder.Services.Configure<CosmosOptions>(builder.Configuration.GetSection("Cosmos"));

builder.Services.AddSingleton<CosmosClient>(sp =>
{
    var opt = sp.GetRequiredService<IOptions<CosmosOptions>>().Value;

    // Allow quick override to force IPv4 if needed (helps on some stacks)
    var endpoint = Environment.GetEnvironmentVariable("COSMOS_ENDPOINT") ?? opt.Endpoint;
    //var key = Environment.GetEnvironmentVariable("COSMOS_KEY") ?? opt.Key;

    var clientOptions = new CosmosClientOptions
    {
        ApplicationName = "Vibe.Blips",
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
    }

    //return new CosmosClient(endpoint, key, clientOptions);
    return new CosmosClient(endpoint, new DefaultAzureCredential(), clientOptions);
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


// GET /blips?userId=...&pageSize=20&continuationToken=...
group.MapGet("/", async (
    string userId,
    int pageSize,
    string? continuationToken,
    IBlipsRepository repo,
    CancellationToken ct) =>
{
    pageSize = pageSize <= 0 ? 20 : Math.Min(pageSize, 100);

    // RU: capture RU from repository
    var (items, token, ru) = await repo.ListAsync(userId, pageSize, continuationToken, ct);

    // RU: include ru in payload
    return Results.Ok(new
    {
        items = items.Select(i => i.ToDto()),
        continuationToken = token,
        ru
    });
})
.Produces(StatusCodes.Status200OK)
.WithName("ListBlips");

// run
app.Run();
