namespace BlipWriter.Infrastructure;

public sealed class CosmosOptions
{
    public string Endpoint { get; init; } = default!;
    public string Key { get; init; } = default!;
    public string DatabaseId { get; init; } = "blips";
    public string ContainerId { get; init; } = "user-followers";
}
