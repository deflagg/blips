namespace BlipFeedFanout.Infrastructure;

public enum GremlinMode { Emulator, Cloud }

public sealed class GremlinCommonOptions
{
    public required string DatabaseId { get; init; }
    public required string GraphId { get; init; }
}

public sealed class GremlinCloudOptions
{
    public required string AccountName { get; init; }
    public string? SubscriptionId { get; init; }
    public string? ResourceGroup  { get; init; }
}

public sealed class GremlinEmulatorOptions
{
    public required string Host { get; init; } 
    public int Port    { get; init; } 
    public required string AuthKey { get; init; } 
}

public sealed class GremlinOptions
{
    public GremlinMode Mode { get; init; } = GremlinMode.Cloud;
    public required GremlinCommonOptions Common { get; init; }
    public GremlinCloudOptions? Cloud { get; init; }
    public GremlinEmulatorOptions? Emulator { get; init; }
}
