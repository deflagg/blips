# BLIPS - Modern Microservices Architecture Example

## Overview

BLIPS is a comprehensive example of a modern, cloud-native application built using microservices architecture. The project demonstrates infrastructure as code, containerization, service mesh, and Kubernetes deployment patterns. It includes both a backend service (BlipFeed) and a frontend UI component, all deployable to Azure using industry best practices.

## Project Structure

```
blips/
├── infra/             # Infrastructure as Code (Azure Bicep)
│   ├── certs/         # Certificates for AKS and VPN 
│   ├── modules/       # Modularized infrastructure components
│   ├── deploy.ps1     # Main deployment script
│   └── main.bicep     # Entry point for Azure deployment
├── services/          # Backend microservices
│   └── blipfeed/      # Sample API service
│       ├── helm/      # Kubernetes deployment via Helm charts
│       └── Dockerfile # Container definition
└── ui/               # Frontend application
    ├── src/          # React source code
    └── Dockerfile    # Container definition for UI
```

## Components

### Infrastructure

The project uses Azure Bicep templates to provision a complete cloud infrastructure including:

- Virtual Networks (Hub & Spoke architecture)
- Azure Kubernetes Service (AKS)
- Application Gateway with Web Application Firewall
- Azure API Management
- Container Registry
- Azure DNS with private zones
- DNS Forwarder VM
- VPN Gateway for secure access
- Azure Key Vault
- Log Analytics workspace

### Backend Service - BlipFeed

A .NET 9 REST API service that:
- Demonstrates health checks
- Provides a sample weather forecast API endpoint
- Includes Docker containerization
- Has Kubernetes deployment configurations via Helm charts

### Frontend UI

A React application built with:
- Modern React (v19)
- Vite for fast development and optimized builds
- Component-based architecture
- Connects to the BlipFeed service 
- Multi-stage Docker build for optimized container size

## Deployment

### Prerequisites

- Azure subscription
- Azure CLI
- PowerShell
- Docker
- Kubernetes CLI (kubectl)
- Helm

### Deploying Infrastructure

```powershell
# Deploy the Azure infrastructure
cd infra
./deploy.ps1 -ResourceGroupName "your-resource-group" -Location "your-preferred-region"
```

### Deploying Services

#### Deploy BlipFeed Service

```powershell
# Deploy the BlipFeed service
cd services/blipfeed
./deploy.ps1
```

#### Deploy UI

```powershell
# Deploy the UI
cd ui
./deploy.ps1
```

## Development

### BlipFeed Service

```powershell
# Run the service locally
cd services/blipfeed
dotnet run
```

### UI

```powershell
# Install dependencies
cd ui
npm install

# Start development server
npm run dev
```

## Security Features

- TLS certificates for secure communication
- VPN for secure access to resources
- Private AKS cluster
- Network security groups
- Azure Firewall
- Web Application Firewall in Application Gateway

## Architecture Highlights

- Hub and Spoke network topology
- Service mesh for microservices communication
- API Gateway pattern with Azure Application Gateway
- Containerized applications for consistent deployment
- Infrastructure as Code for reproducibility
- Kubernetes for container orchestration
- Multi-stage Docker builds for security and optimization

## License

This project is licensed under the MIT License - see the LICENSE file for details.

