using Gremlin.Net.Driver;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
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

    // Name of the vertex property configured as the container's partition key
    private readonly string _pkName;

    // Function to derive the partition key value from a personId. Default assumes pk == id.
    private readonly Func<string, string> _pkForId;

    // Whether to maintain reverse edges for fast followers queries
    private readonly bool _maintainReverseEdge;

    /// <param name="partitionKeyPropertyName">
    /// The property name used as the partition key in your graph container (default: "personId").
    /// </param>
    /// <param name="pkForId">
    /// Function that maps a vertex id to its partition key value. Defaults to identity (id == pk).
    /// </param>
    /// <param name="maintainReverseEdge">
    /// If true, writes a mirrored "followedBy" edge for fast followers queries.
    /// </param>
    public PersonRepository(
        GremlinClient client,
        string partitionKeyPropertyName = "PersonId",
        Func<string, string>? pkForId = null,
        bool maintainReverseEdge = true)
    {
        _client = client;
        _pkName = partitionKeyPropertyName;
        _pkForId = pkForId ?? (id => id);
        _maintainReverseEdge = maintainReverseEdge;
    }

    public async Task<(Person, double)> UpsertPersonAsync(Person p, CancellationToken ct = default)
    {
        var uid = p.Id ?? throw new ArgumentNullException(nameof(p.Id));
         var pk  = _pkForId(uid);
         
        // NOTE: property key names (like the PK) cannot be parameterized as bindings; we inline the string.
        var q = $@"
g.V([pid, uid]).fold().
  coalesce(
    unfold()
      .property('displayName', name)
      .property('email', email)
      .property('updatedAt', updated),
    addV('person')
      .property('{_pkName}', pid)
      .property('id', uid)
      .property('displayName', name)
      .property('email', email)
      .property('createdAt', created)
      .property('updatedAt', updated)
  )
  .project('id','displayName','email','createdAt','updatedAt')
  .by(values('id'))
  .by(values('displayName'))
  .by(coalesce(values('email'), constant('')))
  .by(values('createdAt'))
  .by(values('updatedAt'))
";

        var u = new Dictionary<string, object> {
            ["pid"]     = uid,                 // PK value
            ["uid"]     = uid,                // vertex id
            ["name"]    = p.DisplayName,
            ["email"]   = p.Email ?? "",      // primitives only
            ["created"] = Iso(p.CreatedAt),   // ISO strings
            ["updated"] = Iso(p.UpdatedAt)
        };

        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, u);
        var mapped = MapPerson(rs.Single());
        return (mapped, ReadRu(rs));
    }

    public async Task<(Person?, double)> GetPersonAsync(string personId, CancellationToken ct = default)
    {
        var pk = _pkForId(personId);

        var q = @"
g.V([pk, uid])
  .project('id','displayName','email','createdAt','updatedAt')
  .by(values('id'))
  .by(values('displayName'))
  .by(coalesce(values('email'), constant('')))
  .by(values('createdAt'))
  .by(values('updatedAt'))
";
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() { ["uid"] = personId, ["pk"] = pk });
        var person = rs.Any() ? MapPerson(rs.Single()) : null;
        return (person, ReadRu(rs));
    }

    public async Task<(bool, double)> DeletePersonAsync(string personId, CancellationToken ct = default)
    {
        var pk = _pkForId(personId);
        var q = "g.V([pk, uid]).bothE().drop(); g.V([pk, uid]).drop()";
        var rs = await _client.SubmitAsync<dynamic>(q, new() { ["uid"] = personId, ["pk"] = pk });
        return (true, ReadRu(rs));
    }

    // ---------------- Relationships ----------------

    public async Task<(bool, double)> FollowAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        var fpk = _pkForId(followerId);
        var tpk = _pkForId(followeeId);
        var now = DateTimeOffset.UtcNow;

        var q = @"
// ensure forward edge follower -> followee
g.V([fpk,f]).as('f')
 .V([tpk,t]).as('t')
 .coalesce(
   select('t').inE('follows').where(outV().as('f')),
   addE('follows').from('f').to('t').property('createdAt', createdAt)
 )
