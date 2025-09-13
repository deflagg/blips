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
builder.Services.AddSingleton<IPersonRepository>(sp =>new PersonRepository(sp.GetRequiredService<GremlinClient>()));

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


// Seed Data
app.MapGet("/initializeData", async (
    IAccountsRepository accountsRepo,
    IPersonRepository personsRepo,
    HttpContext http,
    int users = 10,             // how many to create (<= usernames count)
    int? seed = null,            // RNG seed for reproducibility
    double avgFollows = 1,      // target average out-degree
    double homophilyBoost = 1.8, // multiplier if interests overlap
    double influencerBoost = 4.0,// multiplier for influencers being chosen
    double triadicProb = 0.12,   // probability to add triadic-closure edges
    double reciprocityProb = 0.28,// base reciprocity probability
    double noiseFollowProb = 0.02,// small chance to follow a random user
    CancellationToken ct = default) =>
{
    // -----------------------------
    // 1) Seed users with attributes
    // -----------------------------
    var usernames = new[]
    {
        "acorn","alpenglow","amber","ash","aurora","banyan","bayou","bramble","brook","buttercup",
        "canto","cascade","cedar","clover","coral","cypress","dawn","dewdrop","dovetail","driftwood",
        "elm","ember","evergreen","fern","fjord","flint","foxglove","gale","glacier","gossamer",
        "grove","harbor","harvest","heather","horizon","indigo","iris","isla","jade","jasmine",
        "junco","juniper","kelp","kestrel","kite","koa","lagoon","laurel","lilac","lumen",
        "marigold","mesa","mistral","moonstone","nectar","nimbus","nori","nova","oak","ochre",
        "onyx","opal","pebble","peony","poppy","prairie","quartz","quasar","quill","quince",
        "reed","river","rosemary","rune","sage","sable","solstice","spruce","thatch","thistle",
        "tamarind","tundra","umbra","umber","upland","urn","vale","vernal","verve","violet",
        "wadi","willow","wren","xanadu","xenia","xylem","yarrow","yonder","yosemite","zephyr"
    };

    users = Math.Clamp(users, 2, usernames.Length);
    var rng = seed.HasValue ? new Random(seed.Value) : new Random();

    // Some broad interest buckets for homophily
    var interests = new[]
    {
        "tech","sports","music","movies","gaming","art","science","finance","health","travel",
        "food","nature","politics","crypto","fashion","photography"
    };

    // Light influencer/bot priors
    double influencerRate = 0.005; // ~1% influencers
    double botRate = 0.00; // ~8% bots

    var chosen = usernames.Take(users).ToArray();

    var createdPersons = new List<Person>(users);
    foreach (var u in chosen)
    {
        var person = new Person
        {
            PersonId = u,
            AccountId = u,
            Name = u,
            Email = $"{u}@example.com"
        };
        var (upserted, _) = await personsRepo.UpsertPersonAsync(person, ct);
        createdPersons.Add(upserted);
    }

    // Build indices and per-user metadata
    var indexOf = createdPersons
        .Select((p, i) => (p.PersonId, i))
        .ToDictionary(t => t.PersonId, t => t.i);

    var n = createdPersons.Count;
    var meta = new UserMeta[n];
    for (int i = 0; i < n; i++)
    {
        var i1 = interests[rng.Next(interests.Length)];
        var i2 = interests[rng.Next(interests.Length)];
        while (i2 == i1) i2 = interests[rng.Next(interests.Length)];

        meta[i] = new UserMeta
        {
            IsInfluencer = rng.NextDouble() < influencerRate,
            IsBot = rng.NextDouble() < botRate,
            Interests = new HashSet<string>(new[] { i1, i2 })
        };
    }

    // -----------------------------------------------
    // 2) Generate realistic follow edges (the fun part)
    // -----------------------------------------------
    // We keep a local adjacency for uniqueness & weighting
    var outAdj = new HashSet<int>[n];
    var inDeg = new int[n]; // in-degree drives "popularity"
    for (int i = 0; i < n; i++) outAdj[i] = new HashSet<int>();

    // Heavy-tailed out-degree using log-normal around avgFollows
    int MaxOutPerUser() => Math.Min(n - 1, Math.Max(1, (int)Math.Round(avgFollows * 3.5)));
    int SampleOut()
    {
        // Log-normal with sigma=1.0, mean approx avgFollows
        double sigma = 1.0;
        double mu = Math.Log(Math.Max(1.0, avgFollows)) - 0.5 * sigma * sigma;
        double u1 = 1.0 - rng.NextDouble();
        double u2 = 1.0 - rng.NextDouble();
        double z = Math.Sqrt(-2.0 * Math.Log(u1)) * Math.Cos(2.0 * Math.PI * u2);
        double val = Math.Exp(mu + sigma * z);
        int k = (int)Math.Round(val);
        return Math.Clamp(k, 1, MaxOutPerUser());
    }

    double WeightForTarget(int src, int dst)
    {
        if (src == dst) return 0;
        // Popularity via in-degree (preferential attachment) + 1 for nonzero base
        double w = 1.0 + inDeg[dst];

        // Homophily: bump if shared interests
        if (meta[src].Interests.Overlaps(meta[dst].Interests))
            w *= homophilyBoost;

        // Influencers are attractive to follow
        if (meta[dst].IsInfluencer)
            w *= influencerBoost;

        // Bots are less attractive to follow
        if (meta[dst].IsBot)
            w *= 0.7;

        return w;
    }

    bool TryPickTarget(int src, out int picked, HashSet<int>? banned = null)
    {
        // Build a one-pass weighted sampler across all candidates
        double total = 0;
        picked = -1;
        double r = rng.NextDouble();

        for (int j = 0; j < n; j++)
        {
            if (j == src) continue;
            if (outAdj[src].Contains(j)) continue;
            if (banned != null && banned.Contains(j)) continue;

            double w = WeightForTarget(src, j);
            if (w <= 0) continue;

            total += w;
            // Reservoir-like weighted pick
            if (rng.NextDouble() < w / total)
                picked = j;
        }

        return picked >= 0;
    }

    // Initial follows per user
    var newEdges = new List<(int u, int v)>(n * 8);

    for (int u = 0; u < n; u++)
    {
        int desired = SampleOut();
        int guard = 0, maxGuard = desired * 8 + 64; // avoid infinite loops
        while (outAdj[u].Count < desired && guard++ < maxGuard)
        {
            // Mostly weighted picks, with small chance of pure random noise
            int v;
            if (rng.NextDouble() < noiseFollowProb)
            {
                v = rng.Next(n);
                if (v == u || outAdj[u].Contains(v)) continue;
            }
            else
            {
                if (!TryPickTarget(u, out v)) break;
            }

            outAdj[u].Add(v);
            inDeg[v]++;
            newEdges.Add((u, v));
        }
    }

    // Triadic closure: follow friends-of-friends
    int triadicAdded = 0;
    for (int u = 0; u < n; u++)
    {
        // Collect candidates two steps away
        var fofs = new HashSet<int>();
        foreach (var v in outAdj[u])
            foreach (var w in outAdj[v])
                if (w != u && !outAdj[u].Contains(w))
                    fofs.Add(w);

        foreach (var w in fofs)
        {
            if (rng.NextDouble() > triadicProb) continue;
            // optionally prefer weighted triadic picks (ban none, but keep a one-off pick probability)
            if (outAdj[u].Contains(w)) continue;

            outAdj[u].Add(w);
            inDeg[w]++;
            newEdges.Add((u, w));
            triadicAdded++;
        }
    }

    // Reciprocity: some edges get followed back (lower for influencers)
    int reciprocalAdded = 0;
    foreach (var (u, v) in newEdges.ToArray())
    {
        if (outAdj[v].Contains(u)) continue;
        double p = reciprocityProb;
        if (meta[u].IsInfluencer) p *= 0.6; // influencers less likely to follow back
        if (meta[v].IsInfluencer) p *= 0.6;

        if (rng.NextDouble() < p)
        {
            outAdj[v].Add(u);
            inDeg[u]++;
            newEdges.Add((v, u));
            reciprocalAdded++;
        }
    }

    // --------------------------------
    // 3) Persist follows via repository
    // --------------------------------
    var ids = createdPersons.Select(p => p.PersonId).ToArray();

    foreach (var (u, v) in newEdges)
    {
        await personsRepo.FollowAsync(ids[u], ids[v], ct);
    }

    // ---------------
    // 4) Basic metrics
    // ---------------
    // Edge set for reciprocity measurement
    var edgeSet = new HashSet<long>(newEdges.Count);
    static long Key(int a, int b) => ((long)a << 32) | (uint)b;
    foreach (var (u, v) in newEdges) edgeSet.Add(Key(u, v));

    int E = edgeSet.Count;
    int mutual = 0;
    foreach (var (u, v) in newEdges)
        if (edgeSet.Contains(Key(v, u))) mutual++;

    // Each mutual pair counted twice above; normalize
    double reciprocityRate = (mutual / 2.0) / E;

    // Top hubs by followers
    var topHubs = Enumerable.Range(0, n)
        .OrderByDescending(i => inDeg[i])
        .Take(Math.Min(10, n))
        .Select(i => new { user = ids[i], followers = inDeg[i], influencer = meta[i].IsInfluencer })
        .ToArray();

    // Gini coefficient over follower counts (0 = equal, 1 = extremely unequal)
    double Gini(int[] arr)
    {
        if (arr.Length == 0) return 0;
        var sorted = arr.Select(x => (double)x).OrderBy(x => x).ToArray();
        double cum = 0, sum = sorted.Sum(), g = 0;
        for (int i = 0; i < sorted.Length; i++)
        {
            cum += sorted[i];
            g += cum - sorted[i] / 2.0;
        }
        // Lorenz-based formula
        // G = 1 - 2 * (area under Lorenz curve)
        double lorenz = g / (sorted.Length * sum);
        return Math.Round(1 - 2 * lorenz, 4);
    }

    var stats = new
    {
        users = n,
        edges = E,
        avgOut = Math.Round(E / (double)n, 2),
        avgIn = Math.Round(E / (double)n, 2),
        triadicAdded,
        reciprocalAdded,
        reciprocity = Math.Round(reciprocityRate, 3),
        giniFollowers = Gini(inDeg),
        influencers = Enumerable.Range(0, n).Where(i => meta[i].IsInfluencer)
            .Select(i => ids[i]).Take(12).ToArray(),
        bots = Enumerable.Range(0, n).Where(i => meta[i].IsBot)
            .Select(i => ids[i]).Take(12).ToArray(),
        topHubs
    };

    return Results.Ok(new
    {
        message = $"Initialized {n} persons and {E} follow edges (incl. triadic + reciprocity).",
        stats
    });
})
.WithTags("Init");

