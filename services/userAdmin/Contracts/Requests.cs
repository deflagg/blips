using Microsoft.Identity.Client;
using UserAdmin.Models;

namespace UserAdmin.Contracts;

public sealed record AccountCreateDto(string Name, string? Email);
public sealed record AccountUpdateDto(string AccountId, string Id, string Name, string? Email);
public sealed record FollowStateDto(bool Following);
public sealed record CountDto(long Count);
public sealed record SuggestionDto(Person Person, long Mutuals);
