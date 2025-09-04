using System.Net;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;
using UserAdmin.Models;

namespace UserAdmin.Infrastructure;

public interface IAccountsRepository
{
    Task<(Account Item, string ETag, double RU)> CreateAsync(Account account, CancellationToken ct);
    Task<(Account Item, string ETag, double RU)?> GetAsync(string id, CancellationToken ct);
    Task<(IReadOnlyList<Account> Items, string? Continuation, double RU)> ListAsync(int pageSize, string? continuation, CancellationToken ct);
    Task<(Account Item, string ETag, double RU)?> UpdateAsync(Account account, string ifMatchEtag, CancellationToken ct);
    Task<(bool Deleted, double RU)> DeleteAsync(string id, string? ifMatchEtag, CancellationToken ct);
}

public sealed class AccountsRepository : IAccountsRepository
{
    private readonly Container _container;
    public AccountsRepository(CosmosClient client, IOptions<CosmosOptions> opt)
    {
        var o = opt.Value;
        var db = o.Databases["UserAdmin"];
        var c = db.Containers["Accounts"];
        _container = client.GetContainer(db.DatabaseId, c.ContainerId);
    }

    public async Task<(Account, string, double)> CreateAsync(Account account, CancellationToken ct)
    {
        var resp = await _container.CreateItemAsync(account, new PartitionKey(account.id), cancellationToken: ct);
        return (resp.Resource, resp.ETag, resp.RequestCharge);
    }

    public async Task<(Account, string, double)?> GetAsync(string id, CancellationToken ct)
    {
        try
        {
            var resp = await _container.ReadItemAsync<Account>(id, new PartitionKey(id), cancellationToken: ct);
            return (resp.Resource, resp.ETag, resp.RequestCharge);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound) { return null; }
    }

    public async Task<(IReadOnlyList<Account>, string?, double)> ListAsync(int pageSize, string? continuation, CancellationToken ct)
    {
        var q = new QueryDefinition("SELECT * FROM c ORDER BY c.createdAt DESC");
        var it = _container.GetItemQueryIterator<Account>(q, continuation, new QueryRequestOptions { MaxItemCount = pageSize });
        if (!it.HasMoreResults) return (Array.Empty<Account>(), null, 0d);
        var page = await it.ReadNextAsync(ct);
        return (page.Resource.ToList(), page.ContinuationToken, page.RequestCharge);
    }

    public async Task<(Account, string, double)?> UpdateAsync(Account account, string ifMatchEtag, CancellationToken ct)
    {
        try
        {
            account.updatedAt = DateTimeOffset.UtcNow;
            var resp = await _container.ReplaceItemAsync(account, account.id, new PartitionKey(account.id),
                new ItemRequestOptions { IfMatchEtag = ifMatchEtag }, ct);
            return (resp.Resource, resp.ETag, resp.RequestCharge);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.PreconditionFailed) { return null; }
    }

    public async Task<(bool, double)> DeleteAsync(string id, string? ifMatchEtag, CancellationToken ct)
    {
        try
        {
            var opts = ifMatchEtag is null ? null : new ItemRequestOptions { IfMatchEtag = ifMatchEtag };
            var resp = await _container.DeleteItemAsync<Account>(id, new PartitionKey(id), opts, ct);
            return (true, resp.RequestCharge);
        }
        catch (CosmosException ex) when (ex.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.PreconditionFailed) { return (false, 0d); }
    }
}
