/*
  Configures a Databricks Network Connectivity Config (NCC) and a private endpoint
  rule pointing at the Azure Private Link Service deployed by ../modules/private-link-service.bicep,
  per the "Next Steps" in the repo README:
    1. Configure the Serverless Databricks workspace to use an NCC.
    2. In the NCC, establish a private endpoint to the Private Link Service.

  Requires an account-level Databricks provider (service principal or Azure CLI
  identity with Account Admin rights) since NCC resources are account-scoped.
*/

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    databricks = {
      source                = "databricks/databricks"
      version               = "~> 1.55"
      configuration_aliases = [databricks.account]
    }
  }
}

variable "databricks_account_id" {
  description = "Databricks account ID (found in the Account Console)."
  type        = string
}

variable "databricks_account_host" {
  description = "Databricks account console host."
  type        = string
  default     = "https://accounts.azuredatabricks.net"
}

variable "databricks_workspace_id" {
  description = "Numeric ID of the existing Databricks workspace to bind the NCC to."
  type        = string
}

variable "region" {
  description = "Azure region of the Databricks workspace, in Databricks region format (e.g. westus2)."
  type        = string
}

variable "prefix" {
  description = "Naming prefix used for the NCC. Must match ^[0-9a-zA-Z-_]{3,30}$."
  type        = string
  default     = "dbx-sqlproxy"
}

variable "private_link_service_resource_id" {
  description = "Resource ID of the Private Link Service (output 'privateLinkServiceId' from main.bicep)."
  type        = string
}

variable "private_link_service_domain_names" {
  description = "Domain name(s) clients use to reach the Private Link Service, e.g. the on-prem SQL Server FQDN behind HAProxy."
  type        = list(string)
}

provider "databricks" {
  alias      = "account"
  host       = var.databricks_account_host
  account_id = var.databricks_account_id
  auth_type  = "azure-cli"
}

resource "databricks_mws_network_connectivity_config" "ncc" {
  provider = databricks.account
  name     = "${var.prefix}-ncc"
  region   = var.region
}

resource "databricks_mws_ncc_binding" "this" {
  provider                        = databricks.account
  network_connectivity_config_id  = databricks_mws_network_connectivity_config.ncc.network_connectivity_config_id
  workspace_id                    = var.databricks_workspace_id
}

resource "databricks_mws_ncc_private_endpoint_rule" "pls" {
  provider                       = databricks.account
  network_connectivity_config_id = databricks_mws_network_connectivity_config.ncc.network_connectivity_config_id
  resource_id                    = var.private_link_service_resource_id
  domain_names                   = var.private_link_service_domain_names
}

output "network_connectivity_config_id" {
  value = databricks_mws_network_connectivity_config.ncc.network_connectivity_config_id
}

output "private_endpoint_rule_id" {
  value = databricks_mws_ncc_private_endpoint_rule.pls.rule_id
}

output "private_endpoint_connection_state" {
  description = "Approve the pending private endpoint connection on the Private Link Service in Azure if this is not ESTABLISHED (unless auto-approval is configured)."
  value       = databricks_mws_ncc_private_endpoint_rule.pls.connection_state
}
