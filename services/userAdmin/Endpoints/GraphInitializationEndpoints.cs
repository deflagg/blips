using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Routing;
using UserAdmin.Contracts;
using UserAdmin.Extensions;
using UserAdmin.Services;

namespace UserAdmin.Endpoints;

public static class GraphInitializationEndpoints
{
    public static IEndpointRouteBuilder MapGraphInitializationEndpoints(this IEndpointRouteBuilder endpoints)
    {
        if (endpoints is null)
        {
            throw new ArgumentNullException(nameof(endpoints));
        }

        endpoints.MapGet("/initializeData", InitializeGraphAsync).WithTags("Init");
        return endpoints;
    }

    private static async Task<IResult> InitializeGraphAsync(
        GraphSeeder seeder,
        HttpContext httpContext,
        [AsParameters] GraphSeedRequest request,
        CancellationToken cancellationToken = default)
    {
        var result = await seeder.SeedAsync(request, cancellationToken);
        httpContext.Response.SetRequestCharge(result.TotalRequestCharge);

        return Results.Ok(new
        {
            result.Message,
            result.Stats
        });
    }
}
