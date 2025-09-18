public sealed class EventHubsOptions
{
    public bool Enabled { get; init; } = true;
    public string? ConnectionString { get; init; }
    public string EventHubName { get; init; } = "blip-events"; // pick your hub name
}
