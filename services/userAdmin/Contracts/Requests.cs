namespace UserAdmin.Contracts;

public record CreateBlipRequest(string UserId, string Text);
public record UpdateBlipRequest(string Text);
