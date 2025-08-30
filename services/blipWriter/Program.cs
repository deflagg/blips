using System.Globalization; // RU formatting
using Microsoft.Azure.Cosmos;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.OpenApi.Models;
using BlipWriter.Contracts;
using BlipWriter.Infrastructure;
using BlipWriter.Models;
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

// ---------- Options + CosmosClient (singleton) ----------
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

// POST /blips
group.MapPost("/", async Task<Results<Created<BlipDto>, ValidationProblem>> (
    CreateBlipRequest req,
    IBlipsRepository repo,
    HttpResponse res,
    CancellationToken ct) =>
{
    var text = (req.Text ?? string.Empty).Trim();

    if (string.IsNullOrWhiteSpace(req.UserId) || text.Length is 0 or > 280)
    {
        return TypedResults.ValidationProblem(new Dictionary<string, string[]>
        {
            ["userId/text"] = ["UserId is required; Text must be 1..280 characters."]
        });
    }

    var blip = new Blip { userId = req.UserId, text = text };

    // RU: changed to capture RU from repository
    var (saved, etag, ru) = await repo.CreateAsync(blip, ct);

    // Set ETag on the response
    var headers = res.GetTypedHeaders();
    headers.ETag = EntityTagHeaderValue.Parse(etag); // etag already quoted

    // RU: add RU header
    res.Headers.Append("x-ms-request-charge", ru.ToString("0.###", CultureInfo.InvariantCulture));

    var dto = saved.ToDto();
    return TypedResults.Created($"/blips/{dto.Id}?userId={dto.UserId}", dto);
})
.Produces<BlipDto>(StatusCodes.Status201Created)
.ProducesProblem(StatusCodes.Status400BadRequest)
.WithName("CreateBlip");


// PUT /blips/{id}?userId=...   (optimistic concurrency with If-Match)
group.MapPut("/{id}", async Task<Results<Ok<BlipDto>, NotFound, StatusCodeHttpResult, BadRequest>> (
    string id,
    string userId,
    UpdateBlipRequest req,
    IBlipsRepository repo,
    HttpRequest http,
    HttpResponse res, // RU: added to set RU header
    CancellationToken ct) =>
{
    var ifMatch = http.Headers.IfMatch.FirstOrDefault()?.Trim('"');
    if (string.IsNullOrWhiteSpace(ifMatch))
        return TypedResults.BadRequest();

    var existing = await repo.GetAsync(id, userId, ct);
    if (existing is null) return TypedResults.NotFound();

    // Update the existing blip
    var blip = existing.Value.Item;
    blip.text = (req.Text ?? string.Empty).Trim();

    // RU: capture RU from repository
    var updated = await repo.UpdateAsync(blip, ifMatch!, ct);
    if (updated is null)
    {
        // ETag mismatch -> 412 Precondition Failed
        return TypedResults.StatusCode(StatusCodes.Status412PreconditionFailed);
    }

    // RU: add RU header
    res.Headers.Append("x-ms-request-charge", updated.Value.RU.ToString("0.###", CultureInfo.InvariantCulture));

    return TypedResults.Ok(updated.Value.Item.ToDto());
})
.WithName("UpdateBlip");


app.Run();
