using '../update-haproxy-backends.bicep'

param vmName = 'dbx-sqlproxy-prod-vm'
param loadBalancerName = 'dbx-sqlproxy-prod-ilb'
param subnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-connectivity/subnets/snet-proxy'
param networkSecurityGroupName = 'dbx-sqlproxy-prod-nsg'

// Authoritative list: every listener/backend that should exist after this deployment.
param backends = [
  {
    name: 'sql-prod'
    frontendPort: 1433
    servers: [
      { name: 'sql01', address: '10.100.20.25', port: 1433 }
    ]
  }
  {
    name: 'sql-reporting'
    frontendPort: 1434
    servers: [
      { name: 'sql02', address: '10.100.20.40', port: 1433 }
    ]
  }
]
