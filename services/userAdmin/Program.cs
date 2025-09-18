using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.DependencyInjection;
using UserAdmin.DependencyInjection;
using UserAdmin.Endpoints;
using UserAdmin.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrelFromConfiguration();
builder.Services.AddApplicationServices(builder.Configuration);

var app = builder.Build();

app.Logger.LogInformation("ENV={Env}", app.Environment.EnvironmentName);

await app.Services.GetRequiredService<ICosmosInitializer>().InitializeAsync();

app.UseCors(ServiceCollectionExtensions.AllowAllCorsPolicy);
app.UseSwagger();
app.UseSwaggerUI();

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = registration => registration.Tags.Contains("live")
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = registration => registration.Tags.Contains("ready")
});

app.MapAccountsEndpoints();
app.MapGraphAdministrationEndpoints();
app.MapGraphInitializationEndpoints();
app.MapGraphEndpoints();

app.Run();
