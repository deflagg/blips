using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace UserAdmin.Infrastructure;

public interface ICosmosInitializer { Task InitializeAsync(CancellationToken ct = default); }

public sealed class CosmosInitializer : ICosmosInitializer
{
    private readonly CosmosClient _client;
    private readonly CosmosOptions _opt;

    public CosmosInitializer(CosmosClient client, IOptions<CosmosOptions> opt)
    { _client = client; _opt = opt.Value; }

    public async Task InitializeAsync(CancellationToken ct = default)
    {
        var db = (await _client.CreateDatabaseIfNotExistsAsync(_opt.DatabaseId, cancellationToken: ct)).Database;
        var props = new ContainerProperties(_opt.ContainerId, "/userId");
        await db.CreateContainerIfNotExistsAsync(props, cancellationToken: ct);
    }
}
