using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using UserAdmin.Contracts;
using UserAdmin.Infrastructure;
using UserAdmin.Models;

namespace UserAdmin.Services;

public sealed class GraphSeeder
{
    private readonly IAccountsRepository _accountsRepository;
    private readonly IPersonRepository _personRepository;

    private static readonly string[] Usernames =
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

    private static readonly string[] Interests =
    {
        "tech","sports","music","movies","gaming","art","science","finance","health","travel",
        "food","nature","politics","crypto","fashion","photography"
    };

    private const double InfluencerRate = 0.005;
    private const double BotRate = 0.0;

    public GraphSeeder(IAccountsRepository accountsRepository, IPersonRepository personRepository)
    {
        _accountsRepository = accountsRepository ?? throw new ArgumentNullException(nameof(accountsRepository));
        _personRepository = personRepository ?? throw new ArgumentNullException(nameof(personRepository));
    }

    public async Task<GraphSeedResult> SeedAsync(GraphSeedRequest request, CancellationToken cancellationToken = default)
    {
        if (request is null)
        {
            throw new ArgumentNullException(nameof(request));
        }

        var now = DateTimeOffset.UtcNow;
        var totalRequestCharge = 0d;

        var userCount = Math.Clamp(request.Users, 2, Usernames.Length);
        var rng = request.Seed.HasValue ? new Random(request.Seed.Value) : new Random();

        var createdPersons = new List<Person>(userCount);

        foreach (var username in Usernames.Take(userCount))
        {
            var email = $"{username}@example.com";

            var account = new Account
            {
                Id = Guid.NewGuid().ToString(),
                AccountId = Guid.NewGuid().ToString(),
                Name = username,
                Email = email,
                CreatedAt = now,
                UpdatedAt = now
            };

            var (createdAccount, _, accountCharge) = await _accountsRepository.CreateAsync(account, cancellationToken);
            totalRequestCharge += accountCharge;

            var person = new Person
            {
                PersonId = username,
                AccountId = createdAccount.AccountId,
                Name = username,
                Email = email,
                CreatedAt = now,
                UpdatedAt = now
            };

            var (upsertedPerson, personCharge) = await _personRepository.UpsertPersonAsync(person, cancellationToken);
            totalRequestCharge += personCharge;
            createdPersons.Add(upsertedPerson);
        }

        var n = createdPersons.Count;
        if (n == 0)
        {
            var emptyStats = new GraphSeedStats(
                Users: 0,
                AccountsCreated: 0,
                Edges: 0,
                AvgOut: 0,
                AvgIn: 0,
                TriadicAdded: 0,
                ReciprocalAdded: 0,
                Reciprocity: 0,
                GiniFollowers: 0,
                TopHubs: Array.Empty<GraphSeedTopHub>());

            return new GraphSeedResult("No users were created.", emptyStats, totalRequestCharge);
        }

        var metadata = new UserMeta[n];
        for (var i = 0; i < n; i++)
        {
            var firstInterest = Interests[rng.Next(Interests.Length)];
            var secondInterest = Interests[rng.Next(Interests.Length)];
            while (secondInterest == firstInterest)
            {
                secondInterest = Interests[rng.Next(Interests.Length)];
            }

            metadata[i] = new UserMeta(
                rng.NextDouble() < InfluencerRate,
                rng.NextDouble() < BotRate,
                new HashSet<string>(new[] { firstInterest, secondInterest }));
        }

        var outAdjacency = new HashSet<int>[n];
        var inDegree = new int[n];
        for (var i = 0; i < n; i++)
        {
            outAdjacency[i] = new HashSet<int>();
        }

        int MaxOutPerUser() => Math.Min(n - 1, Math.Max(1, (int)Math.Round(request.AvgFollows * 3.5)));

        int SampleOut()
        {
            const double sigma = 1.0;
            var mu = Math.Log(Math.Max(1.0, request.AvgFollows)) - 0.5 * sigma * sigma;
            var u1 = 1.0 - rng.NextDouble();
            var u2 = 1.0 - rng.NextDouble();
            var z = Math.Sqrt(-2.0 * Math.Log(u1)) * Math.Cos(2.0 * Math.PI * u2);
            var value = Math.Exp(mu + sigma * z);
            var desired = (int)Math.Round(value);
            return Math.Clamp(desired, 1, MaxOutPerUser());
        }

        double WeightForTarget(int src, int dst)
        {
            if (src == dst)
            {
                return 0d;
            }

            var weight = 1.0 + inDegree[dst];
            if (metadata[src].Interests.Overlaps(metadata[dst].Interests))
            {
                weight *= request.HomophilyBoost;
            }

            if (metadata[dst].IsInfluencer)
            {
                weight *= request.InfluencerBoost;
            }

            if (metadata[dst].IsBot)
            {
                weight *= 0.7;
            }

            return weight;
        }

        bool TryPickTarget(int src, out int picked)
        {
            double total = 0;
            picked = -1;

            for (var j = 0; j < n; j++)
            {
                if (j == src)
                {
                    continue;
                }

                if (outAdjacency[src].Contains(j))
                {
                    continue;
                }

                var weight = WeightForTarget(src, j);
                if (weight <= 0)
                {
                    continue;
                }

                total += weight;
                if (rng.NextDouble() < weight / total)
                {
                    picked = j;
                }
            }

            return picked >= 0;
        }

        var edgeBuffer = new List<(int Source, int Target)>(n * 8);

        for (var source = 0; source < n; source++)
        {
            var desired = SampleOut();
            var guard = 0;
            var maxGuard = desired * 8 + 64;

            while (outAdjacency[source].Count < desired && guard++ < maxGuard)
            {
                int target;
                if (rng.NextDouble() < request.NoiseFollowProb)
                {
                    target = rng.Next(n);
                    if (target == source || outAdjacency[source].Contains(target))
                    {
                        continue;
                    }
                }
                else if (!TryPickTarget(source, out target))
                {
                    break;
                }

                outAdjacency[source].Add(target);
                inDegree[target]++;
                edgeBuffer.Add((source, target));
            }
        }

        var triadicAdded = 0;
        for (var source = 0; source < n; source++)
        {
            var friendsOfFriends = new HashSet<int>();
            foreach (var friend in outAdjacency[source])
            {
                foreach (var candidate in outAdjacency[friend])
                {
                    if (candidate != source && !outAdjacency[source].Contains(candidate))
                    {
                        friendsOfFriends.Add(candidate);
                    }
                }
            }

            foreach (var candidate in friendsOfFriends)
            {
                if (rng.NextDouble() > request.TriadicProb)
                {
                    continue;
                }

                if (outAdjacency[source].Contains(candidate))
                {
                    continue;
                }

                outAdjacency[source].Add(candidate);
                inDegree[candidate]++;
                edgeBuffer.Add((source, candidate));
                triadicAdded++;
            }
        }

        var reciprocalAdded = 0;
        foreach (var (source, target) in edgeBuffer.ToArray())
        {
            if (outAdjacency[target].Contains(source))
            {
                continue;
            }

            var probability = request.ReciprocityProb;
            if (metadata[source].IsInfluencer)
            {
                probability *= 0.6;
            }

            if (metadata[target].IsInfluencer)
            {
                probability *= 0.6;
            }

            if (rng.NextDouble() < probability)
            {
                outAdjacency[target].Add(source);
                inDegree[source]++;
                edgeBuffer.Add((target, source));
                reciprocalAdded++;
            }
        }

        var personIds = createdPersons.Select(p => p.PersonId).ToArray();
        foreach (var (source, target) in edgeBuffer)
        {
            var (_, followCharge) = await _personRepository.FollowAsync(personIds[source], personIds[target], cancellationToken);
            totalRequestCharge += followCharge;
        }

        static long MakeEdgeKey(int source, int target) => ((long)source << 32) | (uint)target;

        var uniqueEdges = new HashSet<long>(edgeBuffer.Count);
        foreach (var (source, target) in edgeBuffer)
        {
            uniqueEdges.Add(MakeEdgeKey(source, target));
        }

        var edgeCount = uniqueEdges.Count;
        var mutualEdges = 0;
        foreach (var (source, target) in edgeBuffer)
        {
            if (uniqueEdges.Contains(MakeEdgeKey(target, source)))
            {
                mutualEdges++;
            }
        }

        var reciprocity = edgeCount == 0 ? 0d : (mutualEdges / 2.0) / edgeCount;
        var avgDegree = n == 0 ? 0d : edgeCount / (double)n;

        var topHubs = Enumerable.Range(0, n)
            .OrderByDescending(i => inDegree[i])
            .Take(Math.Min(10, n))
            .Select(i => new GraphSeedTopHub(personIds[i], inDegree[i]))
            .ToArray();

        var stats = new GraphSeedStats(
            Users: n,
            AccountsCreated: n,
            Edges: edgeCount,
            AvgOut: Math.Round(avgDegree, 2),
            AvgIn: Math.Round(avgDegree, 2),
            TriadicAdded: triadicAdded,
            ReciprocalAdded: reciprocalAdded,
            Reciprocity: Math.Round(reciprocity, 3),
            GiniFollowers: CalculateGini(inDegree),
            TopHubs: topHubs);

        var message = $"Initialized {n} accounts, {n} persons and {edgeCount} follow edges (incl. triadic + reciprocity).";

        return new GraphSeedResult(message, stats, totalRequestCharge);
    }

    private static double CalculateGini(IReadOnlyList<int> values)
    {
        if (values.Count == 0)
        {
            return 0d;
        }

        var sorted = values.Select(v => (double)v).OrderBy(v => v).ToArray();
        var cumulative = 0d;
        var sum = sorted.Sum();
        if (sum == 0)
        {
            return 0d;
        }

        var giniAccumulator = 0d;
        for (var i = 0; i < sorted.Length; i++)
        {
            cumulative += sorted[i];
            giniAccumulator += cumulative - sorted[i] / 2.0;
        }

        var lorenz = giniAccumulator / (sorted.Length * sum);
        return Math.Round(1 - 2 * lorenz, 4);
    }

    private sealed record UserMeta(bool IsInfluencer, bool IsBot, HashSet<string> Interests);
}
