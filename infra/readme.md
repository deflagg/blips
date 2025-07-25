Lessons Learned
=================
- Ensure that the Key Vault's `enableSoftDelete` property is set to `true` to allow integration with Application Gateway.
- When using `enablePurgeProtection`, it should be set to `true` only if the Key Vault is not intended to be purged after deletion. This setting is commented out in the current configuration.
- RBAC assignments 