param name string
param location string
param tags object = {}
param subnetResourceId string
param loadBalancerFrontendId string
param visibilitySubscriptionIds array = []
param autoApprovalSubscriptionIds array = []

var visibility = empty(visibilitySubscriptionIds)
  ? [subscription().subscriptionId]
  : visibilitySubscriptionIds
var autoApproval = autoApprovalSubscriptionIds

resource pls 'Microsoft.Network/privateLinkServices@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    enableProxyProtocol: false
    loadBalancerFrontendIpConfigurations: [
      { id: loadBalancerFrontendId }
    ]
    ipConfigurations: [
      {
        name: 'nat-ipconfig-1'
        properties: {
          primary: true
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: subnetResourceId }
        }
      }
    ]
    visibility: { subscriptions: visibility }
    autoApproval: { subscriptions: autoApproval }
  }
}

output id string = pls.id
output alias string = pls.properties.alias
