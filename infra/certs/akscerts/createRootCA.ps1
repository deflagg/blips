# ---------- configurable values ----------
$RootName     = "BlipsAKSRootCA"   # Common-name and file prefix
$ValidityDays = 3650               # 10-year validity
# ----------------------------------------

Write-Host "Creating $RootName root CA..."

# Generate private key
& openssl genrsa -out "$RootName.key" 4096 | Out-Null

# Generate self-signed certificate in PEM format
& openssl req -x509 -new -nodes -key "$RootName.key" `
    -sha256 -days $ValidityDays -out "$RootName.cer" `
    -subj "/CN=$RootName"

# Convert PEM to DER (binary)
& openssl x509 -in "$RootName.cer" -outform DER -out "$RootName.der"

# Base-64 encode the DER file (pure binary, no headers/footers)
$base64Cert = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$PSScriptRoot\$RootName.der")) |
    Set-Content "$RootName`_cer_base64.txt" -Encoding ascii

remove-item "$RootName.der"  # Clean up DER file

Write-Host "Root created:`n  - $RootName.cer (PEM public cert)`n  - $RootName.key (private key)"
Write-Host "`nIMPORTANT: Store $RootName.key securely and offline."