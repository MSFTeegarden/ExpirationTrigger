targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// this tag tells azd which environment to use. The 'expirationfunction' name refers to the app in the azure.yaml file
var tags = {
  'azd-env-name': environmentName
}

// Create a new resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: '${environmentName}-rg'
  location: location
  tags: tags
}

// Deploy the resources in the resources.bicep file these resources are in a seprarate module because the scope of the resources is the resource group, not the subscription.
module resources './resources.bicep' = {
  name: 'resources'
  params: {
    prefix: environmentName
    location: location
    tags: tags
  }
  scope : resourceGroup
}
