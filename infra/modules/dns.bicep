// dns.bicep – Private DNS zone + VNet link
// Verified against Microsoft Learn reference 2024-06-01
// ----------------------------------------------------

@description('Private DNS zone name (e.g. "priv.contoso.com")')
param dnsZoneName string

@description('Resource ID of the virtual network to link')
param vnetId string

// ---------- Private DNS zone ----------
// • Resource type:  Microsoft.Network/privateDnsZones
// • API version :   2024-06-01  :contentReference[oaicite:0]{index=0}
resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: dnsZoneName
  location: 'global'   // location is always Global for DNS zones
  properties: {}
}

// ---------- VNet ↔ zone link ----------
// • Resource type:  Microsoft.Network/privateDnsZones/virtualNetworkLinks
// • API version :   2024-06-01  :contentReference[oaicite:1]{index=1}
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'vnetLink-${uniqueString(vnetId)}'   // must be unique *within* the zone
  parent: dnsZone                             // cleaner than embedding the zone name in `name`
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    // enable if you want VM hostname registration
    registrationEnabled: false
    // `resolutionPolicy` is optional; omit to use the default behaviour
  }
}

output dnsZoneResourceId string = dnsZone.id
