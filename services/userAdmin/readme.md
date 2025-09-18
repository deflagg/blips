dotnet new webapi
dotnet add package Microsoft.Azure.Cosmos
dotnet add package Swashbuckle.AspNetCore
dotnet add package Newtonsoft.Json
dotnet add package Azure.Identity
dotnet add package Gremlin.Net
dotnet add package Azure.ResourceManager
dotnet add package Azure.ResourceManager.CosmosDB
dotnet add package Azure.Messaging.EventHubs
dotnet add package Microsoft.Extensions.Caching.StackExchangeRedis
dotnet clean
dotnet build

docker pull ngrok/ngrok:latest
