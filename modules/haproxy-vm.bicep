param name string
param location string
param tags object = {}
param subnetResourceId string
param nsgResourceId string
param backendPoolId string
param adminUsername string
@description('OpenSSH public key text in ssh-rsa or ssh-ed25519 format. Supply the contents of the .pub file, not its path or a private key.')
@secure()
param sshPublicKey string
param vmSize string
param frontendPort int
param sqlServerAddress string
param sqlServerPort int
param maxConnections int

@description('Linux distribution for the HAProxy VM.')
@allowed([
  'Ubuntu'
  'RHEL'
])
param osType string = 'Ubuntu'

var osImages = {
  Ubuntu: {
    publisher: 'Canonical'
    offer: 'ubuntu-24_04-lts'
    sku: 'server'
    version: 'latest'
  }
  // RHEL PAYG image; if deployment fails with a marketplace terms error, run:
  // az vm image terms accept --urn RedHat:RHEL:9-lvm-gen2:latest
  RHEL: {
    publisher: 'RedHat'
    offer: 'RHEL'
    sku: '9-lvm-gen2'
    version: 'latest'
  }
}

// RHEL ships firewalld enabled and SELinux enforcing, both of which block HAProxy's non-standard listener ports by default.
var packages = osType == 'RHEL' ? ['haproxy', 'policycoreutils-python-utils'] : ['haproxy']
var packagesYaml = join(map(packages, p => '  - ${p}'), '\n')
var rhelPortSetupRuncmd = osType == 'RHEL' ? format('''
  - firewall-cmd --permanent --add-port={0}/tcp
  - firewall-cmd --permanent --add-port=8404/tcp
  - firewall-cmd --reload
  - semanage port -a -t http_port_t -p tcp {0} 2>/dev/null || semanage port -m -t http_port_t -p tcp {0}
  - semanage port -a -t http_port_t -p tcp 8404 2>/dev/null || semanage port -m -t http_port_t -p tcp 8404''', frontendPort) : ''

var nicName = '${name}-nic'
var cloudInit = format('''#cloud-config
package_update: true
packages:
{0}

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
          maxconn {1}

      defaults
          log global
          mode tcp
          option tcplog
          option dontlognull
          timeout connect 10s
          timeout client 1h
          timeout server 1h

      frontend sql_frontend
          bind 0.0.0.0:{2}
          default_backend sql_backend

      backend sql_backend
          option tcp-check
          server sql01 {3}:{4} check inter 5s fall 3 rise 2

      listen health
          bind 0.0.0.0:8404
          mode http
          monitor-uri /health

runcmd:
  - haproxy -c -f /etc/haproxy/haproxy.cfg
{5}
  - systemctl enable haproxy
  - systemctl restart haproxy
''', packagesYaml, maxConnections, frontendPort, sqlServerAddress, sqlServerPort, rhelPortSetupRuncmd)

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
              keyData: trim(sshPublicKey)
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: osImages[osType]
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
