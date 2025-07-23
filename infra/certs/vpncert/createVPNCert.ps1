<#
    Updated script: generates a root CA, a client cert, bundles them into a
    PFX, and installs both certificates silently in the current user stores.
#> 

# ---------- configurable values ----------
$RootName    = "BlipsAzureVpnRootCA"
$ClientName  = "BlipsVpnClient"
$PfxPassword = "p@ssword1"    # choose a strong password
# ----------------------------------------

# ---- ROOT CA (re-use if already present) ----
if (-not (Test-Path ".\$RootName.key")) {
    & openssl genrsa -out "$RootName.key" 2048 | Out-Null
    & openssl req -x509 -new -nodes -key "$RootName.key" `
        -sha256 -days 3650 -out "$RootName.cer" `
        -subj "/CN=$RootName" | Out-Null
}

# ----- save a Base-64 copy for the Azure portal -----
$bytes = Get-Content .\$RootName.cer -Encoding Byte
$b64 = [Convert]::ToBase64String($bytes) | Out-File "$RootName`_base64.txt" -Encoding ascii

# ----- import root CA silently (no UI prompt) -----
certutil.exe -user -f -addstore root "$RootName.cer" | Out-Null

# ------------- CLIENT CERTIFICATE -------------
& openssl genrsa -out "$ClientName.key" 2048 | Out-Null
& openssl req -new -key "$ClientName.key" `
    -subj "/CN=$ClientName" -out "$ClientName.csr" | Out-Null

# Minimal OpenSSL config for EKU = clientAuth
@"
[ req ]
distinguished_name = dn
[ dn ]
[ v3_client ]
keyUsage = digitalSignature
extendedKeyUsage = clientAuth
"@ | Out-File ".\client_openssl.cnf" -Encoding ascii

& openssl x509 -req -in "$ClientName.csr" `
    -CA "$RootName.cer" -CAkey "$RootName.key" -CAcreateserial `
    -out "$ClientName.cer" -days 825 -sha256 `
    -extensions v3_client -extfile ".\client_openssl.cnf" | Out-Null
Remove-Item ".\client_openssl.cnf" -Force

# ------------- BUNDLE PFX & IMPORT -------------
& openssl pkcs12 -export `
    -in "$ClientName.cer" -inkey "$ClientName.key" `
    -certfile "$RootName.cer" -out "$ClientName.pfx" `
    -passout pass:$PfxPassword | Out-Null

Import-PfxCertificate -FilePath "$ClientName.pfx" `
    -Password (ConvertTo-SecureString $PfxPassword -AsPlainText -Force) `
    -CertStoreLocation Cert:\CurrentUser\My | Out-Null
