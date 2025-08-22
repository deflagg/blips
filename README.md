# BLIPS - Cloud-Native Microservices Platform

## Overview

BLIPS is a comprehensive cloud-native platform demonstrating modern microservices architecture on Azure. The project showcases infrastructure as code with Azure Bicep, containerized .NET 9 services, Azure Functions for serverless computing, React-based frontend, and enterprise-grade security patterns including certificate management and private networking.

## Project Structure

```
blips/
├── blips.sln                    # Main solution file
├── infra/                       # Infrastructure as Code (Azure Bicep)
│   ├── main.bicep              # Main infrastructure template
│   ├── main.parameters.json    # Infrastructure parameters
│   ├── deploy.ps1              # Infrastructure deployment script
│   ├── modules/                # Modular infrastructure components
│   │   ├── aks.bicep          # Azure Kubernetes Service
│   │   ├── agw.bicep          # Application Gateway
│   │   ├── apim.bicep         # API Management
│   │   ├── cosmosdb/          # Cosmos DB with serverless config
│   │   ├── keyvault.bicep     # Azure Key Vault
│   │   ├── hubvnet.bicep      # Hub virtual network
│   │   ├── spoke1Vnet.bicep   # Spoke virtual network
│   │   ├── vpngw.bicep        # VPN Gateway
│   │   └── ...                # Additional infrastructure modules
│   └── certs/                 # TLS certificates and CA management
│       ├── akscerts/          # AKS cluster certificates
│       └── vpncert/           # VPN client certificates
├── services/                   # Backend microservices
│   ├── blipfeed/              # .NET 9 Read API (Query side)
│   │   ├── Program.cs         # Main application entry point
│   │   ├── Dockerfile         # Container definition
│   │   ├── helm/              # Kubernetes Helm charts
│   │   └── deploy.ps1         # Service deployment script
│   ├── blipWriter/            # .NET 9 Write API (Command side)
│   │   ├── Program.cs         # Main application entry point
│   │   ├── Dockerfile         # Container definition
│   │   └── deploy.ps1         # Service deployment script
│   └── userFollowersCdc/      # Azure Functions for Cosmos DB CDC
│       ├── user-followers-trigger.cs  # Cosmos DB change feed processor
│       ├── host.json          # Function app configuration
│       └── Program.cs         # Function app host
└── ui/                        # Frontend React application
    ├── src/                   # React source code
    │   ├── App.jsx           # Main application component
    │   └── components/       # React components
    │       └── blipfeed.jsx  # BlipFeed service integration
    ├── package.json          # Node.js dependencies
    ├── vite.config.js        # Vite build configuration
    └── Dockerfile            # Container definition for UI
```

## Components

### Infrastructure

The project uses Azure Bicep templates to provision a complete enterprise-grade cloud infrastructure including:

- **Virtual Networks**: Hub & Spoke architecture with private networking
- **Azure Kubernetes Service (AKS)**: Private cluster for container orchestration
- **Application Gateway**: Layer 7 load balancer with Web Application Firewall (WAF)
- **Azure API Management (APIM)**: API gateway with policy enforcement
- **Azure Container Registry (ACR)**: Private container image repository
- **Cosmos DB**: Serverless NoSQL database with free tier
- **Azure Functions**: Serverless compute for event-driven processing
- **Azure DNS**: Private DNS zones for internal name resolution
- **DNS Forwarder VM**: Custom DNS forwarding for hybrid scenarios
- **VPN Gateway**: Secure point-to-site connectivity
- **Azure Key Vault**: Certificate and secrets management
- **Log Analytics**: Centralized logging and monitoring
- **Azure Firewall**: Network security and traffic filtering

### Backend Services

#### CQRS Architecture with Separated Read/Write Services

The platform implements **Command Query Responsibility Segregation (CQRS)** pattern with dedicated services for read and write operations:

#### BlipFeed Service (.NET 9 Read API)
A specialized .NET 9 REST API service for **query operations** featuring:
- **GET /blips** - List blips with pagination and continuation tokens
- **Request Unit (RU) monitoring** - Cosmos DB cost tracking in response headers
- Health check endpoints for Kubernetes probes
- TLS certificate integration with Azure Key Vault
- OpenAPI/Swagger documentation
- Docker containerization with multi-stage builds
- Kubernetes deployment via Helm charts
- Integration with Application Gateway for HTTPS termination
- CORS support with exposed RU headers for client-side monitoring

