using System.Globalization; // RU formatting
using Microsoft.Azure.Cosmos;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.OpenApi.Models;
using UserAdmin.Contracts;
using UserAdmin.Infrastructure;
using UserAdmin.Models;
using Microsoft.Net.Http.Headers;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Azure.Identity;
using Gremlin.Net.Driver;
using Azure.ResourceManager.CosmosDB;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseKestrel((context, options) =>
{
    options.Configure(context.Configuration.GetSection("Kestrel"));
});

// ---------- Swagger ----------
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "UserAdmin API", Version = "v1" });
});

// ---------- Options  CosmosClient (singleton) ----------
builder.Services.Configure<CosmosOptions>(builder.Configuration.GetSection("Cosmos"));

builder.Services.AddSingleton<CosmosClient>(sp =>
{
    var opt = sp.GetRequiredService<IOptions<CosmosOptions>>().Value;

    // Allow quick override to force IPv4 if needed (helps on some stacks)
    var endpoint = opt.Endpoint;
    //var key = Environment.GetEnvironmentVariable("COSMOS_KEY") ?? opt.Key;

    var clientOptions = new CosmosClientOptions
    {
        ApplicationName = "Blips.UserAdmin",
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

// ---------- Options  GremlinClient (singleton) ----------
builder.Services.Configure<GremlinOptions>(builder.Configuration.GetSection("UserGraphDB"));

builder.Services.AddSingleton<GremlinClient>(sp =>
{
    var o = sp.GetRequiredService<IOptions<GremlinOptions>>().Value;

    // No client ID in code — Workload Identity env vars are injected into the pod
    var cred = new Azure.Identity.DefaultAzureCredential();
    var arm = new Azure.ResourceManager.ArmClient(cred);
    var id = CosmosDBAccountResource.CreateResourceIdentifier(o.SubscriptionId, o.ResourceGroup, o.AccountName);
    var acct = arm.GetCosmosDBAccountResource(id);

    var keys = acct.GetKeysAsync().GetAwaiter().GetResult(); // or GetReadOnlyKeysAsync()
    var key = keys.Value.PrimaryMasterKey;

    var server = new Gremlin.Net.Driver.GremlinServer(
        $"{o.AccountName}.gremlin.cosmos.azure.com",
        443,
        enableSsl: true,
        username: $"/dbs/{o.DatabaseId}/colls/{o.GraphId}",
        password: key);

    return new Gremlin.Net.Driver.GremlinClient(server, new Gremlin.Net.Structure.IO.GraphSON.GraphSON2MessageSerializer());
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
builder.Services.AddSingleton<IUsersGraphRepository>(sp =>
    new UsersRepository(
        sp.GetRequiredService<GremlinClient>(),
        maintainReverseEdge: true // keep fast followers
    )
);

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


// ---------- Users endpoints ----------
var users = group.MapGroup("/users").WithTags("Users");

// tiny helper to surface RU like your Core API endpoints do
static void SetRu(HttpResponse res, double ru) =>
    res.Headers["x-ms-request-charge"] = ru.ToString("0.###", CultureInfo.InvariantCulture);

// DTOs
public sealed record UserCreateDto(string Id, string DisplayName, string? Email);
public sealed record UserUpdateDto(string DisplayName, string? Email);
public sealed record FollowStateDto(bool Following);
public sealed record CountDto(long Count);
public sealed record SuggestionDto(User User, long Mutuals);

// Create (or upsert) a user
users.MapPost("/", async (IUsersGraphRepository repo, HttpContext http, UserCreateDto dto) =>
{
    var now = DateTimeOffset.UtcNow;
    var user = new User(dto.Id, dto.DisplayName, dto.Email, now, now);

    var (created, ru) = await repo.UpsertUserAsync(user, http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Created($"/useradmin/users/{created.Id}", created);
});

// Update a user (idempotent upsert)
users.MapPut("/{id}", async (IUsersGraphRepository repo, HttpContext http, string id, UserUpdateDto dto) =>
{
    var now = DateTimeOffset.UtcNow;
    var (existing, ru0) = await repo.GetUserAsync(id, http.RequestAborted);

    var user = existing is null
        ? new User(id, dto.DisplayName, dto.Email, now, now)
        : new User(id,
                   dto.DisplayName ?? existing.DisplayName,
                   dto.Email,
                   existing.CreatedAt,
                   now);

    var (updated, ru1) = await repo.UpsertUserAsync(user, http.RequestAborted);
    SetRu(http.Response, ru0 + ru1);
    return Results.Ok(updated);
});

// Get user by id
users.MapGet("/{id}", async (IUsersGraphRepository repo, HttpContext http, string id) =>
{
    var (user, ru) = await repo.GetUserAsync(id, http.RequestAborted);
    SetRu(http.Response, ru);
    return user is null ? Results.NotFound() : Results.Ok(user);
});

// Delete user
users.MapDelete("/{id}", async (IUsersGraphRepository repo, HttpContext http, string id) =>
{
    var (deleted, ru) = await repo.DeleteUserAsync(id, http.RequestAborted);
    SetRu(http.Response, ru);
    return deleted ? Results.NoContent() : Results.NotFound();
});

// ----- Follow mechanics -----

// Follow
users.MapPost("/{id}/follow/{targetId}", async (IUsersGraphRepository repo, HttpContext http, string id, string targetId) =>
{
    if (string.Equals(id, targetId, StringComparison.Ordinal))
        return Results.BadRequest(new { error = "User cannot follow themself." });

    var (ok, ru) = await repo.FollowAsync(id, targetId, http.RequestAborted);
    SetRu(http.Response, ru);
    return ok ? Results.NoContent() : Results.Problem("Follow failed.");
});

// Unfollow
users.MapDelete("/{id}/follow/{targetId}", async (IUsersGraphRepository repo, HttpContext http, string id, string targetId) =>
{
    var (ok, ru) = await repo.UnfollowAsync(id, targetId, http.RequestAborted);
    SetRu(http.Response, ru);
    return ok ? Results.NoContent() : Results.NotFound();
});

// Is following?
users.MapGet("/{id}/following/{targetId}", async (IUsersGraphRepository repo, HttpContext http, string id, string targetId) =>
{
    var (following, ru) = await repo.IsFollowingAsync(id, targetId, http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(new FollowStateDto(following));
});

// ----- Lists & counts -----

// Following list
users.MapGet("/{id}/following", async (IUsersGraphRepository repo, HttpContext http, string id, int skip = 0, int take = 50) =>
{
    var (list, ru) = await repo.GetFollowingAsync(id, Math.Max(0, skip), Math.Clamp(take, 1, 200), http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(list);
});

// Followers list
users.MapGet("/{id}/followers", async (IUsersGraphRepository repo, HttpContext http, string id, int skip = 0, int take = 50) =>
{
    var (list, ru) = await repo.GetFollowersAsync(id, Math.Max(0, skip), Math.Clamp(take, 1, 200), http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(list);
});

// Following count
users.MapGet("/{id}/following/count", async (IUsersGraphRepository repo, HttpContext http, string id) =>
{
    var (count, ru) = await repo.CountFollowingAsync(id, http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(new CountDto(count));
});

// Followers count
users.MapGet("/{id}/followers/count", async (IUsersGraphRepository repo, HttpContext http, string id) =>
{
    var (count, ru) = await repo.CountFollowersAsync(id, http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(new CountDto(count));
});

// Suggestions (people you may know)
users.MapGet("/{id}/suggestions", async (IUsersGraphRepository repo, HttpContext http, string id, int limit = 20) =>
{
    var (suggestions, ru) = await repo.SuggestToFollowAsync(id, Math.Clamp(limit, 1, 100), http.RequestAborted);
    SetRu(http.Response, ru);

    // map to DTO if you want a stable contract
    var dto = suggestions.Select(s => new SuggestionDto(s.user, s.mutuals)).ToList();
    return Results.Ok(dto);
});

// Mutual followees between two users (who both A and B follow)
users.MapGet("/{id}/mutuals/{otherId}", async (IUsersGraphRepository repo, HttpContext http, string id, string otherId, int limit = 50) =>
{
    var (list, ru) = await repo.MutualFollowsAsync(id, otherId, Math.Clamp(limit, 1, 200), http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(list);
});

// Utility: followee ids (to join with your Blips repo for timelines)
users.MapGet("/{id}/followee-ids", async (IUsersGraphRepository repo, HttpContext http, string id, int max = 500) =>
{
    var (ids, ru) = await repo.GetFolloweeIdsAsync(id, Math.Clamp(max, 1, 2000), http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(ids);
});



app.Run();
