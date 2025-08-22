using System;
using System.Collections.Generic;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace Blips.Function;

public class user_followers_trigger
{
    private readonly ILogger<user_followers_trigger> _logger;

    public user_followers_trigger(ILogger<user_followers_trigger> logger)
    {
        _logger = logger;
    }

    [Function("user_followers_trigger")]
    public void Run([CosmosDBTrigger(
        databaseName: "blips",
        containerName: "user-followers",
        Connection = "cosmossysdesign_DOCUMENTDB",
        LeaseContainerName = "leases",
        CreateLeaseContainerIfNotExists = false)] IReadOnlyList<MyDocument> input)
    {
        if (input != null && input.Count > 0)
        {
            _logger.LogInformation("Documents modified: " + input.Count);
            _logger.LogInformation("First document Id: " + input[0].id);
        }
    }
}

public class MyDocument
{
    public string id { get; set; }
    public string userId { get; set; }
}