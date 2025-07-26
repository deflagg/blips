<#
    Script:    New‑AksRootCA.ps1
    Purpose:   Create a self‑signed root CA certificate and key.
               Run **once** and keep the key offline / under tight controls.
    Note:      No explicit exception handling, per request.
#>

# ---------- configurable values ----------
$RootName     = "BlipsAKSRootCA"   # Common‑name and file prefix
$ValidityDays = 3650               # 10‑year validity
# ----------------------------------------

Write-Host "Creating $RootName root CA..."

& openssl genrsa -out "$RootName.key" 4096 | Out-Null

& openssl req -x509 -new -nodes -key "$RootName.key" `
    -sha256 -days $ValidityDays -out "$RootName.cer" `
    -subj "/CN=$RootName"

Write-Host "Root created:`n  - $RootName.cer (public cert)`n  - $RootName.key (private key)"
Write-Host "`nIMPORTANT: Store $RootName.key securely and offline."
