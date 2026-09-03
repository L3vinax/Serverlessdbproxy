param name string
param location string
param tags object = {}
param subnetResourceId string
param frontendPort int

var frontendName = 'sql-frontend'
var backendPoolName = 'haproxy-backend'
var probeName = 'haproxy-health'

resource lb 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: frontendName
        properties: {
          subnet: { id: subnetResourceId }
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
    backendAddressPools: [
      { name: backendPoolName }
    ]
    probes: [
      {
        name: probeName
        properties: {
          protocol: 'Http'
          port: 8404
          requestPath: '/health'
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'sql-forwarding'
        properties: {
          protocol: 'Tcp'
          frontendPort: frontendPort
          backendPort: frontendPort
          enableFloatingIP: false
          enableTcpReset: true
          idleTimeoutInMinutes: 30
          disableOutboundSnat: true
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', name, frontendName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', name, backendPoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', name, probeName)
          }
        }
      }
    ]
  }
}

output id string = lb.id
output frontendId string = resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', name, frontendName)
output backendPoolId string = resourceId('Microsoft.Network/loadBalancers/backendAddressPools', name, backendPoolName)
