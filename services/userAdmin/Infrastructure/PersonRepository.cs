using Gremlin.Net.Driver;
using System.Collections.Generic;
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

    // “People you may know” & friends you both follow
    Task<(IReadOnlyList<(Person person, long mutuals)> suggestions, double ru)> SuggestToFollowAsync(string personId, int limit = 20, CancellationToken ct = default);
    Task<(IReadOnlyList<Person> persons, double ru)> MutualFollowsAsync(string personIdA, string personIdB, int limit = 50, CancellationToken ct = default);

    // Utility for timeline joins (use with your existing Cosmos NoSQL blip repo)
    Task<(IReadOnlyList<string> followeeIds, double ru)> GetFolloweeIdsAsync(string personId, int max = 500, CancellationToken ct = default);
}

public sealed class PersonRepository : IPersonRepository
{
    private readonly GremlinClient _client;
    private readonly bool _maintainReverseEdge;

    /// <param name="maintainReverseEdge">
    /// If true, writes a mirrored "followedBy" edge for fast followers queries.
    /// </param>
    public PersonRepository(GremlinClient client, bool maintainReverseEdge = true)
    {
        _client = client;
        _maintainReverseEdge = maintainReverseEdge;
    }


    public async Task<(Person, double)> UpsertPersonAsync(Person p, CancellationToken ct = default)
    {
        var q = """
        g.V([uid, uid]).fold().
          coalesce(
            unfold()
              .property('displayName', name)
              .property('email', email)
              .property('updatedAt', updated),
            addV('person')
              .property('id', uid)
              .property('personId', uid)
              .property('displayName', name)
              .property('email', email)
              .property('createdAt', created)
              .property('updatedAt', updated)
          )
          .project('id','displayName','email','createdAt','updatedAt')
          .by(values('id'))
          .by(values('displayName'))
          .by(coalesce(values('email'), constant(null)))
          .by(values('createdAt'))
          .by(values('updatedAt'))
        """;

        var u = new Dictionary<string, object> {
            ["uid"] = p.Id,
            ["name"] = p.DisplayName,
            ["email"] = (object?)p.Email ?? DBNull.Value,
            ["created"] = p.CreatedAt,
            ["updated"] = p.UpdatedAt
        };

        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, u);
        var mapped = MapPerson(rs.Single());
        return (mapped, ReadRu(rs));
    }

    public async Task<(Person?, double)> GetPersonAsync(string personId, CancellationToken ct = default)
    {
        var q = """
        g.V([uid, uid])
          .project('id','displayName','email','createdAt','updatedAt')
          .by(values('id'))
          .by(values('displayName'))
          .by(coalesce(values('email'), constant(null)))
          .by(values('createdAt'))
          .by(values('updatedAt'))
        """;
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() { ["uid"] = personId });
        var person = rs.Any() ? MapPerson(rs.Single()) : null;
        return (person, ReadRu(rs));
    }

    public async Task<(bool, double)> DeletePersonAsync(string personId, CancellationToken ct = default)
    {
        // Drop edges first to avoid dangling references.
        var q = "g.V([uid, uid]).bothE().drop(); g.V([uid, uid]).drop()";
        var rs = await _client.SubmitAsync<dynamic>(q, new() { ["uid"] = personId });
        return (true, ReadRu(rs));
    }

    // ---------------- Relationships ----------------

    public async Task<(bool, double)> FollowAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        var now = DateTimeOffset.UtcNow;

        var q = """
        // ensure forward edge follower -> followee
        g.V([f,f]).as('f')
          .V([t,t])
          .coalesce(
            inE('follows').where(outV().as('f')),
            addE('follows').from('f').property('createdAt', createdAt)
          )
        """ + (_maintainReverseEdge ? """
        // optional reverse edge for fast followers (followee -> follower)
        ; g.V([t,t]).as('t')
            .V([f,f])
            .coalesce(
              inE('followedBy').where(outV().as('t')),
              addE('followedBy').from('t').property('createdAt', createdAt)
            )
        """ : "");

        var rs = await _client.SubmitAsync<dynamic>(q, new() {
            ["f"] = followerId, ["t"] = followeeId, ["createdAt"] = now
        });
        return (true, ReadRu(rs));
    }

    public async Task<(bool, double)> UnfollowAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        var q = """
        g.V([f,f]).outE('follows')
          .where(inV().has('id', t).has('personId', t))
          .limit(1).drop()
        """ + (_maintainReverseEdge ? """
        ; g.V([t,t]).outE('followedBy')
            .where(inV().has('id', f).has('personId', f))
            .limit(1).drop()
        """ : "");

        var rs = await _client.SubmitAsync<dynamic>(q, new() { ["f"] = followerId, ["t"] = followeeId });
        return (true, ReadRu(rs));
    }

    public async Task<(bool, double)> IsFollowingAsync(string followerId, string followeeId, CancellationToken ct = default)
    {
        var q = """
        g.V([f,f]).out('follows')
          .has('id', t).has('personId', t)
          .limit(1).count()
        """;
        var rs = await _client.SubmitAsync<long>(q, new() { ["f"] = followerId, ["t"] = followeeId });
        var exists = rs.FirstOrDefault() > 0;
        return (exists, ReadRu(rs));
    }

    // ---------------- Lists & counts ----------------

    public async Task<(IReadOnlyList<Person>, double)> GetFollowingAsync(string personId, int skip = 0, int take = 50, CancellationToken ct = default)
    {
        var q = """
        g.V([u,u]).out('follows')
          .order().by('createdAt', decr) // newest follows first
          .range(skip, skip + take)
          .project('id','displayName','email','createdAt','updatedAt')
          .by(values('id'))
          .by(values('displayName'))
          .by(coalesce(values('email'), constant(null)))
          .by(values('createdAt'))
          .by(values('updatedAt'))
        """;
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() {
            ["u"] = personId, ["skip"] = Math.Max(0, skip), ["take"] = take
        });
        return (rs.Select(MapPerson).ToList(), ReadRu(rs));
    }

    public async Task<(IReadOnlyList<Person>, double)> GetFollowersAsync(string personId, int skip = 0, int take = 50, CancellationToken ct = default)
    {
        // If reverse edges are maintained, use out('followedBy') to stay partition-local to the target.
        var q = _maintainReverseEdge ? """
        g.V([u,u]).out('followedBy')
          .order().by('createdAt', decr)
          .range(skip, skip + take)
          .project('id','displayName','email','createdAt','updatedAt')
          .by(values('id'))
          .by(values('displayName'))
          .by(coalesce(values('email'), constant(null)))
          .by(values('createdAt'))
          .by(values('updatedAt'))
        """ : """
        g.V([u,u]).in('follows')          // cross-partition; higher RU
          .order().by('createdAt', decr)
          .range(skip, skip + take)
          .project('id','displayName','email','createdAt','updatedAt')
          .by(values('id'))
          .by(values('displayName'))
          .by(coalesce(values('email'), constant(null)))
          .by(values('createdAt'))
          .by(values('updatedAt'))
        """;

        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() {
            ["u"] = personId, ["skip"] = Math.Max(0, skip), ["take"] = take
        });
        return (rs.Select(MapPerson).ToList(), ReadRu(rs));
    }

    public async Task<(long, double)> CountFollowingAsync(string personId, CancellationToken ct = default)
    {
        var rs = await _client.SubmitAsync<long>("g.V([u,u]).out('follows').count()", new() { ["u"] = personId });
        return (rs.FirstOrDefault(), ReadRu(rs));
    }

    public async Task<(long, double)> CountFollowersAsync(string personId, CancellationToken ct = default)
    {
        var q = _maintainReverseEdge
            ? "g.V([u,u]).out('followedBy').count()"
            : "g.V([u,u]).in('follows').count()";
        var rs = await _client.SubmitAsync<long>(q, new() { ["u"] = personId });
        return (rs.FirstOrDefault(), ReadRu(rs));
    }

    // ---------------- Suggestions & mutuals ----------------

    // friends-of-friends not already followed; ranked by mutual count
    public async Task<(IReadOnlyList<(Person person, long mutuals)> suggestions, double ru)> SuggestToFollowAsync(string personId, int limit = 20, CancellationToken ct = default)
    {
        var q = """
        g.V([u,u])
          .out('follows').aggregate('mine')
          .out('follows')
          .where(neq([u,u]))          // not me
          .where(without('mine'))     // not already following
          .groupCount().by(id())      // candidate -> mutual count
          .order(local).by(values, decr)
          .limit(local, limit)
          .unfold()
          .project('person','score')
            .by(select(keys)
                .coalesce(
                   unfold().V([it,it]),          // partition-aware point read (pk==id)
                   V().has('id', select(keys))   // fallback if pk diverges
                )
                .project('id','displayName','email','createdAt','updatedAt')
                .by(values('id'))
                .by(values('displayName'))
                .by(coalesce(values('email'), constant(null)))
                .by(values('createdAt'))
                .by(values('updatedAt')))
            .by(select(values))
        """;
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() { ["u"] = personId, ["limit"] = limit });
        var list = rs.Select(d =>
        {
            var uDict = (Dictionary<string, object>)d["person"];
            var person = MapPerson(uDict);
            var mutuals = Convert.ToInt64(d["score"]);
            return (person, mutuals);
        }).ToList();
        return (list, ReadRu(rs));
    }

    // persons that both A and B follow (mutual followees)
    public async Task<(IReadOnlyList<Person>, double)> MutualFollowsAsync(string personIdA, string personIdB, int limit = 50, CancellationToken ct = default)
    {
        var q = """
        g.V([a,a]).out('follows').aggregate('aF')
         .V([b,b]).out('follows')
         .where(within('aF'))
         .limit(limit)
         .project('id','displayName','email','createdAt','updatedAt')
         .by(values('id'))
         .by(values('displayName'))
         .by(coalesce(values('email'), constant(null)))
         .by(values('createdAt'))
         .by(values('updatedAt'))
        """;
        var rs = await _client.SubmitAsync<Dictionary<string, object>>(q, new() { ["a"] = personIdA, ["b"] = personIdB, ["limit"] = limit });
        return (rs.Select(MapPerson).ToList(), ReadRu(rs));
    }

    // ---------------- Utility ----------------

    // Use this to join against your existing Cosmos NoSQL blip repo:
    public async Task<(IReadOnlyList<string>, double)> GetFolloweeIdsAsync(string personId, int max = 500, CancellationToken ct = default)
    {
        var q = """
        g.V([u,u]).out('follows')
          .limit(max)
          .values('id')
        """;
        var rs = await _client.SubmitAsync<string>(q, new() { ["u"] = personId, ["max"] = max });
        return (rs.ToList(), ReadRu(rs));
    }

    // ----- helpers -----

    private static Person MapPerson(Dictionary<string, object> d) => new(
        Id: (string)d["id"],
        DisplayName: (string)d["displayName"],
        Email: d.TryGetValue("email", out var e) ? e as string : null,
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

    private static double ReadRu<TResult>(ResultSet<TResult> rs) =>
        rs.StatusAttributes.TryGetValue("x-ms-total-request-charge", out var v) ? Convert.ToDouble(v) : 0d;
}
