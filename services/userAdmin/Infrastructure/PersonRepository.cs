using Gremlin.Net.Driver;
using System.Globalization;
using System.Text.Json;
using UserAdmin.Models;

namespace UserAdmin.Infrastructure;

public interface IPersonRepository
{
    // Users
    Task<(Person person, double ru)> UpsertPersonAsync(Person person, CancellationToken ct = default);
    Task<(Person? person, double ru)> GetPersonAsync(string personId, CancellationToken ct = default);
    Task<(bool deleted, double ru)> DeletePersonAsync(string personId, CancellationToken ct = default);

    // Relationships
    Task<(bool created, double ru)> FollowAsync(string followerId, string followeeId, CancellationToken ct = default);
    Task<(bool removed, double ru)> UnfollowAsync(string followerId, string followeeId, CancellationToken ct = default);
    Task<(bool following, double ru)> IsFollowingAsync(string followerId, string followeeId, CancellationToken ct = default);

    // Lists & counts
    Task<(IReadOnlyList<Person> persons, double ru)> GetFollowingAsync(string personId, int skip = 0, int take = 50, CancellationToken ct = default);
    Task<(IReadOnlyList<Person> persons, double ru)> GetFollowersAsync(string personId, int skip = 0, int take = 50, CancellationToken ct = default);
    Task<(long count, double ru)> CountFollowingAsync(string personId, CancellationToken ct = default);
    Task<(long count, double ru)> CountFollowersAsync(string personId, CancellationToken ct = default);

    // Suggestions & mutuals
    Task<(IReadOnlyList<(Person person, long mutuals)> suggestions, double ru)> SuggestToFollowAsync(string personId, int limit = 20, CancellationToken ct = default);
    Task<(IReadOnlyList<Person> persons, double ru)> MutualFollowsAsync(string personIdA, string personIdB, int limit = 50, CancellationToken ct = default);

    // Utilities
    Task<(IReadOnlyList<string> followeeIds, double ru)> GetFolloweeIdsAsync(string personId, int max = 500, CancellationToken ct = default);
}

public sealed class PersonRepository : IPersonRepository
{
    private readonly GremlinClient _client;

    // Always "personId" for PersonGraphDB
    private readonly string _pkName;

    // Map from vertex id -> partition key value. For this DB, pk == id.
    private readonly Func<string, string> _pkForId;

    // Whether to maintain reverse edges for fast followers queries
    private readonly bool _maintainReverseEdge;

    public PersonRepository(
        GremlinClient client,
        string partitionKeyPropertyName = "personId",
        Func<string, string>? pkForId = null,
        bool maintainReverseEdge = true)
    {
        _client = client;
        _pkName = partitionKeyPropertyName;          // should remain "personId"
        _pkForId = pkForId ?? (id => id);            // pk == id in this graph
        _maintainReverseEdge = maintainReverseEdge;
    }

    // ---------------- Users ----------------

