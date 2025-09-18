# Blips

Blips is a sample social feed platform built around event-driven .NET microservices, a React front end, and Azure infrastructure-as-code. The repository contains everything needed to run the API surface, worker processes, infrastructure templates, and local developer tooling.

## Architecture Overview
- **Client (`ui/`)** - Vite-powered React 19 single-page app that calls the backend APIs via Axios and renders timelines and relationship graphs with Cytoscape.
- **Write API (`services/blipWriter/`)** - ASP.NET Core minimal API that validates input, persists new blips to Cosmos DB, and publishes `blip.created` events to Event Hubs so downstream services can fan out updates.
- **Read API (`services/blipfeed/`)** - ASP.NET Core minimal API that assembles personalized feeds by combining Cosmos DB queries, follower graph lookups via Gremlin, and optional Redis home-feed caching.
- **User Admin API (`services/userAdmin/`)** - ASP.NET Core minimal API that seeds Cosmos containers, manages account data, and maintains the follower graph stored in the Cosmos Gremlin API.
- **Fan-out Worker (`services/blipFeedFanout/`)** - .NET background worker that consumes Event Hubs partitions, resolves follower lists from Gremlin, and writes fan-out timelines into Redis sorted sets.
- **Change Data Capture (`services/userFollowersCdc/`)** - Azure Functions (isolated worker) project that reacts to Cosmos DB change feed events for the `user-followers` container and logs or propagates updates.
- **Infrastructure (`infra/`)** - Bicep templates and deployment scripts that provision Azure resources such as hub or spoke VNets, AKS, API Management, Application Gateway, Cosmos DB (SQL and Gremlin), Event Hubs, Key Vault, Log Analytics, and related dependencies.
- **Utilities (`utils/`)** - PowerShell scripts for spinning up local dependencies including the Cosmos DB emulator with Gremlin, the Event Hubs emulator (via WSL), and a Dockerized Redis instance.

### Data & Event Flow
1. The UI posts new content to `blipWriter`, which stores payloads in the Cosmos SQL API and emits `blip.created` events to Event Hubs.
2. `blipFeedFanout` consumes those events, looks up followers in the Cosmos Gremlin graph, and populates Redis home timelines per follower.
3. Clients request feeds through `blipfeed`, which first reads from Redis when available and falls back to Cosmos queries combined with follower graph lookups.
4. User and relationship management goes through `userAdmin`. The optional `userFollowersCdc` function watches the follower container change feed for additional processing hooks.

## Dependencies
### Core runtimes & tooling
- `.NET 9` across APIs, worker, and functions (`blipWriter`, `blipfeed`, `userAdmin`, `blipFeedFanout`, `userFollowersCdc`).
- `Node.js` plus `npm` for the Vite and React frontend (`ui/`).
- `Azure Bicep` and PowerShell for infrastructure provisioning (`infra/`).
- `Docker` used by local scripts such as `utils/run-redis.ps1`.

### Service packages (selected)
- `blipWriter`: `Azure.Identity`, `Azure.Messaging.EventHubs`, `Microsoft.Azure.Cosmos`, `Swashbuckle.AspNetCore`.
- `blipfeed`: `Azure.Identity`, `Gremlin.Net`, `Microsoft.Extensions.Caching.StackExchangeRedis`, `Microsoft.Azure.Cosmos`.
- `userAdmin`: `Azure.Identity`, `Azure.ResourceManager`, `Gremlin.Net`, `Microsoft.Azure.Cosmos`.
- `blipFeedFanout`: `Azure.Messaging.EventHubs`, `Gremlin.Net`, `StackExchange.Redis`, `Azure.Identity`.
- `userFollowersCdc`: `Microsoft.Azure.Functions.Worker`, `Microsoft.Azure.Functions.Worker.Extensions.CosmosDB`, `Microsoft.ApplicationInsights.WorkerService`.
- `ui`: `react`, `react-router-dom`, `axios`, `cytoscape`, with ESLint and Vite for tooling.

### External services & emulators
- **Azure Cosmos DB (SQL API)** - primary data store for blips and account metadata; local development uses the Cosmos DB Emulator (`utils/start-cosmosdb-gremlin.ps1`).
- **Cosmos DB (Gremlin API)** - stores the follower graph queried by `blipfeed`, `userAdmin`, and `blipFeedFanout`.
- **Azure Event Hubs** - transports `blip.created` events; a WSL-based emulator launcher is provided at `utils/start-event-hubs.ps1`.
- **Redis** - caches fan-out timelines; run locally via Docker with `utils/run-redis.ps1` or backed by Azure Cache for Redis in cloud deployments.
- **Azure Kubernetes Service, API Management, Application Gateway, Log Analytics, Key Vault** - provisioned by the Bicep templates to host and secure the microservices stack in Azure.

### Optional developer tooling
- `infra/deploy.ps1` and related scripts orchestrate Bicep deployments.
- Helm charts inside each service (`services/*/helm/`) package container deployments for AKS.
