using System;
using System.Net.Http;
using Azure.Identity;
using Gremlin.Net.Driver;
using Gremlin.Net.Structure.IO.GraphSON;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi.Models;
using UserAdmin.Infrastructure;
using UserAdmin.Services;

namespace UserAdmin.DependencyInjection;

public static class ServiceCollectionExtensions
{
    public const string AllowAllCorsPolicy = "AllowAll";

    public static IServiceCollection AddApplicationServices(this IServiceCollection services, IConfiguration configuration)
    {
        if (services is null)
        {
            throw new ArgumentNullException(nameof(services));
        }

        if (configuration is null)
        {
            throw new ArgumentNullException(nameof(configuration));
        }

        services.AddEndpointsApiExplorer();
        services.AddSwaggerGen(options =>
        {
            options.SwaggerDoc("v1", new OpenApiInfo
            {
                Title = "UserAdmin API",
                Version = "v1"
            });
        });

        services.AddCors(options =>
        {
            options.AddPolicy(AllowAllCorsPolicy, policy =>
            {
                policy
                    .AllowAnyOrigin()
                    .AllowAnyMethod()
                    .AllowAnyHeader()
                    .WithExposedHeaders(
                        "x-ms-request-charge",
                        "ETag",
                        "Location",
                        "x-ms-activity-id",
                        "x-ms-request-duration");
            });
        });

        services
            .AddHealthChecks()
            .AddCheck("self", () => HealthCheckResult.Healthy(), tags: new[] { "ready" });

        services.Configure<CosmosOptions>(configuration.GetSection("Cosmos"));
        services.AddSingleton(CreateCosmosClient);

        services.Configure<GremlinOptions>(configuration.GetSection("PersonGraphDB"));
        services.AddSingleton(CreateGremlinClient);

        services.AddSingleton<IAccountsRepository, AccountsRepository>();
        services.AddSingleton<ICosmosInitializer, CosmosInitializer>();
        services.AddSingleton<IPersonRepository, PersonRepository>();
        services.AddSingleton<GraphSeeder>();

        return services;
    }

    private static CosmosClient CreateCosmosClient(IServiceProvider provider)
    {
        var options = provider.GetRequiredService<IOptions<CosmosOptions>>().Value;

        var clientOptions = new CosmosClientOptions
        {
            ApplicationName = "Blips.UserAdmin",
            ConnectionMode = ConnectionMode.Gateway,
            LimitToEndpoint = true,
            SerializerOptions = new CosmosSerializationOptions
            {
                PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
            }
        };

        var endpoint = options.Endpoint;
        if (!string.IsNullOrWhiteSpace(endpoint) &&
            (endpoint.Contains("localhost", StringComparison.OrdinalIgnoreCase) ||
             endpoint.Contains("127.0.0.1", StringComparison.OrdinalIgnoreCase)))
        {
            clientOptions.HttpClientFactory = () =>
            {
                var handler = new HttpClientHandler
                {
                    UseProxy = false,
                    Proxy = null,
                    ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
                };

                return new HttpClient(handler, disposeHandler: true)
                {
                    Timeout = TimeSpan.FromSeconds(65)
                };
            };

            return new CosmosClient(endpoint, options.Key, clientOptions);
        }

        return new CosmosClient(endpoint, new DefaultAzureCredential(), clientOptions);
    }

    private static GremlinClient CreateGremlinClient(IServiceProvider provider)
    {
        var settings = provider.GetRequiredService<IOptions<GremlinOptions>>().Value;
        var username = $"/dbs/{settings.Common.DatabaseId}/colls/{settings.Common.GraphId}";

        if (settings.Mode == GremlinMode.Emulator)
        {
            var emulator = settings.Emulator ?? throw new InvalidOperationException("Emulator configuration is required when Gremlin mode is set to Emulator.");

            var server = new GremlinServer(
                hostname: emulator.Host,
                port: emulator.Port,
                enableSsl: false,
                username: username,
                password: emulator.AuthKey);

            return new GremlinClient(server, new GraphSON2MessageSerializer());
        }

        var cloud = settings.Cloud ?? throw new InvalidOperationException("Cloud configuration is required when Gremlin mode is set to Cloud.");
        var credential = new DefaultAzureCredential();
        var token = credential.GetToken(new Azure.Core.TokenRequestContext(new[] { "https://cosmos.azure.com/.default" })).Token;

        var gremlinServer = new GremlinServer(
            $"{cloud.AccountName}.gremlin.cosmos.azure.com",
            443,
            enableSsl: true,
            username: username,
            password: token);

        return new GremlinClient(gremlinServer, new GraphSON2MessageSerializer());
    }
}
