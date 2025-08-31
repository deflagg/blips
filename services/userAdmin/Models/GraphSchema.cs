public static class GraphSchema
{
    public static class Labels
    {
        public const string User = "user";
        public const string Follows = "follows";
        public const string FollowedBy = "followedBy"; // mirrored edge for fast followers
    }

    public static class Props
    {
        public const string Id = "id";                 // Cosmos id
        public const string UserId = "userId";         // partition key (== Id)
        public const string DisplayName = "displayName";
        public const string Email = "email";
        public const string CreatedAt = "createdAt";
        public const string UpdatedAt = "updatedAt";
    }

    // Reusable projection that every user read should use
    public static string UserProjection => $@"
      project('{Props.Id}','{Props.DisplayName}','{Props.Email}','{Props.CreatedAt}','{Props.UpdatedAt}')
        .by(values('{Props.Id}'))
        .by(values('{Props.DisplayName}'))
        .by(coalesce(values('{Props.Email}'), constant(null)))
        .by(values('{Props.CreatedAt}'))
        .by(values('{Props.UpdatedAt}'))";
}
