param name string
param location string
param tags object = {}
param subnetResourceId string
param nsgResourceId string
param backendPoolId string
param adminUsername string
@secure()
param sshPublicKey string
param vmSize string
param frontendPort int
param sqlServerAddress string
param sqlServerPort int
param maxConnections int

var nicName = '${name}-nic'
var cloudInit = format('''#cloud-config
package_update: true
packages:
  - haproxy

write_files:
  - path: /etc/haproxy/haproxy.cfg
    owner: root:root
    permissions: '0644'
    content: |
      global
          log /dev/log local0
          log /dev/log local1 notice
          user haproxy
          group haproxy
          daemon
          maxconn {0}

      defaults
          log global
          mode tcp
          option tcplog
          option dontlognull
          timeout connect 10s
          timeout client 1h
          timeout server 1h

      frontend sql_frontend
          bind 0.0.0.0:{1}
          default_backend sql_backend

      backend sql_backend
          option tcp-check
          server sql01 {2}:{3} check inter 5s fall 3 rise 2

      listen health
          bind 0.0.0.0:8404
          mode http
          monitor-uri /health

runcmd:
  - haproxy -c -f /etc/haproxy/haproxy.cfg
  - systemctl enable haproxy
  - systemctl restart haproxy
''', maxConnections, frontendPort, sqlServerAddress, sqlServerPort)

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    enableAcceleratedNetworking: true
    networkSecurityGroup: { id: nsgResourceId }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: subnetResourceId }
          loadBalancerBackendAddressPools: [
            { id: backendPoolId }
          ]
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    osProfile: {
      computerName: take(name, 64)
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        patchSettings: {
          assessmentMode: 'AutomaticByPlatform'
          patchMode: 'AutomaticByPlatform'
        }
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: { storageAccountType: 'Premium_LRS' }
        diskSizeGB: 64
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic.id }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: { enabled: true }
    }
  }
}

output vmId string = vm.id
output vmName string = vm.name
output nicId string = nic.id
