using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using UserAdmin.Extensions;
using UserAdmin.Infrastructure;

namespace UserAdmin.Endpoints;

public static class GraphEndpoints
{
    public static IEndpointRouteBuilder MapGraphEndpoints(this IEndpointRouteBuilder endpoints)
    {
        if (endpoints is null)
        {
            throw new ArgumentNullException(nameof(endpoints));
        }

        endpoints.MapGet("/graph", GetGraphAsync).WithTags("Graph");
        return endpoints;
    }

    private static async Task<IResult> GetGraphAsync(
        IPersonRepository repository,
        HttpContext httpContext,
        int vertexLimit = 2000,
        int edgeLimit = 10000)
    {
        var (persons, edges, requestCharge) = await repository.GetGraphAsync(vertexLimit, edgeLimit, httpContext.RequestAborted);
        httpContext.Response.SetRequestCharge(requestCharge);

        var payload = new
        {
            nodes = persons.Select(p => new
            {
                id = p.PersonId,
                label = p.Name,
                accountId = p.AccountId,
                email = p.Email
            }),
            edges = edges.Select(e => new
            {
                source = e.source,
                target = e.target,
                createdAt = e.createdAt
            })
        };

        return Results.Ok(payload);
    }
}
