public sealed class RedisOptions
{
    public bool Enabled { get; init; } = true;
    public string? ConnectionString { get; init; }
    public string InstanceName { get; init; } = "blips:";
    public int FeedTtlSeconds { get; init; } = 30;
}
