# Databricks Serverless SQL Proxy

Deploys an HAProxy Ubuntu VM behind an internal Standard Load Balancer and Azure Private Link Service.

## Prerequisites

- Existing subnet with routing to on-premises through vWAN/ExpressRoute.
- Private Link service network policies disabled on that subnet.
- Outbound package access for cloud-init to install HAProxy, either directly or through the customer's approved egress path.
- Return routing and firewall access from the on-premises SQL Server to the HAProxy subnet.

```bash
az network vnet subnet update \
  --resource-group <network-rg> \
  --vnet-name <vnet> \
  --name <subnet> \
  --disable-private-link-service-network-policies true

az deployment group create \
  --resource-group <deployment-rg> \
  --template-file main.bicep \
  --parameters examples/main.bicepparam
```

## Validate

```bash
az vm run-command invoke \
  --resource-group <deployment-rg> \
  --name dbx-sqlproxy-prod-vm \
  --command-id RunShellScript \
  --scripts 'haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl is-active haproxy'
```

This baseline uses one VM. Use two zonal VMs for production availability.
