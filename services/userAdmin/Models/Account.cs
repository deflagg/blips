using System.Text.Json.Serialization;

namespace UserAdmin.Models;
public sealed class Account
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = default!;

    // Partition key
    [JsonPropertyName("accountId")]
    public string AccountId { get; set; } = default!;

    [JsonPropertyName("name")]
    public string Name { get; set; } = default!;

    [JsonPropertyName("email")]
    public string Email { get; set; } = default!;

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset? UpdatedAt { get; set; }
}

public record AccountDto(string Id, string AccountId, string Name, string Email, DateTimeOffset CreatedAt, DateTimeOffset? UpdatedAt);

public static class AccountMapping
{
    public static AccountDto ToDto(this Account b) =>
        new(b.Id, b.AccountId, b.Name, b.Email, b.CreatedAt, b.UpdatedAt);
}