// ----- Graph Admin -----
app.MapDelete("/DeleteGraph", async (
    IAccountsRepository accountsRepo,
    IPersonRepository personsRepo,
    HttpContext http,
    CancellationToken ct = default) =>
{
    var ru = await personsRepo.DeleteGraphAsync(http.RequestAborted);
    SetRu(http.Response, ru);
    return Results.Ok(new { deleted = "all", ru });

})
.WithTags("Graph");


// ----- Graph -----
app.MapGet("/graph", async (IPersonRepository repo, HttpContext http, int vertexLimit = 2000, int edgeLimit = 10000) =>
{
    var (persons, edges, ru) = await repo.GetGraphAsync(vertexLimit, edgeLimit, http.RequestAborted);

    // RU header (matches the pattern already used elsewhere)
    SetRu(http.Response, ru);

    // Shape for the front-end graph
    var payload = new
    {
        nodes = persons.Select(p => new {
            id        = p.PersonId,      // unique id for the graph
            label     = p.Name,          // display name
            accountId = p.AccountId,
            email     = p.Email
        }),
        edges = edges.Select(e => new {
            source    = e.source,        // from personId
            target    = e.target,        // to personId
            createdAt = e.createdAt
        })
    };

    return Results.Ok(payload);
})
.WithTags("Graph");


app.Run();