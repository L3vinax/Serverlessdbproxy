targetScope = 'resourceGroup'

metadata description = 'Deploys HAProxy behind an internal Standard Load Balancer and Private Link Service for Databricks Serverless access to on-premises SQL Server.'

param location string = resourceGroup().location
param prefix string = 'dbx-sqlproxy'
@description('Existing subnet resource ID. Private Link service network policies must be disabled.')
param subnetResourceId string
param adminUsername string = 'azureadmin'
@secure()
param sshPublicKey string
param vmSize string = 'Standard_D2s_v5'
@minValue(1)
@maxValue(65535)
param frontendPort int = 1433
param sqlServerAddress string
@minValue(1)
@maxValue(65535)
param sqlServerPort int = 1433
param maxConnections int = 10000
@description('Linux distribution for the HAProxy VM.')
@allowed([
  'Ubuntu'
  'RHEL'
])
param osType string = 'Ubuntu'
param visibilitySubscriptionIds array = []
param autoApprovalSubscriptionIds array = []
param tags object = {}

@description('Set true to also configure a Databricks NCC and private endpoint to the Private Link Service created above.')
param deployDatabricksNcc bool = false
param databricksAccountConsoleUrl string = 'https://accounts.azuredatabricks.net'
param databricksAccountId string = ''
@description('Numeric Databricks workspace ID (not the ARM resource ID).')
param databricksWorkspaceId string = ''
@description('Azure region in Databricks region format (e.g. westus2). Required if deployDatabricksNcc is true.')
param databricksRegion string = ''
@description('Domain name(s) clients use to reach the Private Link Service, e.g. the on-prem SQL Server FQDN.')
param privateLinkServiceDomainNames array = []
@description('Resource ID of a user-assigned managed identity that is an Account Admin in the Databricks account. Required if deployDatabricksNcc is true.')
param databricksNccIdentityResourceId string = ''

module nsg './modules/nsg.bicep' = {
  name: 'nsg'
  params: {
    name: '${prefix}-nsg'
    location: location
    tags: tags
    frontendPort: frontendPort
  }
}

module lb './modules/load-balancer.bicep' = {
  name: 'load-balancer'
  params: {
    name: '${prefix}-ilb'
    location: location
    tags: tags
    subnetResourceId: subnetResourceId
    frontendPort: frontendPort
  }
}

module vm './modules/haproxy-vm.bicep' = {
  name: 'haproxy-vm'
  params: {
    name: '${prefix}-vm'
    location: location
    tags: tags
    subnetResourceId: subnetResourceId
    nsgResourceId: nsg.outputs.id
    backendPoolId: lb.outputs.backendPoolId
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    frontendPort: frontendPort
    sqlServerAddress: sqlServerAddress
    sqlServerPort: sqlServerPort
    maxConnections: maxConnections
    osType: osType
  }
}

module pls './modules/private-link-service.bicep' = {
  name: 'private-link-service'
  params: {
    name: '${prefix}-pls'
    location: location
    tags: tags
    subnetResourceId: subnetResourceId
    loadBalancerFrontendId: lb.outputs.frontendId
    visibilitySubscriptionIds: visibilitySubscriptionIds
    autoApprovalSubscriptionIds: autoApprovalSubscriptionIds
  }
  dependsOn: [vm]
}

module ncc './modules/databricks-ncc.bicep' = if (deployDatabricksNcc) {
  name: 'databricks-ncc'
  params: {
    location: location
    tags: tags
    accountConsoleUrl: databricksAccountConsoleUrl
    databricksAccountId: databricksAccountId
    databricksWorkspaceId: databricksWorkspaceId
    region: databricksRegion
    nccName: '${prefix}-ncc'
    privateLinkServiceResourceId: pls.outputs.id
    privateLinkServiceDomainNames: privateLinkServiceDomainNames
    identityResourceId: databricksNccIdentityResourceId
  }
}

output privateLinkServiceId string = pls.outputs.id
output privateLinkServiceAlias string = pls.outputs.alias
output haproxyVmName string = vm.outputs.vmName
output frontendPort int = frontendPort
output networkConnectivityConfigId string = ncc.?outputs.networkConnectivityConfigId ?? ''
