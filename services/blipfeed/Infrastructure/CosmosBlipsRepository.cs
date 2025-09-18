using System.Net;
using System.Linq;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;
using BlipFeed.Models;

namespace BlipFeed.Infrastructure;

public interface IBlipsRepository
{
    Task<(Blip Item, string ETag, double RU)?> GetAsync(string id, string userId, CancellationToken ct);
    Task<(IReadOnlyList<Blip> Items, string? ContinuationToken, double RU)> ListAsync(
        IReadOnlyCollection<string> userIds, int pageSize, string? continuationToken, CancellationToken ct);
}

public sealed class CosmosBlipsRepository : IBlipsRepository
{
    private readonly Container _container;

    public CosmosBlipsRepository(CosmosClient client, IOptions<CosmosOptions> opt)
    {
        var o = opt.Value;
        var db = o.Databases["BlipsDatabase"];
        var c = db.Containers["Accounts"];
        _container = client.GetContainer(db.DatabaseId, c.ContainerId);
        // Assumes container PK path == "/accountId"
    }

    public async Task<(Blip, string, double)?> GetAsync(string id, string userId, CancellationToken ct)
    {
        try
        {
            var resp = await _container.ReadItemAsync<Blip>(id, new PartitionKey(userId), cancellationToken: ct);
            return (resp.Resource, resp.ETag, resp.RequestCharge);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<(IReadOnlyList<Blip>, string?, double)> ListAsync(
        IReadOnlyCollection<string> userIds, int pageSize, string? continuationToken, CancellationToken ct)
    {
        if (userIds.Count == 0) return (Array.Empty<Blip>(), null, 0d);

        var ids = userIds
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .ToArray();

        if (ids.Length == 0) return (Array.Empty<Blip>(), null, 0d);

        var q = new QueryDefinition("SELECT * FROM c WHERE ARRAY_CONTAINS(@uids, c.userId) ORDER BY c.createdAt DESC")
            .WithParameter("@uids", ids);

        var requestOptions = new QueryRequestOptions
        {
            MaxItemCount = pageSize
        };

        var it = _container.GetItemQueryIterator<Blip>(q, continuationToken, requestOptions);

        if (!it.HasMoreResults) return (Array.Empty<Blip>(), null, 0d);

        var page = await it.ReadNextAsync(ct);
        return (page.Resource.ToList(), page.ContinuationToken, page.RequestCharge);
    }
}
