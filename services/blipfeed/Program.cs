    using System.Collections.ObjectModel;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    using Microsoft.AspNetCore.Diagnostics.HealthChecks;
    using Microsoft.AspNetCore.Server.Kestrel.Https;
    using Microsoft.Extensions.Diagnostics.HealthChecks;

    var builder = WebApplication.CreateBuilder(args);

    // Add services to the container.
    // Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
    builder.Services.AddOpenApi();

    builder.Services
        .AddHealthChecks()
        .AddCheck("self", () => HealthCheckResult.Healthy(), tags: new[] { "ready" });

    // // Load cert from mounted secret (adjust paths/keys as needed)
    // var certPath = "/mnt/secrets/azure-aks-appgw-pfx-base64";  // Key Vault secret name
    // //var certPassword = "/mnt/secrets/cert-password";  // Or env var
    // var cert = X509Certificate2.CreateFromPemFile(certPath); ///, File.ReadAllText(certPassword));

    // builder.WebHost.UseKestrel(options =>
    // {
    //     options.ListenAnyIP(443, listenOptions =>
    //     {
    //         listenOptions.UseHttps(cert);
    //     });
    // });

    // // Load base64-encoded passwordless PFX from mounted secret
    // string base64PfxPath = "/mnt/secrets/azure-aks-appgw-pfx-base64";
    // string base64Pfx = File.ReadAllText(base64PfxPath).Trim();
    // byte[] pfxBytes = Convert.FromBase64String(base64Pfx);

    // // Load the PFX using the .NET 9 API (returns a single cert)
    // X509Certificate2 cert = X509CertificateLoader.LoadPkcs12(
    //     pfxBytes,
    //     password: null,
    //     keyStorageFlags: X509KeyStorageFlags.MachineKeySet | X509KeyStorageFlags.PersistKeySet | X509KeyStorageFlags.Exportable
    // );

    string certPath = "/mnt/secrets/azure-aks-appgw-chain-pfx";
    // Load the full PFX chain
    // Load leaf cert with private key (efficient for .NET 6+)
    // Load full chain collection (no password; use null or empty string)
    X509Certificate2Collection fullChain = X509CertificateLoader.LoadPkcs12CollectionFromFile(certPath, null, X509KeyStorageFlags.Exportable);

    // Find leaf cert with private key
    X509Certificate2? leafCert = fullChain.FirstOrDefault(c => c.HasPrivateKey);
    if (leafCert == null) throw new Exception("No certificate with private key found in PFX.");

    // Create additional chain (exclude leaf)
    var additionalChain = new X509Certificate2Collection(fullChain.Where(c => !c.Thumbprint.Equals(leafCert.Thumbprint)).ToArray());

    // Build reusable context (sends full chain)
    var serverCertContext = SslStreamCertificateContext.Create(leafCert, additionalChain, offline: true);

    builder.WebHost.UseKestrel(options =>
    {
        options.Listen(IPAddress.Any, 443, listenOptions =>
        {
            listenOptions.UseHttps(new TlsHandshakeCallbackOptions
            {
                OnConnection = _ => new ValueTask<SslServerAuthenticationOptions>(
                    new SslServerAuthenticationOptions
                    {
                        ServerCertificateContext = serverCertContext
                    })
            });
        });
    });

    // cors
    builder.Services.AddCors(options =>
    {
        options.AddPolicy("AllowAll",
            builder => builder.AllowAnyOrigin()
                              .AllowAnyMethod()
                              .AllowAnyHeader());
    });



    var app = builder.Build();

    app.UseCors("AllowAll");

    // Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.UseHttpsRedirection();
}

    if (app.Environment.IsProduction())
    {
        app.UseHttpsRedirection();
    }

    // ----------  Health-check endpoints ----------
    app.MapHealthChecks("/health/live", new HealthCheckOptions
    {
        Predicate = reg => reg.Tags.Contains("live")   // run only the failing check
    });

    app.MapHealthChecks("/health/ready", new HealthCheckOptions
    {
        Predicate = reg => reg.Tags.Contains("ready")  // run only the ready checks
    });
    // ---------------------------------------------

    var summaries = new[]
    {
        "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
    };

    app.MapGet("/weatherforecast", () =>
    {
        var forecast =  Enumerable.Range(1, 5).Select(index =>
            new WeatherForecast
            (
                DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
                Random.Shared.Next(-20, 55),
                summaries[Random.Shared.Next(summaries.Length)]
            ))
            .ToArray();
        return forecast;
    })
    .WithName("GetWeatherForecast");

    app.Run();

    record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
    {
        public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
    }