    public async Task<(Person, double)> UpsertPersonAsync(Person p, CancellationToken ct = default)
    {
        if (p is null) throw new ArgumentNullException(nameof(p));
        var personId = p.PersonId ?? throw new ArgumentNullException(nameof(p.PersonId));

        // PK == ID for PersonGraphDB
        var partitionKey = personId;

        // Server-managed timestamps
        var nowIso = Iso(DateTimeOffset.UtcNow);

        // CREATE: set PK exactly once (personId). UPDATE: never touch PK.
        var q = $@"
g.V([personId, personId]).fold().
  coalesce(
    // UPDATE (vertex exists)
    unfold()
      .property('name', name)
      .property('email', email)
      .property('updatedAt', updatedAt),
    // CREATE (vertex missing)
    addV('person')
      .property('{_pkName}', personId)   // <-- set PK once
      .property('id', personId)          // element id == personId
      .property('accountId', accountId)
      .property('name', name)
      .property('email', email)
      .property('createdAt', createdAt)
      .property('updatedAt', updatedAt)
  )
  .project('id','personId','accountId','name','email','createdAt','updatedAt')
  .by(id())
  .by(values('personId'))
  .by(coalesce(values('accountId'), constant('')))
  .by(values('name'))
  .by(coalesce(values('email'), constant('')))
  .by(values('createdAt'))
  .by(values('updatedAt'))
";

        var bindings = new Dictionary<string, object> {
            ["personId"]  = personId,
            ["accountId"] = p.AccountId ?? "",
            ["name"]      = p.Name,
            ["email"]     = p.Email ?? "",
            ["createdAt"] = nowIso,
            ["updatedAt"] = nowIso
        };

        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, bindings);
        var mapped = MapPerson(rs.Single());
        return (mapped, ReadRu(rs));
    }

    public async Task<(Person?, double)> GetPersonAsync(string personId, CancellationToken ct = default)
    {
        // PK == ID
        var q = @"
g.V([personId, personId]).fold().
  coalesce(unfold(), V().hasLabel('person').hasId(personId))
  .limit(1)
  .project('id','personId','accountId','name','email','createdAt','updatedAt')
  .by(id())
  .by(values('personId'))
  .by(coalesce(values('accountId'), constant('')))
  .by(values('name'))
  .by(coalesce(values('email'), constant('')))
  .by(values('createdAt'))
  .by(values('updatedAt'))
";
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() { ["personId"] = personId });
        var person = rs.Any() ? MapPerson(rs.Single()) : null;
        return (person, ReadRu(rs));
    }

    public async Task<(bool, double)> DeletePersonAsync(string personId, CancellationToken ct = default)
    {
        var q = @"
g.V([personId, personId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personId)).bothE().drop();
g.V([personId, personId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personId)).drop()
";
        var rs = await _client.SubmitAsync<dynamic>(q, new() { ["personId"] = personId });
        return (true, ReadRu(rs));
    }

    // ---------------- Relationships ----------------

    public async Task<(bool, double)> FollowAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        var nowIso = Iso(DateTimeOffset.UtcNow);

        var q = @"
