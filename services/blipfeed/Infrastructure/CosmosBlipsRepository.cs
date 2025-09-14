using System.Net;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;
using BlipFeed.Models;

namespace BlipFeed.Infrastructure;

public interface IBlipsRepository
{
    Task<(Blip Item, string ETag, double RU)?> GetAsync(string id, string userId, CancellationToken ct);
    Task<(IReadOnlyList<Blip> Items, string? ContinuationToken, double RU)> ListAsync(
        string userId, int pageSize, string? continuationToken, CancellationToken ct);
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
        string userId, int pageSize, string? continuationToken, CancellationToken ct)
    {
        var q = new QueryDefinition("SELECT * FROM c WHERE c.userId = @uid ORDER BY c.createdAt DESC")
            .WithParameter("@uid", userId);

        var it = _container.GetItemQueryIterator<Blip>(
            q,
            continuationToken,
            new QueryRequestOptions { PartitionKey = new PartitionKey(userId), MaxItemCount = pageSize });

        if (!it.HasMoreResults) return (Array.Empty<Blip>(), null, 0d);

        var page = await it.ReadNextAsync(ct);
        return (page.Resource.ToList(), page.ContinuationToken, page.RequestCharge);
    }
}
