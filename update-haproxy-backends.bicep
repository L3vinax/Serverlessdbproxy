targetScope = 'resourceGroup'

metadata description = 'Adds listener rules to an existing HAProxy load balancer and updates the HAProxy configuration on its VM.'

type backendServer = {
  @description('Unique HAProxy server name.')
  name: string
  @description('Backend server IP address or DNS name.')
  address: string
  @minValue(1)
  @maxValue(65535)
  port: int
}

type haproxyBackend = {
  @description('Unique HAProxy backend name. Use letters, numbers, hyphens, or underscores.')
  name: string
  @minValue(1)
  @maxValue(65535)
  frontendPort: int
  @minLength(1)
  servers: backendServer[]
}

@description('Name of the existing HAProxy VM.')
param vmName string
@description('Name of the existing internal load balancer.')
param loadBalancerName string
@description('Resource ID of the subnet currently used by the load balancer frontend.')
param subnetResourceId string
@description('Name of the existing network security group attached to the HAProxy VM NIC.')
param networkSecurityGroupName string
param location string = resourceGroup().location
param tags object = {}
@minValue(1)
param maxConnections int = 10000
@minLength(1)
@maxLength(145)
@description('Complete desired backend list. Each backend gets its own frontend listener port.')
param backends haproxyBackend[]

var frontendName = 'sql-frontend'
var backendPoolName = 'haproxy-backend'
var probeName = 'haproxy-health'

var backendSections = [for backend in backends: join(concat([
  'frontend ${backend.name}_frontend'
  '    bind 0.0.0.0:${backend.frontendPort}'
  '    default_backend ${backend.name}'
  ''
  'backend ${backend.name}'
  '    balance roundrobin'
  '    option tcp-check'
], map(backend.servers, server => '    server ${server.name} ${server.address}:${server.port} check inter 5s fall 3 rise 2')), '\n')]

var globalAndDefaultsConfig = join([
  'global'
  '    log /dev/log local0'
  '    log /dev/log local1 notice'
  '    user haproxy'
  '    group haproxy'
  '    daemon'
  '    maxconn ${maxConnections}'
  ''
  'defaults'
  '    log global'
  '    mode tcp'
  '    option tcplog'
  '    option dontlognull'
  '    timeout connect 10s'
  '    timeout client 1h'
  '    timeout server 1h'
], '\n')

var healthConfig = join([
  'listen health'
  '    bind 0.0.0.0:8404'
  '    mode http'
  '    monitor-uri /health'
], '\n')

var haproxyConfig = '${globalAndDefaultsConfig}\n\n${join(backendSections, '\n\n')}\n\n${healthConfig}\n'
var encodedHaproxyConfig = base64(haproxyConfig)

resource loadBalancer 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: loadBalancerName
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
    loadBalancingRules: [for backend in backends: {
      name: '${backend.name}-forwarding'
      properties: {
        protocol: 'Tcp'
        frontendPort: backend.frontendPort
        backendPort: backend.frontendPort
        enableFloatingIP: false
        enableTcpReset: true
        idleTimeoutInMinutes: 30
        disableOutboundSnat: true
        frontendIPConfiguration: {
          id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, frontendName)
        }
        backendAddressPool: {
          id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, backendPoolName)
        }
        probe: {
          id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, probeName)
        }
      }
    }]
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' existing = {
  name: networkSecurityGroupName
}

resource securityRules 'Microsoft.Network/networkSecurityGroups/securityRules@2024-05-01' = [for (backend, index) in backends: {
  parent: networkSecurityGroup
  name: 'Allow-PrivateLink-${backend.name}'
  properties: {
    priority: 200 + index
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: string(backend.frontendPort)
    sourceAddressPrefix: 'VirtualNetwork'
    destinationAddressPrefix: '*'
  }
}]

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource updateHaproxyConfig 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  parent: vm
  name: 'update-haproxy-backends'
  location: location
  properties: {
    source: {
      script: format('''
set -euo pipefail

new_config=$(mktemp)
backup_config=$(mktemp)
trap 'rm -f "$new_config" "$backup_config"' EXIT

printf '%s' '{0}' | base64 --decode > "$new_config"
haproxy -c -f "$new_config"

cp /etc/haproxy/haproxy.cfg "$backup_config"
install -o root -g root -m 0644 "$new_config" /etc/haproxy/haproxy.cfg

if ! systemctl reload haproxy; then
    install -o root -g root -m 0644 "$backup_config" /etc/haproxy/haproxy.cfg
    systemctl restart haproxy
    exit 1
fi
  ''', encodedHaproxyConfig)
    }
    timeoutInSeconds: 300
    asyncExecution: false
    treatFailureAsDeploymentFailure: true
  }
  dependsOn: [
    loadBalancer
    securityRules
  ]
}

output configuredBackends array = [for backend in backends: {
  name: backend.name
  frontendPort: backend.frontendPort
  servers: length(backend.servers)
}]
