namespace BlipFeed.Models;

public sealed class Blip
{
    // Cosmos SQL API requires "id" property.
    public string id { get; set; } = Guid.NewGuid().ToString("n");
    public string userId { get; set; } = default!;
    public string text { get; set; } = default!;
    public DateTimeOffset createdAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset updatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public record BlipDto(string Id, string UserId, string Text, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);

public static class BlipMapping
{
    public static BlipDto ToDto(this Blip b) =>
        new(b.id, b.userId, b.text, b.createdAt, b.updatedAt);
}
