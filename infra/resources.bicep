param prefix string
param location string = resourceGroup().location
param tags object = {}

// cosmosdb parameters and variables
param cosmosDBDatabaseThroughput int = 400
var cosmosDBDatabaseName = 'myDatabase'
var cosmosDBContainerName = 'Inventory'
var cosmosDBContainerPartitionKey = '/id'

// storage account parameters and variables
@description('Storage Account type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountType string = 'Standard_LRS'

// function app parameters and variables
@description('The language worker runtime to load in the function app.')
@allowed([
  'node'
  'dotnet'
  'dotnet-isolated'
  'java'
  'python'
  'powershell'
])
param runtime string = 'dotnet-isolated' //use the dotnet-isolated worker runtime

// set runtime version specifically to .NET 8.0
param linuxFxVersion string = 'DOTNET-ISOLATED|8.0'

var functionAppName = '${prefix}-function-${uniqueString(resourceGroup().id)}'
var hostingPlanName = '${prefix}-plan-${uniqueString(resourceGroup().id)}'
var applicationInsightsName = '${prefix}-appinsights-${uniqueString(resourceGroup().id)}'
var storageAccountName = '${prefix}${uniqueString(resourceGroup().id)}'
var functionWorkerRuntime = runtime

// create a redis cache with keyspace notifications configured
resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: '${prefix}-redis-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Standard'
      family: 'C'
      capacity: 0
    }
    redisConfiguration: {
      'notify-keyspace-events': 'KEA'
    }
    enableNonSslPort: false
  }
}

// create an application insights instance to monitor the function app
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

// create a cosmosdb account
resource cosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: '${prefix}-cosmosdb-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
  }
}

// create a cosmosdb database and container
resource cosmosDBDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2020-04-01' = {
  parent: cosmosDBAccount
  name: cosmosDBDatabaseName
  tags: tags
  properties: {
    resource: {
      id: cosmosDBDatabaseName
    }
    options: {
      throughput: cosmosDBDatabaseThroughput
    }
  }
  resource container 'containers' = {
    name: cosmosDBContainerName
    tags: tags
    properties: {
      resource: {
        id: cosmosDBContainerName
        partitionKey: {
          kind: 'Hash'
          paths: [
            cosmosDBContainerPartitionKey
          ]
        }
      }
      options: {}
    }
  }
}

// create a storage account to store function app code and logs
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountType
  }
  kind: 'Storage'
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
}

// create a hosting plan for the function app. Consumption functions cannot be used for this example because pub/sub messages are fire-and-forget in Redis.
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  kind: 'Linux'
  sku: {
    name: 'EP1'
    tier: 'Premium'
  }
  properties: {
    reserved: true
  }
}

// create a function app to process expiration events from the Redis cache
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: union(tags, {'azd-service-name': 'expirationfunction' }) //this tells the azd extension to deploy code to this function app
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED'
          value: '1'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionWorkerRuntime
        }      
        {
          // connection string to the Redis cache. This is pulled automatically from the Redis resource that was just provisioned.
          name: 'redisConnectionString'
          value: '${redis.properties.hostName}:6380,password=${redis.listKeys().primaryKey},ssl=True,abortConnect=False'
        }
        {
          // connection string to the CosmosDB account. This is pulled automatically from the CosmosDB resource that was just provisioned.
          name: 'CosmosDbConnection'
          value: '${cosmosDBAccount.listConnectionStrings().connectionStrings[0].connectionString}'
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      linuxFxVersion: linuxFxVersion
    }
    httpsOnly: true
  }
}
