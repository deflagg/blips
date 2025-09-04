namespace UserAdmin.Infrastructure;

// {
//   "Logging": {
//     "LogLevel": {
//       "Default": "Information",
//       "Microsoft.AspNetCore": "Warning"
//     }
//   },
//   "PersonGraphDB": {
//     "SubscriptionId": "400acf99-3ce6-4ee6-8bf7-9b209093ac5f",
//     "ResourceGroup": "sysdesign",
//     "AccountName": "gremlin-sysdesign",
//     "DatabaseId": "PersonGraphDb",
//     "GraphId": "PersonGraph"
//   },
//   "Cosmos": {
//     "Endpoint": "https://cosmos-sysdesign.documents.azure.com:443",
//     "Databases": [
//       {
//         "Id": "UserAdminDb",
//         "Throughput": null,
//         "Containers": [
//           {
//             "Id": "Accounts",
//             "PartitionKeyPath": "/accountId",
//             "Throughput": null,
//             "UniqueKeySets": [ [ "/email" ] ],
//             "DefaultTtlSeconds": -1
//           },
//           {
//             "Id": "Profiles",
//             "PartitionKeyPath": "/profileId",
//             "Throughput": 400
//           }
//         ]
//       },
//       {
//         "Id": "AuditDb",
//         "Throughput": 400,
//         "Containers": [
//           { "Id": "Events", "PartitionKeyPath": "/tenantId" },
//           { "Id": "Outbox", "PartitionKeyPath": "/pk", "ExcludeAllFromIndexing": true }
//         ]
//       }
//     ]
//   },
//   "Kestrel": {
//     "Endpoints": {
//       "Https": {
//         "Url": "https://+:443",
//         "Protocols": "Http1AndHttp2"
//       }
//     },
//     "Certificates": {
//       "Default": {
//         "Path": "/mnt/secrets/azure-aks-appgw-chain-pfx"
//       }
//     }
//   },
//   "AllowedHosts": "*"
// }


public sealed class CosmosOptions
{
    public string Endpoint { get; init; } = default!;
    public Dictionary<string, DatabaseOptions> Databases { get; init; } = new();

    public sealed class DatabaseOptions
    {
        public string DatabaseId { get; init; } = default!;
        public int? Throughput { get; init; }
        public Dictionary<string, ContainerOptions> Containers { get; init; } = new();
    }

    public sealed class ContainerOptions
    {
        public string ContainerId { get; init; } = default!;
        public string PartitionKeyPath { get; init; } = default!;
        public int? Throughput { get; init; }
        public List<List<string>>? UniqueKeySets { get; init; }
        public int? DefaultTtlSeconds { get; init; }
        public bool? ExcludeAllFromIndexing { get; init; }
    }
}