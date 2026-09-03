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
param visibilitySubscriptionIds array = []
param autoApprovalSubscriptionIds array = []
param tags object = {}

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

output privateLinkServiceId string = pls.outputs.id
output privateLinkServiceAlias string = pls.outputs.alias
output haproxyVmName string = vm.outputs.vmName
output frontendPort int = frontendPort
