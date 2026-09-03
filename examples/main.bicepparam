using '../main.bicep'

param location = 'westus2'
param prefix = 'dbx-sqlproxy-prod'
param subnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-connectivity/subnets/snet-proxy'
param adminUsername = 'azureadmin'
param sshPublicKey = 'ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY'
param sqlServerAddress = '10.100.20.25'
param sqlServerPort = 1433
param frontendPort = 1433
param visibilitySubscriptionIds = [
  '00000000-0000-0000-0000-000000000000'
]
param tags = {
  workload: 'databricks-sql-proxy'
  managedBy: 'bicep'
}