";

        if (_maintainReverseEdge)
        {
            q += @"
; g.V([tpk,t]).as('t2')
   .V([fpk,f]).as('f2')
   .coalesce(
     select('f2').inE('followedBy').where(outV().as('t2')),
     addE('followedBy').from('t2').to('f2').property('createdAt', createdAt)
   )";
        }

        var rs = await _client.SubmitAsync<dynamic>(q, new() {
            ["f"] = followerId, ["fpk"] = fpk,
            ["t"] = followeeId, ["tpk"] = tpk,
            ["createdAt"] = Iso(now)
        });
        return (true, ReadRu(rs));
    }

    public async Task<(bool, double)> UnfollowAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        var fpk = _pkForId(followerId);
        var tpk = _pkForId(followeeId);

        var q = @"
g.V([fpk,f]).as('f')
 .V([tpk,t]).as('t')
 .coalesce(
   select('f').outE('follows').where(inV().as('t')).limit(1).drop(),
   constant('ok')
 )
";

        if (_maintainReverseEdge)
        {
            q += @"
; g.V([tpk,t]).as('t2')
   .V([fpk,f]).as('f2')
   .coalesce(
     select('t2').outE('followedBy').where(inV().as('f2')).limit(1).drop(),
     constant('ok')
   )";
        }

        var rs = await _client.SubmitAsync<dynamic>(q, new() { ["f"] = followerId, ["fpk"] = fpk, ["t"] = followeeId, ["tpk"] = tpk });
        return (true, ReadRu(rs));
    }

    public async Task<(bool, double)> IsFollowingAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        var fpk = _pkForId(followerId);

        var q = @"
g.V([fpk,f]).out('follows')
 .where(id().is(t))
 .limit(1).count()
";
        var rs = await _client.SubmitAsync<long>(q, new() { ["f"] = followerId, ["fpk"] = fpk, ["t"] = followeeId });
        var exists = rs.FirstOrDefault() > 0;
        return (exists, ReadRu(rs));
    }

    // ---------------- Lists & counts ----------------

    public async Task<(IReadOnlyList<Person>, double)> GetFollowingAsync(string personId, int skip = 0, int take = 50, CancellationToken ct = default)
    {
        var pk = _pkForId(personId);
        var q = @"
g.V([upk,u]).out('follows')
  .range(skip, skip + take)
  .project('id','displayName','email','createdAt','updatedAt')
  .by(values('id'))
  .by(values('displayName'))
  .by(coalesce(values('email'), constant('')))
  .by(values('createdAt'))
  .by(values('updatedAt'))
";
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() {
            ["u"] = personId, ["upk"] = pk, ["skip"] = Math.Max(0, skip), ["take"] = take
        });
        return (rs.Select(MapPerson).ToList(), ReadRu(rs));
    }

    public async Task<(IReadOnlyList<Person>, double)> GetFollowersAsync(string personId, int skip = 0, int take = 50, CancellationToken ct = default)
    {
        var pk = _pkForId(personId);

        var q = _maintainReverseEdge ? @"
g.V([upk,u]).out('followedBy')
  .range(skip, skip + take)
  .project('id','displayName','email','createdAt','updatedAt')
  .by(values('id'))
  .by(values('displayName'))
  .by(coalesce(values('email'), constant('')))
  .by(values('createdAt'))
  .by(values('updatedAt'))
"
:
@"
g.V([upk,u]).in('follows')
  .range(skip, skip + take)
  .project('id','displayName','email','createdAt','updatedAt')
  .by(values('id'))
  .by(values('displayName'))
  .by(coalesce(values('email'), constant('')))
  .by(values('createdAt'))
  .by(values('updatedAt'))
";

        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() {
            ["u"] = personId, ["upk"] = pk, ["skip"] = Math.Max(0, skip), ["take"] = take
        });
        return (rs.Select(MapPerson).ToList(), ReadRu(rs));
    }

    public async Task<(long, double)> CountFollowingAsync(string personId, CancellationToken ct = default)
    {
        var pk = _pkForId(personId);
        var rs = await _client.SubmitAsync<long>("g.V([upk,u]).out('follows').count()", new() { ["u"] = personId, ["upk"] = pk });
        return (rs.FirstOrDefault(), ReadRu(rs));
    }

    public async Task<(long, double)> CountFollowersAsync(string personId, CancellationToken ct = default)
    {
        var pk = _pkForId(personId);
        var q = _maintainReverseEdge
            ? "g.V([upk,u]).out('followedBy').count()"
            : "g.V([upk,u]).in('follows').count()";
        var rs = await _client.SubmitAsync<long>(q, new() { ["u"] = personId, ["upk"] = pk });
        return (rs.FirstOrDefault(), ReadRu(rs));
    }

    // ---------------- Suggestions & mutuals ----------------

    public async Task<(IReadOnlyList<(Person person, long mutuals)> suggestions, double ru)> SuggestToFollowAsync(string personId, int limit = 20, CancellationToken ct = default)
    {
        var pk = _pkForId(personId);

        // Uses a point-read path when pk == id; otherwise falls back to a cross-partition by-id lookup.
        var q = @"
g.V([upk,u])
  .out('follows').aggregate('mine')
  .out('follows')
  .where(neq([upk,u]))         // not me
  .where(without('mine'))      // not already following
  .groupCount().by(id())       // candidate -> mutual count
  .order(local).by(values, decr)
  .limit(local, limit)
  .unfold()
  .project('person','score')
    .by(select(keys)
        .coalesce(
           unfold().V([it,it]),          // fast path if pk==id
           V().has('id', select(keys))   // fallback if pk differs
        )
        .project('id','displayName','email','createdAt','updatedAt')
        .by(values('id'))
        .by(values('displayName'))
        .by(coalesce(values('email'), constant('')))
        .by(values('createdAt'))
        .by(values('updatedAt')))
    .by(select(values))
";
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() { ["u"] = personId, ["upk"] = pk, ["limit"] = limit });
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
        var apk = _pkForId(personIdA);
        var bpk = _pkForId(personIdB);

        var q = @"
