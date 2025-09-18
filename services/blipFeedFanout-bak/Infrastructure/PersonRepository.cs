using Gremlin.Net.Driver;
using Gremlin.Net.Driver.Messages;

using System.Globalization;
using System.Text.Json;
using BlipFeedFanout.Models;


namespace BlipFeedFanout.Infrastructure;

public interface IPersonRepository
{
    // Users
    Task<(Person person, double ru)> UpsertPersonAsync(Person person, CancellationToken ct = default);
    Task<(IReadOnlyList<Person> persons, IReadOnlyList<(string source, string target, DateTimeOffset createdAt)> edges, double ru)> GetGraphAsync(int vertexLimit = 2000, int edgeLimit = 10000, CancellationToken ct = default);
    Task<(Person? person, double ru)> GetPersonAsync(string personId, CancellationToken ct = default);
    Task<(bool deleted, double ru)> DeletePersonAsync(string personId, CancellationToken ct = default);

    Task<double> DeleteGraphAsync(CancellationToken ct = default);
    Task<(bool created, double ru)> FollowAsync(string followerId, string followeeId, CancellationToken ct = default);
}

public sealed class PersonRepository : IPersonRepository
{
    private readonly GremlinClient _client;

    public PersonRepository(GremlinClient client)
    {
        _client = client;
    }

    public async Task<(Person person, double ru)> UpsertPersonAsync(Person person, CancellationToken ct = default)
    {
        var now = (person.UpdatedAt == default ? DateTimeOffset.UtcNow : person.UpdatedAt);
        var createdAt = person.CreatedAt == default ? now : person.CreatedAt;
        var id = string.IsNullOrWhiteSpace(person.Id) ? (person.PersonId ?? Guid.NewGuid().ToString("n")) : person.Id;

        var gremlin = @"
g.V().has('person','personId',personId).fold().
  coalesce(
    unfold()
      .property('name',name)
      .property('email',email)
      .property('accountId',accountId)
      .property('updatedAt',updatedAt),
    addV('person')
      .property('id', id)
      .property('personId',personId)
      .property('accountId',accountId)
      .property('name',name)
      .property('email',email)
      .property('createdAt',createdAt)
      .property('updatedAt',updatedAt)
  ).
  valueMap(true)";

        var bindings = new Dictionary<string, object?>
        {
            ["id"] = id,
            ["personId"] = person.PersonId,
            ["accountId"] = person.AccountId,
            ["name"] = person.Name,
            ["email"] = person.Email,
            ["createdAt"] = createdAt.UtcDateTime.ToString("o", CultureInfo.InvariantCulture),
            ["updatedAt"] = now.UtcDateTime.ToString("o", CultureInfo.InvariantCulture)
        };

        var rs = await _client.SubmitAsync<dynamic>(gremlin, bindings).ConfigureAwait(false);
        var mapped = rs.Any()
            ? MapPersonFromValueMap(rs.First())
            : // extremely unlikely (coalesce always returns a vertex), but fall back to input
              new Person
              {
                  Id = id,
                  PersonId = person.PersonId,
                  AccountId = person.AccountId,
                  Name = person.Name,
                  Email = person.Email,
                  CreatedAt = createdAt,
                  UpdatedAt = now
              };

        return (mapped, GetRu(rs));
    }

    public async Task<(IReadOnlyList<Person> persons, IReadOnlyList<(string source, string target, DateTimeOffset createdAt)> edges, double ru)>
        GetGraphAsync(int vertexLimit = 2000, int edgeLimit = 10000, CancellationToken ct = default)
    {
        // 1) Pull person vertices
        var vScript = @"
g.V().hasLabel('person').limit(vLimit).valueMap(true)";
        var vBindings = new Dictionary<string, object?> { ["vLimit"] = vertexLimit };

        var vRs = await _client.SubmitAsync<dynamic>(vScript, vBindings).ConfigureAwait(false);
        var persons = vRs.Select(MapPersonFromValueMap).ToList();

        // 2) Pull edges that connect person->person (any label), limited
        var eScript = @"
g.E().limit(eLimit).
  where(outV().hasLabel('person')).
  where(inV().hasLabel('person')).
  project('source','target','createdAt').
    by(outV().id()).
    by(inV().id()).
    by(values('createdAt'))";
        var eBindings = new Dictionary<string, object?> { ["eLimit"] = edgeLimit };

        var eRs = await _client.SubmitAsync<dynamic>(eScript, eBindings).ConfigureAwait(false);

        var edges = new List<(string source, string target, DateTimeOffset createdAt)>(eRs.Count);
        foreach (var row in eRs)
        {
            // row is a dictionary-like dynamic with keys: source, target, createdAt
            var map = (IDictionary<string, object>)row;
            var source = map.TryGetValue("source", out var sObj) ? sObj?.ToString() ?? "" : "";
            var target = map.TryGetValue("target", out var tObj) ? tObj?.ToString() ?? "" : "";

            DateTimeOffset createdAt = DateTimeOffset.MinValue;
            if (map.TryGetValue("createdAt", out var cObj) && cObj is not null)
            {
                if (cObj is string cStr && !string.IsNullOrWhiteSpace(cStr))
                {
                    if (DateTimeOffset.TryParse(cStr, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var parsed))
                        createdAt = parsed.ToUniversalTime();
                }
                else if (cObj is DateTime dt)
                {
                    createdAt = new DateTimeOffset(DateTime.SpecifyKind(dt, DateTimeKind.Utc));
                }
                else if (cObj is DateTimeOffset dto)
                {
                    createdAt = dto.ToUniversalTime();
                }
            }

            if (!string.IsNullOrEmpty(source) && !string.IsNullOrEmpty(target))
                edges.Add((source, target, createdAt));
        }

        var totalRu = GetRu(vRs) + GetRu(eRs);
        return (persons, edges, totalRu);
    }