#### BlipWriter Service (.NET 9 Write API)
A dedicated .NET 9 REST API service for **command operations** featuring:
- **POST /blips** - Create new blips with validation (1-280 characters)
- **PUT /blips/{id}** - Update existing blips with optimistic concurrency control
- **Request Unit (RU) monitoring** - Real-time Cosmos DB cost tracking
- **ETag-based concurrency** - Prevents lost updates with If-Match headers
- Health check endpoints for Kubernetes probes
- OpenAPI/Swagger documentation with validation schemas
- Docker containerization for cloud deployment
- Automatic Cosmos DB initialization in development mode
- CORS configuration for cross-origin requests

#### UserFollowers CDC Function (Azure Functions v4)
A serverless Azure Function that:
- Processes Cosmos DB change feed events
- Monitors the `user-followers` container for real-time updates
- Built on .NET 9 with isolated worker model
- Automatic lease container management
- Application Insights integration for monitoring

### Frontend Application

A modern React 19 application built with:
- **Vite**: Fast development server and optimized production builds
- **Component Architecture**: Modular React components
- **Dual API Integration**: Connects to both BlipFeed (read) and BlipWriter (write) services
- **Request Unit Awareness**: Displays Cosmos DB cost information from API responses
- **Modern JavaScript**: ES modules and modern syntax
- **Development Tools**: ESLint for code quality
- **Containerization**: Multi-stage Docker builds for production deployment

## Deployment

### Prerequisites

- Azure subscription with sufficient quotas
- Azure CLI (latest version)
- PowerShell 7+ 
- Docker Desktop
- Kubernetes CLI (kubectl)
- Helm 3.x
- .NET 9 SDK (for local development)
- Node.js 18+ and npm (for UI development)

### Infrastructure Deployment

The infrastructure deployment creates all necessary Azure resources:

```powershell
# Navigate to infrastructure directory
cd infra

# Review and update parameters in main.parameters.json
# Set project name (must be globally unique for ACR and Cosmos DB)
# Configure email and publisher details for APIM

# Deploy the complete Azure infrastructure
./deploy.ps1 -ResourceGroupName "rg-blips-prod" -Location "eastus"
```

### Service Deployment

#### Deploy BlipFeed Read API Service

```powershell
# Deploy the .NET Read API service to AKS
cd services/blipfeed
./deploy.ps1
```

#### Deploy BlipWriter Command API Service

```powershell
# Deploy the .NET Write API service to AKS
cd services/blipWriter
./deploy.ps1
```

#### Deploy Azure Functions

```powershell
# Deploy the Cosmos DB change feed processor
cd services/userFollowersCdc

# Build and publish the function
dotnet publish -c Release

# Deploy using Azure Functions Core Tools or Azure CLI
# (Ensure the function app was created during infrastructure deployment)
```

#### Deploy Frontend UI

```powershell
# Deploy the React application
cd ui
./deploy.ps1
```

## Local Development

### BlipFeed Read API Service

```powershell
# Navigate to the Read API service directory
cd services/blipfeed

# Restore dependencies
dotnet restore

# Run the service locally (uses HTTPS with development certificates)
dotnet run

# The API will be available at https://localhost:5001
# Swagger UI available at https://localhost:5001/swagger
# GET /blips?userId=test&pageSize=20 - List blips with RU tracking
```

### BlipWriter Command API Service

```powershell
# Navigate to the Write API service directory
cd services/blipWriter

# Restore dependencies
dotnet restore

# Run the service locally (uses HTTPS with development certificates)
dotnet run

# The API will be available at https://localhost:5002 (or next available port)
# Swagger UI available at https://localhost:5002/swagger
# POST /blips - Create blips with validation and RU monitoring
# PUT /blips/{id}?userId={userId} - Update with ETag concurrency control
```

### Azure Functions (UserFollowers CDC)

```powershell
# Navigate to the function directory
cd services/userFollowersCdc

# Install Azure Functions Core Tools if not already installed
# Run the function locally
func start

# The function will monitor local Cosmos DB emulator or configured connection
```

### Frontend UI

```powershell
# Navigate to the UI directory
cd ui

# Install dependencies
npm install

# Start development server with hot reload
npm run dev

# The UI will be available at http://localhost:5173
# Automatically connects to the BlipFeed API service
```

### Building the Complete Solution

