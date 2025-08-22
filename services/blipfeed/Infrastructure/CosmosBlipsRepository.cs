using System.Net;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;
using BlipFeed.Models;

namespace BlipFeed.Infrastructure;

public interface IBlipsRepository
{
    Task<(Blip Item, string ETag, double RU)> CreateAsync(Blip blip, CancellationToken ct);
    Task<(Blip Item, string ETag, double RU)?> GetAsync(string id, string userId, CancellationToken ct);
    Task<(IReadOnlyList<Blip> Items, string? ContinuationToken, double RU)> ListAsync(
        string userId, int pageSize, string? continuationToken, CancellationToken ct);
    Task<(Blip Item, string ETag, double RU)?> UpdateAsync(Blip blip, string ifMatchEtag, CancellationToken ct);
    Task<(bool Deleted, double RU)> DeleteAsync(string id, string userId, string? ifMatchEtag, CancellationToken ct);
}

public sealed class CosmosBlipsRepository : IBlipsRepository
{
    private readonly Container _container;

    public CosmosBlipsRepository(CosmosClient client, IOptions<CosmosOptions> opt)
    {
        var o = opt.Value;
        _container = client.GetContainer(o.DatabaseId, o.ContainerId);
    }

    public async Task<(Blip, string, double)> CreateAsync(Blip blip, CancellationToken ct)
    {
        var resp = await _container.CreateItemAsync(blip, new PartitionKey(blip.userId), cancellationToken: ct);
        return (resp.Resource, resp.ETag, resp.RequestCharge);
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

    public async Task<(Blip, string, double)?> UpdateAsync(Blip blip, string ifMatchEtag, CancellationToken ct)
    {
        try
        {
            blip.updatedAt = DateTimeOffset.UtcNow;
            var resp = await _container.ReplaceItemAsync(
                item: blip,
                id: blip.id,
                partitionKey: new PartitionKey(blip.userId),
                requestOptions: new ItemRequestOptions { IfMatchEtag = ifMatchEtag },
                cancellationToken: ct);
            return (resp.Resource, resp.ETag, resp.RequestCharge);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.PreconditionFailed)
        {
            return null; // ETag mismatch (concurrency conflict)
        }
    }

    public async Task<(bool, double)> DeleteAsync(string id, string userId, string? ifMatchEtag, CancellationToken ct)
    {
        try
        {
            var opts = ifMatchEtag is null ? null : new ItemRequestOptions { IfMatchEtag = ifMatchEtag };
            var resp = await _container.DeleteItemAsync<Blip>(id, new PartitionKey(userId), opts, ct);
            return (true, resp.RequestCharge);
        }
        catch (CosmosException ex) when (ex.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.PreconditionFailed)
        {
            return (false, 0d);
        }
    }
}
