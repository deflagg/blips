<#
    Script:    New-AksGatewayTls.ps1
    Purpose:   Produce a server cert signed by the root CA and emit
               a password-less PFX as Base-64 for IaC pipelines.
    Note:      No explicit exception handling, per request.
#>

param (
    [string] $RootName     = "BlipsAKSRootCA",          # Root CA file prefix
    [string] $ServerName   = "BlipsAKSGateway",         # CN for the server cert
    [string[]]$DnsNames    = @("*.blips.service"),      # SANs
    [int]    $ValidityDays = 825                        # < 27 months
)

# ---------- sanity check ----------
if (-not (Test-Path ".\$RootName.cer") -or -not (Test-Path ".\$RootName.key")) {
    throw "Root CA files '$RootName.cer' / '$RootName.key' not found.  Run New-AksRootCA.ps1 first."
}

# ---------- SERVER KEY & CSR ----------
& openssl genrsa -out "$ServerName.key" 4096 | Out-Null
& openssl req -new -key "$ServerName.key" `
    -subj "/CN=$ServerName" -out "$ServerName.csr" | Out-Null

# ---------- Minimal OpenSSL cfg with SANs ----------
$altNames = $DnsNames `
    | ForEach-Object { $i = [array]::IndexOf($DnsNames, $_) + 1; "DNS.$i = $_" } `
    | Out-String
@"
[ req ]
distinguished_name = dn
[ dn ]
[ v3_server ]
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = @alt_names
[ alt_names ]
$altNames
"@ | Set-Content ".\server_openssl.cnf" -Encoding ascii

# ---------- Sign with root ----------
& openssl x509 -req -in "$ServerName.csr" `
    -CA "$RootName.cer" -CAkey "$RootName.key" -CAcreateserial `
    -out "$ServerName.cer" -days $ValidityDays -sha256 `
    -extensions v3_server -extfile ".\server_openssl.cnf"

Remove-Item ".\server_openssl.cnf","$ServerName.csr"
Get-Content "$ServerName.cer","$RootName.cer" | Set-Content "$ServerName.chain.cer"

# ---------- Build password-less PFX ----------
# & openssl pkcs12 -export `
#     -in "$ServerName.cer" -inkey "$ServerName.key" `
#     -certfile "$RootName.cer" -out "$ServerName.pfx" `
#     -passout pass: | Out-Null
& openssl pkcs12 -export `
    -in "$ServerName.chain.cer" -inkey "$ServerName.key" `
    -out "$ServerName.pfx" `
    -passout pass: | Out-Null

# ---------- Base-64 for Bicep ----------
$bytes = Get-Content ".\$ServerName.pfx" -Encoding Byte
[Convert]::ToBase64String($bytes) |
    Set-Content "$ServerName`_pfx_base64.txt" -Encoding ascii

Write-Host "`nBase-64 PFX saved to $ServerName`_pfx_base64.txt"