```powershell
# Build all .NET projects in the solution
dotnet build

# Run tests (if available)
dotnet test

# Build production-ready containers for both services
docker build -t blipfeed:latest -f services/blipfeed/Dockerfile services/blipfeed
docker build -t blipwriter:latest -f services/blipWriter/Dockerfile services/blipWriter
docker build -t blips-ui:latest -f ui/Dockerfile ui
```

## Security Features

- **TLS Everywhere**: End-to-end encryption with custom CA and certificates
- **Private Networking**: All services deployed in private subnets
- **VPN Access**: Secure point-to-site connectivity for management
- **Private AKS Cluster**: API server accessible only through private endpoint
- **Network Security Groups**: Fine-grained network access control
- **Azure Firewall**: Centralized network security and traffic inspection
- **Web Application Firewall**: Application layer protection in Application Gateway
- **Key Vault Integration**: Secure certificate and secrets management
- **Managed Identity**: Service-to-service authentication without credentials
- **API Management Policies**: Rate limiting, authentication, and authorization

## Architecture Highlights

- **CQRS Pattern**: Command Query Responsibility Segregation with dedicated read/write services
- **Request Unit Monitoring**: Real-time Cosmos DB cost tracking with RU headers
- **Optimistic Concurrency**: ETag-based conflict resolution for data consistency
- **Hub and Spoke Topology**: Centralized connectivity and security
- **Private Cluster Design**: Enhanced security with private endpoints
- **API Gateway Pattern**: Centralized API management with Azure APIM
- **Event-Driven Architecture**: Cosmos DB change feed processing with Azure Functions
- **Infrastructure as Code**: Complete environment reproducibility with Bicep
- **Containerized Microservices**: Kubernetes orchestration with Helm
- **Multi-Stage Docker Builds**: Optimized container images for security and performance
- **Serverless Computing**: Cost-effective event processing with Azure Functions
- **Modern Frontend Stack**: React 19 with Vite for optimal development experience
- **Enterprise Monitoring**: Application Insights and Log Analytics integration

## Database Design

The platform uses **Azure Cosmos DB** in serverless mode with:
- **Database**: `blips` 
- **Main Container**: `user-followers` - stores user relationship data and blip content
- **Leases Container**: `leases` - manages change feed processing state
- **Free Tier**: Cost-effective for development and small-scale production
- **Change Feed**: Real-time event processing for user relationship updates
- **Request Unit Tracking**: Built-in cost monitoring with RU consumption in API responses
- **Partition Strategy**: Optimized for user-based queries with userId as partition key
- **Consistency Model**: Strong consistency for write operations, eventual consistency for reads

## API Design

The platform implements a **CQRS (Command Query Responsibility Segregation)** pattern with separate services for read and write operations:

### BlipFeed API (Read Operations)
- **GET /blips?userId={userId}&pageSize={size}&continuationToken={token}**
  - List blips with pagination support
  - Returns continuation tokens for efficient paging
  - Includes RU consumption in response headers
  - Supports configurable page sizes (max 100)

### BlipWriter API (Write Operations)
- **POST /blips**
  - Create new blips with validation (1-280 characters)
  - Returns 201 Created with ETag header for concurrency control
  - Includes RU consumption tracking
  - Validates userId and text content

- **PUT /blips/{id}?userId={userId}**
  - Update existing blips with optimistic concurrency
  - Requires If-Match header with ETag for conflict prevention
  - Returns 412 Precondition Failed on ETag mismatch
  - Real-time RU consumption monitoring

### Cross-Cutting Concerns
- **Health Checks**: `/health/live` and `/health/ready` endpoints for Kubernetes
- **CORS**: Configured for cross-origin requests with exposed RU headers
- **OpenAPI**: Full Swagger documentation for both services
- **Request Unit Tracking**: All operations return Cosmos DB cost information

## Getting Started

1. **Clone the repository**
2. **Review infrastructure parameters** in `infra/main.parameters.json`
3. **Deploy infrastructure** using the deployment script
4. **Configure local development** environment for services
5. **Deploy services** to the provisioned infrastructure
6. **Access the application** through the Application Gateway endpoint

## Contributing

When contributing to this project:
- Follow .NET and React coding standards
- Update Bicep templates for infrastructure changes
- Ensure all services have proper health checks
- Update Helm charts for Kubernetes deployments
- Test locally before deploying to Azure

## License

This project is licensed under the MIT License - see the LICENSE file for details.