g.V([apk,a]).out('follows').aggregate('aF')
 .V([bpk,b]).out('follows')
 .where(within('aF'))
 .limit(limit)
 .project('id','displayName','email','createdAt','updatedAt')
 .by(values('id'))
 .by(values('displayName'))
 .by(coalesce(values('email'), constant('')))
 .by(values('createdAt'))
 .by(values('updatedAt'))
";
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() { ["a"] = personIdA, ["apk"] = apk, ["b"] = personIdB, ["bpk"] = bpk, ["limit"] = limit });
        return (rs.Select(MapPerson).ToList(), ReadRu(rs));
    }

    // ---------------- Utility ----------------

    public async Task<(IReadOnlyList<string>, double)> GetFolloweeIdsAsync(string personId, int max = 500, CancellationToken ct = default)
    {
        var pk = _pkForId(personId);
        var q = @"
g.V([upk,u]).out('follows')
  .limit(max)
  .values('id')
";
        var rs = await _client.SubmitAsync<string>(q, new() { ["u"] = personId, ["upk"] = pk, ["max"] = max });
        return (rs.ToList(), ReadRu(rs));
    }

    // ----- helpers -----

    private static string Iso(DateTimeOffset dto) => dto.UtcDateTime.ToString("o");

    private static Person MapPerson(Dictionary<string, object> d) => new(
        Id: (string)d["id"],
        DisplayName: (string)d["displayName"],
        Email: d.TryGetValue("email", out var e) && e is string s && s.Length > 0 ? s : null, // "" -> null
        CreatedAt: ToDto(d["createdAt"]),
        UpdatedAt: ToDto(d["updatedAt"])
    );

    private static DateTimeOffset ToDto(object v) =>
        v switch
        {
            DateTimeOffset dto => dto,
            DateTime dt => new DateTimeOffset(DateTime.SpecifyKind(dt, DateTimeKind.Utc)),
            string s => DateTimeOffset.Parse(s, null, System.Globalization.DateTimeStyles.AdjustToUniversal),
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
