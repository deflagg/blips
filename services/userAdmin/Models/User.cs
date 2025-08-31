namespace UserAdmin.Models;

public sealed record User(
    string Id,
    string DisplayName,
    string? Email,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt
);

public readonly record struct Suggestion(User User, long Mutuals);
public readonly record struct WithRu<T>(T Value, double Ru);