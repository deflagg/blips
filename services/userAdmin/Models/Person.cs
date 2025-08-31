namespace UserAdmin.Models;

public sealed record Person(
    string Id,
    string DisplayName,
    string? Email,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt
);

public readonly record struct Suggestion(Person Person, long Mutuals);
public readonly record struct WithRu<T>(T Value, double Ru);