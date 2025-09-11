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
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "UserAdmin API", Version = "v1" });
});

// ---------- Options  CosmosClient (singleton) ----------
builder.Services.Configure<CosmosOptions>(builder.Configuration.GetSection("Cosmos"));

builder.Services.AddSingleton<CosmosClient>(sp =>
{
    var opt = sp.GetRequiredService<IOptions<CosmosOptions>>().Value;

    // Allow quick override to force IPv4 if needed (helps on some stacks)
    var endpoint = opt.Endpoint;
    

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

        return new CosmosClient(endpoint, opt.Key, clientOptions);
    }
    
    return new CosmosClient(endpoint, new DefaultAzureCredential(), clientOptions);
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
builder.Services.AddSingleton<IAccountsRepository, AccountsRepository>();
builder.Services.AddSingleton<ICosmosInitializer, CosmosInitializer>();
builder.Services.AddSingleton<IPersonRepository>(sp =>
    new PersonRepository(
        sp.GetRequiredService<GremlinClient>(),
        maintainReverseEdge: true,
        partitionKeyPropertyName: "personId"   // matches Person model property name
    )
);

var app = builder.Build();

app.Logger.LogInformation("ENV={Env}", app.Environment.EnvironmentName);

app.UseCors("AllowAll");

await app.Services.GetRequiredService<ICosmosInitializer>().InitializeAsync();
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

// Create (or upsert) a user
accounts.MapPost("/", async (
    IAccountsRepository accounts,
    IPersonRepository persons,
    HttpContext http,
    AccountCreateDto dto) =>
{
    var now = DateTimeOffset.UtcNow;
    double ru = 0d;

    // Optional: short-circuit if the account already exists (treat as conflict)
    // create id and accountid
    var id = Guid.NewGuid().ToString();
    var accountId = Guid.NewGuid().ToString();

    // 1) Create the Account (source of record)
    var account = new Account
    {
        Id = id,
        AccountId = accountId,
        Name = dto.Name,
        Email = dto.Email,
        CreatedAt = now,
        UpdatedAt = now
    };

    (Account createdAcc, string accEtag, double ruAcc) =
        await accounts.CreateAsync(account, http.RequestAborted);
    ru += ruAcc;

    try
    {
        // 2) Create/Upsert the Person mirror
        var personId = Guid.NewGuid().ToString();
        
        var person = new Person
        {
            Id = id, 
            AccountId = accountId,
            PersonId = personId,
            Name = dto.Name,
            Email = dto.Email,
            CreatedAt = now,
            UpdatedAt = now
        };

        (Person createdPerson, double ruPerson) =
            await persons.UpsertPersonAsync(person, http.RequestAborted);
        ru += ruPerson;

        SetRu(http.Response, ru);
        return Results.Created($"/users/{createdAcc.AccountId}", new
        {
            account = createdAcc,
            person = createdPerson
        });
    }
    catch (Exception ex)
    {
        // Compensate: remove the account we just created to avoid drift
        var (deleted, ruDel) = await accounts.DeleteAsync(account.Id, account.AccountId, accEtag, http.RequestAborted);
        ru += ruDel;

        SetRu(http.Response, ru);
        return Results.Problem(
            detail: ex.Message,
            statusCode: StatusCodes.Status500InternalServerError);
    }
});

// Update a person (idempotent upsert)
accounts.MapPut("/{id}", async (IPersonRepository repo, HttpContext http, string personId, string id, AccountUpdateDto dto) =>
{
    var now = DateTimeOffset.UtcNow;

    (Person? existing, double ru0) = await repo.GetPersonAsync(id, http.RequestAborted);

    var user = existing is null
        ? new Person {
            Id = id,
            AccountId = dto.AccountId,
            PersonId = personId,
            Name = dto.Name,
            Email = dto.Email,
            CreatedAt = now,
            UpdatedAt = now
        }
        : new Person {
            Id = id,
            AccountId = dto.AccountId,
            PersonId = personId,
            Name = dto.Name ?? existing.Name,
            Email = dto.Email,
            CreatedAt = existing.CreatedAt,
            UpdatedAt = now
        };

    (Person updated, double ru1) = await repo.UpsertPersonAsync(user, http.RequestAborted);
    SetRu(http.Response, ru0 + ru1);
    return Results.Ok(updated);
});

// Get person by id
accounts.MapGet("/{id}", async (IPersonRepository repo, HttpContext http, string id) =>
{
    (Person? user, double ru) = await repo.GetPersonAsync(id, http.RequestAborted);
    SetRu(http.Response, ru);
    return user is null ? Results.NotFound() : Results.Ok(user);
});

// Delete person
accounts.MapDelete("/{id}", async (IPersonRepository repo, HttpContext http, string id) =>
{
    (bool deleted, double ru) = await repo.DeletePersonAsync(id, http.RequestAborted);
    SetRu(http.Response, ru);
    return deleted ? Results.NoContent() : Results.NotFound();
});

// ----- Follow mechanics -----

// Follow
accounts.MapPost("/{id}/follow/{targetId}", async (IPersonRepository repo, HttpContext http, string id, string targetId) =>
{
    if (string.Equals(id, targetId, StringComparison.Ordinal))
        return Results.BadRequest(new { error = "Person cannot follow themself." });

    (bool ok, double ru) = await repo.FollowAsync(id, targetId, http.RequestAborted);
    SetRu(http.Response, ru);
    return ok ? Results.NoContent() : Results.Problem("Follow failed.");
});

// Unfollow
accounts.MapDelete("/{id}/follow/{targetId}", async (IPersonRepository repo, HttpContext http, string id, string targetId) =>
{
    (bool ok, double ru) = await repo.UnfollowAsync(id, targetId, http.RequestAborted);
    SetRu(http.Response, ru);
    return ok ? Results.NoContent() : Results.NotFound();
});

// Is following?
accounts.MapGet("/{id}/following/{targetId}", async (IPersonRepository repo, HttpContext http, string id, string targetId) =>
{
    (bool following, double ru) = await repo.IsFollowingAsync(id, targetId, http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(new FollowStateDto(following));
});

// ----- Lists & counts -----

// Following list
accounts.MapGet("/{id}/following", async (IPersonRepository repo, HttpContext http, string id, int skip = 0, int take = 50) =>
{
    (IReadOnlyList<Person> list, double ru) =
        await repo.GetFollowingAsync(id, Math.Max(0, skip), Math.Clamp(take, 1, 200), http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(list);
});

// Followers list
accounts.MapGet("/{id}/followers", async (IPersonRepository repo, HttpContext http, string id, int skip = 0, int take = 50) =>
{
    (IReadOnlyList<Person> list, double ru) =
        await repo.GetFollowersAsync(id, Math.Max(0, skip), Math.Clamp(take, 1, 200), http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(list);
});

// Following count
accounts.MapGet("/{id}/following/count", async (IPersonRepository repo, HttpContext http, string id) =>
{
    (long count, double ru) = await repo.CountFollowingAsync(id, http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(new CountDto(count));
});

// Followers count
accounts.MapGet("/{id}/followers/count", async (IPersonRepository repo, HttpContext http, string id) =>
{
    (long count, double ru) = await repo.CountFollowersAsync(id, http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(new CountDto(count));
});

// Suggestions (people you may know)
accounts.MapGet("/{id}/suggestions", async (IPersonRepository repo, HttpContext http, string id, int limit = 20) =>
{
    (IReadOnlyList<(Person user, long mutuals)> suggestions, double ru) =
        await repo.SuggestToFollowAsync(id, Math.Clamp(limit, 1, 100), http.RequestAborted);
    SetRu(http.Response, ru);

    // map to DTO if you want a stable contract
    var dto = suggestions.Select(s => new SuggestionDto(s.user, s.mutuals)).ToList();
    return Results.Ok(dto);
});

// Mutual followees between two users (who both A and B follow)
accounts.MapGet("/{id}/mutuals/{otherId}", async (IPersonRepository repo, HttpContext http, string id, string otherId, int limit = 50) =>
{
    (IReadOnlyList<Person> list, double ru) =
        await repo.MutualFollowsAsync(id, otherId, Math.Clamp(limit, 1, 200), http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(list);
});

// Utility: followee ids (to join with your Blips repo for timelines)
accounts.MapGet("/{id}/followee-ids", async (IPersonRepository repo, HttpContext http, string id, int max = 500) =>
{
    (IReadOnlyList<string> ids, double ru) =
        await repo.GetFolloweeIdsAsync(id, Math.Clamp(max, 1, 2000), http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(ids);
});



app.Run();