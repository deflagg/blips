using UserAdmin.Models;

namespace UserAdmin.Contracts;

public sealed record PersonCreateDto(string Id, string DisplayName, string? Email);
public sealed record PersonUpdateDto(string DisplayName, string? Email);
public sealed record FollowStateDto(bool Following);
public sealed record CountDto(long Count);
public sealed record SuggestionDto(Person Person, long Mutuals);
