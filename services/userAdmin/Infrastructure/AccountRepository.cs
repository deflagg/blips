using System.Net;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;
using UserAdmin.Models;

namespace UserAdmin.Infrastructure;

public interface IAccountsRepository
{
    Task<(Account Item, string ETag, double RU)> CreateAsync(Account account, CancellationToken ct);

    // point-read requires both the item id and its partition key
    Task<(Account Item, string ETag, double RU)?> GetAsync(string id, string accountId, CancellationToken ct);

    // list by account partition (recommended for Pattern B)
    Task<(IReadOnlyList<Account> Items, string? Continuation, double RU)> ListByAccountAsync(
        string accountId, int pageSize, string? continuation, CancellationToken ct);

    // keep a cross-account list if you really want it (scans all partitions)
    Task<(IReadOnlyList<Account> Items, string? Continuation, double RU)> ListAsync(
        int pageSize, string? continuation, CancellationToken ct);

    Task<(Account Item, string ETag, double RU)?> UpdateAsync(Account account, string ifMatchEtag, CancellationToken ct);

    Task<(bool Deleted, double RU)> DeleteAsync(string id, string accountId, string? ifMatchEtag, CancellationToken ct);
}

public sealed class AccountsRepository : IAccountsRepository
{
    private readonly Container _container;

    public AccountsRepository(CosmosClient client, IOptions<CosmosOptions> opt)
    {
        var o = opt.Value;
        var db = o.Databases["BlipsDatabase"];
        var c = db.Containers["Accounts"];
        _container = client.GetContainer(db.DatabaseId, c.ContainerId);
        // Assumes container PK path == "/accountId"
    }

    public async Task<(Account, string, double)> CreateAsync(Account account, CancellationToken ct)
    {
        // Normalize required keys
        if (string.IsNullOrWhiteSpace(account.AccountId))
            throw new ArgumentException("account.AccountId (partition key) is required.");

        if (string.IsNullOrWhiteSpace(account.Id))
            account.Id = Guid.NewGuid().ToString("n");  // unique per doc

        account.CreatedAt = DateTimeOffset.UtcNow;
        account.UpdatedAt = null;

        var resp = await _container.CreateItemAsync(
            account,
            new PartitionKey(account.AccountId),
            cancellationToken: ct);

        return (resp.Resource, resp.ETag, resp.RequestCharge);
    }

    public async Task<(Account, string, double)?> GetAsync(string id, string accountId, CancellationToken ct)
    {
        try
        {
            var resp = await _container.ReadItemAsync<Account>(
                id, new PartitionKey(accountId), cancellationToken: ct);
            return (resp.Resource, resp.ETag, resp.RequestCharge);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<(IReadOnlyList<Account>, string?, double)> ListByAccountAsync(string accountId, int pageSize, string? continuation, CancellationToken ct)
    {
        var q = new QueryDefinition(
            "SELECT * FROM c WHERE c.accountId = @pk ORDER BY c.createdAt DESC")
            .WithParameter("@pk", accountId);

        var it = _container.GetItemQueryIterator<Account>(
            q,
            continuation,
            new QueryRequestOptions
            {
                MaxItemCount = pageSize,
                PartitionKey = new PartitionKey(accountId) // scoped to one partition
            });

        if (!it.HasMoreResults) return (Array.Empty<Account>(), null, 0d);

        var page = await it.ReadNextAsync(ct);
        return (page.Resource.ToList(), page.ContinuationToken, page.RequestCharge);
    }

    // (Optional) cross-account listing (fan-out). Remove if you don't need it.
    public async Task<(IReadOnlyList<Account>, string?, double)> ListAsync(int pageSize, string? continuation, CancellationToken ct)
    {
        var q = new QueryDefinition("SELECT * FROM c ORDER BY c.createdAt DESC");

        var it = _container.GetItemQueryIterator<Account>(
            q,
            continuation,
            new QueryRequestOptions { MaxItemCount = pageSize /* no PK = cross-partition */ });

        if (!it.HasMoreResults) return (Array.Empty<Account>(), null, 0d);

        var page = await it.ReadNextAsync(ct);
        return (page.Resource.ToList(), page.ContinuationToken, page.RequestCharge);
    }

    public async Task<(Account, string, double)?> UpdateAsync(Account account, string ifMatchEtag, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(account.Id) || string.IsNullOrWhiteSpace(account.AccountId))
            throw new ArgumentException("Account.Id and Account.AccountId are required for update.");

        try
        {
            account.UpdatedAt = DateTimeOffset.UtcNow;

            var resp = await _container.ReplaceItemAsync(
                item: account,
                id: account.Id,
                partitionKey: new PartitionKey(account.AccountId),
                requestOptions: new ItemRequestOptions { IfMatchEtag = ifMatchEtag },
                cancellationToken: ct);

            return (resp.Resource, resp.ETag, resp.RequestCharge);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.PreconditionFailed)
        {
            // ETag mismatch
            return null;
        }
    }

    public async Task<(bool, double)> DeleteAsync(string id, string accountId, string? ifMatchEtag, CancellationToken ct)
    {
        try
        {
            var opts = ifMatchEtag is null ? null : new ItemRequestOptions { IfMatchEtag = ifMatchEtag };

            var resp = await _container.DeleteItemAsync<Account>(
                id, new PartitionKey(accountId), opts, ct);

            return (true, resp.RequestCharge);
        }
        catch (CosmosException ex) when (ex.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.PreconditionFailed)
        {
            return (false, 0d);
        }
    }
}