    public async Task<(Person? person, double ru)> GetPersonAsync(string personId, CancellationToken ct = default)
    {
        var script = @"
g.V().has('person','personId',personId).limit(1).valueMap(true)";
        var bindings = new Dictionary<string, object?> { ["personId"] = personId };

        var rs = await _client.SubmitAsync<dynamic>(script, bindings).ConfigureAwait(false);

        Person? person = rs.Any() ? MapPersonFromValueMap(rs.First()) : null;
        return (person, GetRu(rs));
    }

    public async Task<(bool deleted, double ru)> DeletePersonAsync(string personId, CancellationToken ct = default)
    {
        // Returns true if found and dropped, else false, all in one round-trip.
        var script = @"
g.V().has('person','personId',personId).fold().
  coalesce(
    unfold().as('v').
      bothE().drop().
      select('v').drop().
      constant(true),
    constant(false)
  )";
        var bindings = new Dictionary<string, object?> { ["personId"] = personId };

        var rs = await _client.SubmitAsync<bool>(script, bindings).ConfigureAwait(false);
        bool deleted = rs.FirstOrDefault();
        return (deleted, GetRu(rs));
    }

    public async Task<double> DeleteGraphAsync(CancellationToken ct = default)
    {
        // Force the real Gremlin.NET GraphSON path by using RequestMessage.
        var msg = RequestMessage.Build(Tokens.OpsEval)
            .AddArgument(Tokens.ArgsGremlin, "g.V().drop()")
            .Create();

        var rs = await _client.SubmitAsync<dynamic>(msg).ConfigureAwait(false);
        return GetRu(rs); // your existing RU helper
    }

    public async Task<(bool created, double ru)> FollowAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        // No self-follow, and require ids
        if (string.IsNullOrWhiteSpace(followerId) ||
            string.IsNullOrWhiteSpace(followeeId) ||
            string.Equals(followerId, followeeId, StringComparison.Ordinal))
        {
            return (false, 0d);
        }

        var createdAt = DateTimeOffset.UtcNow.ToString("o", CultureInfo.InvariantCulture);

        // If both vertices exist:
        // - if edge already exists: return false
        // - else create edge with createdAt and return true
        // If either vertex missing: traversal yields no result -> treat as false
        var script = @"
g.V().has('person','personId',followerId).limit(1).as('a').
  V().has('person','personId',followeeId).limit(1).as('b').
  coalesce(
    select('a').outE('follows').where(inV().as('b')).limit(1).constant(false),
    addE('follows').from('a').to('b').property('createdAt',createdAt).constant(true)
  )";

        var bindings = new Dictionary<string, object?>
        {
            ["followerId"] = followerId,
            ["followeeId"] = followeeId,
            ["createdAt"] = createdAt
        };

        var rs = await _client.SubmitAsync<bool>(script, bindings).ConfigureAwait(false);
        bool created = rs.FirstOrDefault(); // empty => false
        return (created, GetRu(rs));
    }

    // --------------------------
    // Helpers
    // --------------------------

    private static Person MapPersonFromValueMap(dynamic row)
    {
        var map = (IDictionary<string, object>)row;

        string GetString(string key)
        {
            if (!map.TryGetValue(key, out var val) || val is null) return "";
            // valueMap(true) returns lists for properties; id/label are scalars
            if (val is string s) return s;
            if (val is IEnumerable<object> list)
            {
                var first = list.Cast<object?>().FirstOrDefault();
                return first?.ToString() ?? "";
            }
            return val.ToString() ?? "";
        }

        DateTimeOffset GetDto(string key)
        {
            var s = GetString(key);
            if (string.IsNullOrWhiteSpace(s)) return DateTimeOffset.MinValue;
            if (DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dto))
                return dto.ToUniversalTime();
            return DateTimeOffset.MinValue;
        }

        var id = map.TryGetValue("id", out var idObj) ? idObj?.ToString() ?? "" : "";

        return new Person
        {
            Id = id,
            PersonId = GetString("personId"),
            AccountId = GetString("accountId"),
            Name = GetString("name"),
            Email = GetString("email"),
            CreatedAt = GetDto("createdAt"),
            UpdatedAt = GetDto("updatedAt")
        };
    }

    private static double GetRu<T>(ResultSet<T> rs)
    {
        if (rs?.StatusAttributes is null) return 0d;

        // Cosmos DB Gremlin API commonly uses "x-ms-total-request-charge"; some responses use "x-ms-request-charge"
        var attrs = rs.StatusAttributes;
        if (attrs.TryGetValue("x-ms-total-request-charge", out var total) && TryToDouble(total, out var d1)) return d1;
        if (attrs.TryGetValue("x-ms-request-charge", out var single) && TryToDouble(single, out var d2)) return d2;

        return 0d;

        static bool TryToDouble(object? o, out double d)
        {
            switch (o)
            {
                case double dd: d = dd; return true;
                case float ff: d = ff; return true;
                case decimal m: d = (double)m; return true;
                case long l: d = l; return true;
                case int i: d = i; return true;
                case string s when double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var p): d = p; return true;
                default: d = 0; return false;
            }
        }
    }
}