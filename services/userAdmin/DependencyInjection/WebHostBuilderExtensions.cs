using System;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;

namespace UserAdmin.DependencyInjection;

public static class WebHostBuilderExtensions
{
    public static IWebHostBuilder ConfigureKestrelFromConfiguration(this IWebHostBuilder builder)
    {
        if (builder is null)
        {
            throw new ArgumentNullException(nameof(builder));
        }

        return builder.UseKestrel((context, options) =>
        {
            var kestrelSection = context.Configuration.GetSection("Kestrel");
            options.Configure(kestrelSection);
        });
    }
}
