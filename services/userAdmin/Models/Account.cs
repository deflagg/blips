namespace UserAdmin.Models;
public sealed class Account
{
    // Cosmos SQL API requires "id" property.
    public string id { get; set; } = Guid.NewGuid().ToString("n");
    public string userId { get; set; } = default!;
    public string name { get; set; } = default!;
    public DateTimeOffset createdAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset updatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public record AccountDto(string Id, string UserId, string Name, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);

public static class AccountMapping
{
    public static AccountDto ToDto(this Account b) =>
        new(b.id, b.userId, b.name, b.createdAt, b.updatedAt);
}
