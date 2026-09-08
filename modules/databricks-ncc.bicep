/*
  Calls the Databricks Account REST API directly (no Terraform/Databricks provider available in ARM/Bicep)
  to create a Network Connectivity Config (NCC), bind it to an existing workspace, and create a private
  endpoint rule to the Private Link Service deployed by ./private-link-service.bicep.

  Prerequisite (one-time, manual): the user-assigned managed identity passed in `identityResourceId` must
  be added as an Account Admin in the Databricks Account Console (https://accounts.azuredatabricks.net).
  There is no ARM API to grant this, since Databricks account admin membership is managed in Databricks, not Azure.
*/

param location string
param tags object = {}

@description('Databricks account console URL.')
param accountConsoleUrl string = 'https://accounts.azuredatabricks.net'

@description('Databricks account ID (Account Console > Settings).')
param databricksAccountId string

@description('Numeric Databricks workspace ID (not the ARM resource ID) to bind the NCC to.')
param databricksWorkspaceId string

@description('Azure region in Databricks region format (e.g. westus2). Must match the workspace region.')
param region string

@description('Name of the network connectivity configuration. Must match ^[0-9a-zA-Z-_]{3,30}$.')
param nccName string

@description('Resource ID of the Private Link Service to create a private endpoint to.')
param privateLinkServiceResourceId string

@description('Domain name(s) clients use to reach the Private Link Service, e.g. the on-prem SQL Server FQDN.')
param privateLinkServiceDomainNames array

@description('Resource ID of a user-assigned managed identity that is an Account Admin in the Databricks account.')
param identityResourceId string

@description('Change to force the script to re-run on a redeploy (defaults to current time).')
param forceUpdateTag string = utcNow()

resource ncc 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'configure-databricks-ncc'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    azCliVersion: '2.63.0'
    forceUpdateTag: forceUpdateTag
    timeout: 'PT30M'
    retentionInterval: 'P1D'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'ACCOUNT_HOST', value: accountConsoleUrl }
      { name: 'ACCOUNT_ID', value: databricksAccountId }
      { name: 'WORKSPACE_ID', value: databricksWorkspaceId }
      { name: 'REGION', value: region }
      { name: 'NCC_NAME', value: nccName }
      { name: 'PLS_RESOURCE_ID', value: privateLinkServiceResourceId }
      { name: 'DOMAIN_NAMES_JSON', value: string(privateLinkServiceDomainNames) }
    ]
    scriptContent: '''
      set -euo pipefail

      TOKEN=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv)
      BASE="$ACCOUNT_HOST/api/2.0/accounts/$ACCOUNT_ID"
      AUTH_HEADER="Authorization: Bearer $TOKEN"

      echo "Creating network connectivity configuration '$NCC_NAME' in $REGION..."
      NCC_BODY=$(python3 -c 'import json,os; print(json.dumps({"name": os.environ["NCC_NAME"], "region": os.environ["REGION"]}))')
      NCC_JSON=$(curl -sf -X POST "$BASE/network-connectivity-configs" -H "$AUTH_HEADER" -H "Content-Type: application/json" -d "$NCC_BODY")
      NCC_ID=$(echo "$NCC_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["network_connectivity_config_id"])')
      export NCC_ID
      echo "Created NCC $NCC_ID"

      echo "Binding NCC to workspace $WORKSPACE_ID..."
      BIND_BODY=$(python3 -c 'import json,os; print(json.dumps({"network_connectivity_config_id": os.environ["NCC_ID"]}))')
      curl -sf -X PATCH "$BASE/workspaces/$WORKSPACE_ID" -H "$AUTH_HEADER" -H "Content-Type: application/json" -d "$BIND_BODY" > /dev/null

      echo "Creating private endpoint rule to $PLS_RESOURCE_ID..."
      RULE_BODY=$(python3 -c 'import json,os; print(json.dumps({"resource_id": os.environ["PLS_RESOURCE_ID"], "domain_names": json.loads(os.environ["DOMAIN_NAMES_JSON"])}))')
      RULE_JSON=$(curl -sf -X POST "$BASE/network-connectivity-configs/$NCC_ID/private-endpoint-rules" -H "$AUTH_HEADER" -H "Content-Type: application/json" -d "$RULE_BODY")
      RULE_ID=$(echo "$RULE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["rule_id"])')
      CONNECTION_STATE=$(echo "$RULE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["connection_state"])')
      export RULE_ID CONNECTION_STATE
      echo "Created private endpoint rule $RULE_ID (connection_state=$CONNECTION_STATE)"

      python3 -c 'import json,os; print(json.dumps({"networkConnectivityConfigId": os.environ["NCC_ID"], "privateEndpointRuleId": os.environ["RULE_ID"], "connectionState": os.environ["CONNECTION_STATE"]}))' > "$AZ_SCRIPTS_OUTPUT_PATH"
    '''
  }
}

output networkConnectivityConfigId string = ncc.properties.outputs.networkConnectivityConfigId
output privateEndpointRuleId string = ncc.properties.outputs.privateEndpointRuleId
output connectionState string = ncc.properties.outputs.connectionState
