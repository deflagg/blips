# To use this script, ensure you have OpenSSL installed and available in your PATH.
# This script generates a self-signed root CA certificate and converts it to a Base-64 string.
# Usage: Run the script.

# Generate a 2048-bit RSA private key
openssl genrsa -out ./BlipsAzureVpnRootCA.key 2048

# Create a self-signed root certificate
openssl req -x509 -new -nodes -key ./BlipsAzureVpnRootCA.key -sha256 -days 3650 -out ./BlipsAzureVpnRootCA.cer -subj "/CN=BlipsAzureVpnRootCA"

# (Optional) Inspect your cert
#openssl x509 -in ./BlipsAzureVpnRootCA.cer -noout -text

# Convert the .cer to a Base-64 string
$bytes = Get-Content .\BlipsAzureVpnRootCA.cer -Encoding Byte
$b64   = [Convert]::ToBase64String($bytes)

# Optionally save to a file:
$b64 | Out-File .\BlipsAzureVpnRootCA_base64.txt -Encoding ascii
