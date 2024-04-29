targetScope = 'subscription'

@minLength(1)
@maxLength(7)
@description('Provide a common prefix for all resources in this example. This will help avoid name collisions. Max length is 7 characters.')
param prefix string

// feel free to change this to the region of your choice
param location string = 'eastus'

// this tag tells azd which environment to use. The 'expirationfunction' name refers to the app in the azure.yaml file
var tags = {
  'azd-env-name': 'expirationfunction'
}

// Create a new resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: '${prefix}-rg'
  location: location
  tags: tags
}

// Deploy the resources in the resources.bicep file these resources are in a seprarate module because the scope of the resources is the resource group, not the subscription.
module resources './resources.bicep' = {
  name: 'resources'
  params: {
    prefix: prefix
    location: location
    tags: tags
  }
  scope : resourceGroup
}
