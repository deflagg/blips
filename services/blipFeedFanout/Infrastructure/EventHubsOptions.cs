public sealed class EventHubsOptions
{
    public bool Enabled { get; set; } = true;
    public string? ConnectionString { get; set; }
    public string? EventHubName { get; set; }
    public string? ConsumerGroup { get; set; } 
    public bool StartFromEarliest { get; set; } = false;  // set true for catch-up
}
