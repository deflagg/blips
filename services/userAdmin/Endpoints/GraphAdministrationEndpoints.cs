using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using UserAdmin.Extensions;
using UserAdmin.Infrastructure;

namespace UserAdmin.Endpoints;

public static class GraphAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapGraphAdministrationEndpoints(this IEndpointRouteBuilder endpoints)
    {
        if (endpoints is null)
        {
            throw new ArgumentNullException(nameof(endpoints));
        }

        endpoints.MapDelete("/DeleteGraph", DeleteGraphAsync).WithTags("Graph");
        return endpoints;
    }

    private static async Task<IResult> DeleteGraphAsync(
        IAccountsRepository accountsRepository,
        IPersonRepository personsRepository,
        HttpContext httpContext,
        int pageSize = 200,
        CancellationToken cancellationToken = default)
    {
        var totalRequestCharge = 0d;

        var graphRequestCharge = await personsRepository.DeleteGraphAsync(cancellationToken);
        totalRequestCharge += graphRequestCharge;

        long deletedAccounts = 0;
        double accountsRequestCharge = 0d;

        string? continuation = null;
        do
        {
            var (items, nextContinuation, listRequestCharge) = await accountsRepository.ListAsync(pageSize, continuation, cancellationToken);
            accountsRequestCharge += listRequestCharge;

            if (items.Count == 0)
            {
                continuation = nextContinuation;
                continue;
            }

            foreach (var account in items)
            {
                var (deleted, deleteRequestCharge) = await accountsRepository.DeleteAsync(account.Id, account.AccountId, null, cancellationToken);
                accountsRequestCharge += deleteRequestCharge;
                if (deleted)
                {
                    deletedAccounts++;
                }
            }

            continuation = nextContinuation;
        }
        while (!string.IsNullOrEmpty(continuation));

        totalRequestCharge += accountsRequestCharge;
        httpContext.Response.SetRequestCharge(totalRequestCharge);

        var response = new
        {
            deleted = "graph+accounts",
            graph = new { ru = graphRequestCharge },
            accounts = new { deleted = deletedAccounts, ru = accountsRequestCharge },
            ru = totalRequestCharge
        };

        return Results.Ok(response);
    }
}
