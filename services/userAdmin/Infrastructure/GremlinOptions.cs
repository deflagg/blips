namespace UserAdmin.Infrastructure;

public sealed class GremlinOptions
{
    public string SubscriptionId { get; set; } = default!;
    public string ResourceGroup  { get; set; } = default!;
    public string AccountName    { get; set; } = default!;
    public string DatabaseId     { get; set; } = default!;
    public string GraphId        { get; set; } = default!;
}
