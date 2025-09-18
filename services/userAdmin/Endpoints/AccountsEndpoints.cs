using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using UserAdmin.Contracts;
using UserAdmin.Extensions;
using UserAdmin.Infrastructure;
using UserAdmin.Models;

namespace UserAdmin.Endpoints;

public static class AccountsEndpoints
{
    public static RouteGroupBuilder MapAccountsEndpoints(this IEndpointRouteBuilder endpoints)
    {
        if (endpoints is null)
        {
            throw new ArgumentNullException(nameof(endpoints));
        }

        var group = endpoints.MapGroup("/accounts").WithTags("Accounts");
        group.MapPost("/", CreateAccountAsync);
        group.MapPut("/{id}", UpdateAccountAsync);
        group.MapGet("/{id}", GetAccountAsync);
        group.MapDelete("/{id}", DeleteAccountAsync);

        return group;
    }

    private static async Task<IResult> CreateAccountAsync(
        IAccountsRepository accountsRepository,
        IPersonRepository personRepository,
        HttpContext httpContext,
        AccountCreateDto dto)
    {
        var now = DateTimeOffset.UtcNow;
        var totalRequestCharge = 0d;

        var account = new Account
        {
            Id = Guid.NewGuid().ToString(),
            AccountId = Guid.NewGuid().ToString(),
            Name = dto.Name,
            Email = dto.Email ?? string.Empty,
            CreatedAt = now,
            UpdatedAt = now
        };

        var (createdAccount, etag, accountRequestCharge) = await accountsRepository.CreateAsync(account, httpContext.RequestAborted);
        totalRequestCharge += accountRequestCharge;

        try
        {
            var person = new Person
            {
                Id = account.Id,
                AccountId = createdAccount.AccountId,
                PersonId = Guid.NewGuid().ToString(),
                Name = dto.Name,
                Email = dto.Email ?? string.Empty,
                CreatedAt = now,
                UpdatedAt = now
            };

            var (createdPerson, personRequestCharge) = await personRepository.UpsertPersonAsync(person, httpContext.RequestAborted);
            totalRequestCharge += personRequestCharge;

            httpContext.Response.SetRequestCharge(totalRequestCharge);

            return Results.Created($"/users/{createdAccount.AccountId}", new
            {
                account = createdAccount,
                person = createdPerson
            });
        }
        catch (Exception ex)
        {
            try
            {
                var (deleted, deleteCharge) = await accountsRepository.DeleteAsync(account.Id, account.AccountId, etag, httpContext.RequestAborted);
                if (deleted)
                {
                    totalRequestCharge += deleteCharge;
                }
            }
            catch
            {
                // ignored - surface original error to caller
            }

            httpContext.Response.SetRequestCharge(totalRequestCharge);
            return Results.Problem(
                detail: ex.Message,
                statusCode: StatusCodes.Status500InternalServerError);
        }
    }

    private static async Task<IResult> UpdateAccountAsync(
        IPersonRepository repository,
        HttpContext httpContext,
        string personId,
        string id,
        AccountUpdateDto dto)
    {
        var now = DateTimeOffset.UtcNow;

        var (existingPerson, readRequestCharge) = await repository.GetPersonAsync(id, httpContext.RequestAborted);

        var person = existingPerson is null
            ? new Person
            {
                Id = id,
                AccountId = dto.AccountId,
                PersonId = personId,
                Name = dto.Name,
                Email = dto.Email ?? string.Empty,
                CreatedAt = now,
                UpdatedAt = now
            }
            : new Person
            {
                Id = id,
                AccountId = dto.AccountId,
                PersonId = personId,
                Name = dto.Name ?? existingPerson.Name,
                Email = dto.Email ?? existingPerson.Email,
                CreatedAt = existingPerson.CreatedAt,
                UpdatedAt = now
            };

        var (updatedPerson, upsertRequestCharge) = await repository.UpsertPersonAsync(person, httpContext.RequestAborted);
        httpContext.Response.SetRequestCharge(readRequestCharge + upsertRequestCharge);

        return Results.Ok(updatedPerson);
    }

    private static async Task<IResult> GetAccountAsync(
        IPersonRepository repository,
        HttpContext httpContext,
        string id)
    {
        var (person, requestCharge) = await repository.GetPersonAsync(id, httpContext.RequestAborted);
        httpContext.Response.SetRequestCharge(requestCharge);

        return person is null ? Results.NotFound() : Results.Ok(person);
    }

    private static async Task<IResult> DeleteAccountAsync(
        IPersonRepository repository,
        HttpContext httpContext,
        string id)
    {
        var (deleted, requestCharge) = await repository.DeletePersonAsync(id, httpContext.RequestAborted);
        httpContext.Response.SetRequestCharge(requestCharge);

        return deleted ? Results.NoContent() : Results.NotFound();
    }
}
