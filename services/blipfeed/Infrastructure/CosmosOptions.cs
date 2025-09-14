namespace BlipFeed.Infrastructure;

public sealed class CosmosOptions
{
    public string Endpoint { get; init; } = default!;
    public string Key { get; init; } = default!;
    public Dictionary<string, DatabaseOptions> Databases { get; init; } = new();

    public sealed class DatabaseOptions
    {
        public string DatabaseId { get; init; } = default!;
        public int? Throughput { get; init; }
        public Dictionary<string, ContainerOptions> Containers { get; init; } = new();
    }

    public sealed class ContainerOptions
    {
        public string ContainerId { get; init; } = default!;
        public string PartitionKeyPath { get; init; } = default!;
        public int? Throughput { get; init; }
        public List<List<string>>? UniqueKeySets { get; init; }
        public int? DefaultTtlSeconds { get; init; }
        public bool? ExcludeAllFromIndexing { get; init; }
    }
}