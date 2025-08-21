
docker pull mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest
docker volume create cosmosdb-data
docker run -d --name cosmos-emulator -p 8081:8081 -p 10250-10255:10250-10255 -v cosmosdb-data:/tmp/cosmos/appdata -e AZURE_COSMOS_EMULATOR_ENABLE_DATA_PERSISTENCE=true --memory=3g mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest
curl -k https://localhost:8081/_explorer/emulator.pem -o emulatorcert.crt
certutil -addstore -f "Root" emulatorcert.crt
start https://localhost:8081/_explorer/index.html
