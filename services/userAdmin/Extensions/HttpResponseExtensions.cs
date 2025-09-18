using System;
using System.Globalization;
using Microsoft.AspNetCore.Http;

namespace UserAdmin.Extensions;

public static class HttpResponseExtensions
{
    public static void SetRequestCharge(this HttpResponse response, double requestCharge)
    {
        if (response is null)
        {
            throw new ArgumentNullException(nameof(response));
        }

        response.Headers["x-ms-request-charge"] = requestCharge.ToString("0.###", CultureInfo.InvariantCulture);
    }
}
