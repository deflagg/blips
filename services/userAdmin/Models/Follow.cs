namespace UserAdmin.Models;
public sealed record Follow(
    string FollowerId,
    string FolloweeId,
    DateTimeOffset CreatedAt
);