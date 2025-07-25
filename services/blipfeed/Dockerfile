# Use the .NET 9 SDK image to build the application
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
ENV ASPNETCORE_URLS="https://*:443"

WORKDIR /source

# Copy the project file and restore dependencies
COPY *.csproj .
RUN dotnet restore

# Copy the rest of the application files and build the release
COPY . .
RUN dotnet publish -c Release -o /app

# Use the .NET 9 ASP.NET runtime image for the final, smaller image
FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /app .

# Expose the port the application runs on
EXPOSE 443

# Set the entry point for the container
ENTRYPOINT ["dotnet", "blipfeed.dll"]