// Resolve vertices via point-reads (pk == id)
g.V([followerId, followerId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(followerId)).as('f')
 .V([followeeId, followeeId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(followeeId)).as('t')
 .coalesce(
   select('f').outE('follows').where(inV().as('t')).limit(1),
   addE('follows').from('f').to('t').property('createdAt', createdAt)
 )
";

        if (_maintainReverseEdge)
        {
            q += @"
; g.V([followeeId, followeeId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(followeeId)).as('t2')
   .V([followerId, followerId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(followerId)).as('f2')
   .coalesce(
     select('t2').outE('followedBy').where(inV().as('f2')).limit(1),
     addE('followedBy').from('t2').to('f2').property('createdAt', createdAt)
   )";
        }

        var rs = await _client.SubmitAsync<dynamic>(q, new() {
            ["followerId"] = followerId,
            ["followeeId"] = followeeId,
            ["createdAt"]  = nowIso
        });
        return (true, ReadRu(rs));
    }

    public async Task<(bool, double)> UnfollowAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        var q = @"
g.V([followerId, followerId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(followerId)).as('f')
 .V([followeeId, followeeId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(followeeId)).as('t')
 .coalesce(
   select('f').outE('follows').where(inV().as('t')).limit(1).drop(),
   constant('ok')
 )
";

        if (_maintainReverseEdge)
        {
            q += @"
; g.V([followeeId, followeeId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(followeeId)).as('t2')
   .V([followerId, followerId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(followerId)).as('f2')
   .coalesce(
     select('t2').outE('followedBy').where(inV().as('f2')).limit(1).drop(),
     constant('ok')
   )";
        }

        var rs = await _client.SubmitAsync<dynamic>(q, new() {
            ["followerId"] = followerId,
            ["followeeId"] = followeeId
        });
        return (true, ReadRu(rs));
    }

    public async Task<(bool, double)> IsFollowingAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        var q = @"
g.V([followerId, followerId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(followerId))
 .out('follows').hasId(followeeId)
 .limit(1).count()
";
        var rs = await _client.SubmitAsync<long>(q, new() {
            ["followerId"] = followerId, ["followeeId"] = followeeId
        });
        var exists = rs.FirstOrDefault() > 0;
        return (exists, ReadRu(rs));
    }

    // ---------------- Lists & counts ----------------

    public async Task<(IReadOnlyList<Person>, double)> GetFollowingAsync(string personId, int skip = 0, int take = 50, CancellationToken ct = default)
    {
        var startIdx = Math.Max(0, skip);
        var endIdx   = startIdx + take;

        var q = @"
g.V([personId, personId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personId))
  .out('follows')
  .range(startIdx, endIdx)
  .project('id','personId','accountId','name','email','createdAt','updatedAt')
  .by(id())
  .by(values('personId'))
  .by(coalesce(values('accountId'), constant('')))
  .by(values('name'))
  .by(coalesce(values('email'), constant('')))
  .by(values('createdAt'))
  .by(values('updatedAt'))
";
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() {
            ["personId"] = personId, ["startIdx"] = startIdx, ["endIdx"] = endIdx
        });
        return (rs.Select(MapPerson).ToList(), ReadRu(rs));
    }

    public async Task<(IReadOnlyList<Person>, double)> GetFollowersAsync(string personId, int skip = 0, int take = 50, CancellationToken ct = default)
    {
        var startIdx = Math.Max(0, skip);
        var endIdx   = startIdx + take;
        var edgeTraversal = _maintainReverseEdge ? "out('followedBy')" : "in('follows')";

        var q = $@"
g.V([personId, personId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personId))
  .{edgeTraversal}
  .range(startIdx, endIdx)
  .project('id','personId','accountId','name','email','createdAt','updatedAt')
  .by(id())
  .by(values('personId'))
  .by(coalesce(values('accountId'), constant('')))
  .by(values('name'))
  .by(coalesce(values('email'), constant('')))
  .by(values('createdAt'))
  .by(values('updatedAt'))
";
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() {
            ["personId"] = personId, ["startIdx"] = startIdx, ["endIdx"] = endIdx
        });
        return (rs.Select(MapPerson).ToList(), ReadRu(rs));
    }

    public async Task<(long, double)> CountFollowingAsync(string personId, CancellationToken ct = default)
    {
        var q = @"
g.V([personId, personId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personId))
 .out('follows').count()
";
        var rs = await _client.SubmitAsync<long>(q, new() { ["personId"] = personId });
        return (rs.FirstOrDefault(), ReadRu(rs));
    }

    public async Task<(long, double)> CountFollowersAsync(string personId, CancellationToken ct = default)
    {
        var edge = _maintainReverseEdge ? "out('followedBy')" : "in('follows')";
        var q = $@"
g.V([personId, personId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personId)).{edge}.count()
";
        var rs = await _client.SubmitAsync<long>(q, new() { ["personId"] = personId });
        return (rs.FirstOrDefault(), ReadRu(rs));
    }

    // ---------------- Suggestions & mutuals ----------------

    public async Task<(IReadOnlyList<(Person person, long mutuals)> suggestions, double ru)> SuggestToFollowAsync(string personId, int limit = 20, CancellationToken ct = default)
    {
        var q = @"
g.V([personId, personId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personId))
  .out('follows').aggregate('mine')
  .out('follows')
  .where(without('mine'))
  .where(id().is(neq(personId)))
  .groupCount()                 // group by vertex
  .order(local).by(values, decr)
  .limit(local, limit)
  .unfold()
  .project('person','score')
    .by(select(keys)
        .project('id','personId','accountId','name','email','createdAt','updatedAt')
        .by(id())
        .by(values('personId'))
        .by(coalesce(values('accountId'), constant('')))
        .by(values('name'))
        .by(coalesce(values('email'), constant('')))
        .by(values('createdAt'))
        .by(values('updatedAt')))
    .by(select(values))
";
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() {
            ["personId"] = personId, ["limit"] = limit
        });
        var list = rs.Select(d =>
        {
            var uDict = (Dictionary<string, object>)d["person"];
            var person = MapPerson(uDict);
            var mutuals = Convert.ToInt64(d["score"]);
            return (person, mutuals);
        }).ToList();
        return (list, ReadRu(rs));
    }

    public async Task<(IReadOnlyList<Person>, double)> MutualFollowsAsync(string personIdA, string personIdB, int limit = 50, CancellationToken ct = default)
    {
        var q = @"
g.V([personIdA, personIdA]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personIdA))
 .out('follows').aggregate('aF')
 .V([personIdB, personIdB]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personIdB))
 .out('follows')
 .where(within('aF'))
 .limit(limit)
 .project('id','personId','accountId','name','email','createdAt','updatedAt')
 .by(id())
 .by(values('personId'))
 .by(coalesce(values('accountId'), constant('')))
 .by(values('name'))
 .by(coalesce(values('email'), constant('')))
 .by(values('createdAt'))
 .by(values('updatedAt'))
";
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() {
            ["personIdA"] = personIdA, ["personIdB"] = personIdB, ["limit"] = limit
        });
        return (rs.Select(MapPerson).ToList(), ReadRu(rs));
    }

    // ---------------- Utility ----------------

    public async Task<(IReadOnlyList<string>, double)> GetFolloweeIdsAsync(string personId, int max = 500, CancellationToken ct = default)
    {
        var q = @"
g.V([personId, personId]).fold().coalesce(unfold(), V().hasLabel('person').hasId(personId))
  .out('follows')
  .limit(max)
  .id()
";
        var rs = await _client.SubmitAsync<string>(q, new() { ["personId"] = personId, ["max"] = max });
        return (rs.ToList(), ReadRu(rs));
    }

    // ----- helpers -----

    private static string Iso(DateTimeOffset dto) => dto.UtcDateTime.ToString("o");

    private static Person MapPerson(Dictionary<string, object> d) => new()
    {
        Id        = (string)d["id"],
        PersonId  = d.TryGetValue("personId", out var pid) ? (string)pid : (string)d["id"],
        AccountId = d.TryGetValue("accountId", out var aid) ? (string)aid : "",
        Name      = (string)d["name"],
        Email     = d.TryGetValue("email", out var e) && e is string s && s.Length > 0 ? s : null,
        CreatedAt = ToDto(d["createdAt"]),
        UpdatedAt = ToDto(d["updatedAt"])
    };

    private static DateTimeOffset ToDto(object v) =>
        v switch
        {
            DateTimeOffset dto => dto,
            DateTime dt => new DateTimeOffset(DateTime.SpecifyKind(dt, DateTimeKind.Utc)),
            string s => DateTimeOffset.Parse(s, null, DateTimeStyles.AdjustToUniversal),
            _ => DateTimeOffset.UtcNow
        };

    private static double ReadRu<TResult>(ResultSet<TResult> rs)
    {
        const string RuKey = "x-ms-total-request-charge";

        if (rs?.StatusAttributes == null) return 0d;
        if (!rs.StatusAttributes.TryGetValue(RuKey, out var v) || v is null) return 0d;

        switch (v)
        {
            case double d:   return d;
            case float f:    return f;
            case decimal m:  return (double)m;
            case long l:     return l;
            case int i:      return i;
            case string s when double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed):
                return parsed;
            case JsonElement je:
                if (je.ValueKind == JsonValueKind.Number && je.TryGetDouble(out var num))
                    return num;
                if (je.ValueKind == JsonValueKind.String &&
                    double.TryParse(je.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var strNum))
                    return strNum;
                break;
        }

        // Last-ditch attempt
        return double.TryParse(v.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var fallback)
            ? fallback
            : 0d;
    }
}
