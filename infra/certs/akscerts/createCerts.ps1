<#
    Script:    New‑AksGatewayTls.ps1
    Purpose:   Produce a root CA + server certificate (signed by that root)
               and save the PFX as base‑64 for use in Azure Bicep templates.
    Note:      No explicit exception handling is included per user request.
#>

# ---------- configurable values ----------
$RootName     = "BlipsAKSRootCA"
$ServerName   = "BlipsAKSGateway"
$DnsNames     = @("*.blips.service")
# ----------------------------------------

# ---------- ROOT CA (re‑use if it exists) ----------
if (-not (Test-Path ".\$RootName.key")) {
    & openssl genrsa -out "$RootName.key" 4096 | Out-Null
    & openssl req -x509 -new -nodes -key "$RootName.key" `
        -sha256 -days 3650 -out "$RootName.cer" `
        -subj "/CN=$RootName"
}

# ---------- SERVER CERTIFICATE ----------
& openssl genrsa -out "$ServerName.key" 4096 | Out-Null
& openssl req -new -key "$ServerName.key" `
    -subj "/CN=$ServerName" -out "$ServerName.csr" | Out-Null

# ---- Build minimal OpenSSL cfg with SANs & serverAuth EKU ----
$altNames = $DnsNames |
    ForEach-Object { $i = [array]::IndexOf($DnsNames, $_) + 1; "DNS.$i = $_" } |
    Out-String
@"
[ req ]
distinguished_name = dn
[ dn ]
[ v3_server ]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[ alt_names ]
$altNames
"@ | Set-Content ".\server_openssl.cnf" -Encoding ascii

& openssl x509 -req -in "$ServerName.csr" `
    -CA "$RootName.cer" -CAkey "$RootName.key" -CAcreateserial `
    -out "$ServerName.cer" -days 825 -sha256 `
    -extensions v3_server -extfile ".\server_openssl.cnf"

Remove-Item ".\server_openssl.cnf"

# ---------- PFX (server cert + chain) ----------
& openssl pkcs12 -export `
    -in "$ServerName.cer" -inkey "$ServerName.key" `
    -certfile "$RootName.cer" -out "$ServerName.pfx" `
    -passout pass: | Out-Null

# ---------- Base‑64 encode the PFX for Bicep ----------
$bytes = Get-Content ".\$ServerName.pfx" -Encoding Byte
[Convert]::ToBase64String($bytes) |
    Set-Content "$ServerName`_pfx_base64.txt" -Encoding ascii

Write-Host "Base‑64 PFX saved to $ServerName`_pfx_base64.txt"
