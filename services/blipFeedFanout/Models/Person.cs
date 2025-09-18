using System.Text.Json.Serialization;

namespace BlipFeedFanout.Models;

public sealed class Person
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = default!;

    [JsonPropertyName("personId")]
    public string PersonId { get; set; } = default!;

    [JsonPropertyName("accountId")]
    public string AccountId { get; set; } = default!;

    [JsonPropertyName("name")]
    public string Name { get; set; } = default!;

    [JsonPropertyName("email")]
    public string Email { get; set; } = default!;


    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset UpdatedAt { get; set; }
}

sealed class UserMeta
{
    public bool IsInfluencer { get; set; }
    public bool IsBot { get; set; }
    public HashSet<string> Interests { get; set; } = new();
}

public readonly record struct Suggestion(Person person, long mutuals);
public readonly record struct WithRu<T>(T value, double ru);