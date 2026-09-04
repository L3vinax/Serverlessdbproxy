# Databricks Serverless SQL Proxy

Deploys an HAProxy Ubuntu VM behind an internal Standard Load Balancer and Azure Private Link Service.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FL3vinax%2FServerlessdbproxy%2Fmain%2Fazuredeploy.json)

## Update HAProxy Backends

Use this deployment to update the existing load balancer rules, NSG rules, and HAProxy configuration.

[![Update HAProxy Backends](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FL3vinax%2FServerlessdbproxy%2Fmain%2Fupdate-haproxy-backends.json)

The backend list is authoritative. Include every existing listener and backend that should remain after the update.

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

This scirpt is provided as-is. Please validate all deployments.