using Microsoft.Extensions.Logging;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.Redis;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Cosmos.Linq;

public class RedisTrigger
{
    private readonly ILogger<RedisTrigger> logger;

    public RedisTrigger(ILogger<RedisTrigger> logger)
    {
        this.logger = logger;
    }

    // This function will be invoked when a key expires in Redis. It then queries Cosmos DB for the key and its value. Finally, it uses an Azure Function output binding to write the updated key and value back to Redis .
   [Function("ExpireTrigger")]
   [RedisOutput(Common.connectionString, "SET")] //Redis output binding. This specifies that the returned value will be written to Redis using the SET command.

    //Trigger on Redis key expiration, and use an CosmosDB input binding to query the key and value from Cosmos DB.
    public static async Task<String> ExpireTrigger(
        [RedisPubSubTrigger(Common.connectionString, "__keyevent@0__:expired")] Common.ChannelMessage channelMessage,
        FunctionContext context,
        [CosmosDBInput(
            "myDatabase", //Cosmos DB database name
            "Inventory", //Cosmos DB container name
            Connection = "CosmosDbConnection" //Parameter name for the connection string in a environmental variable or local.settings.json
            )] Container container
        )    
        {
            var logger = context.GetLogger("RedisTrigger");
            var redisKey = channelMessage.Message; //The key that has expired in Redis
            logger.LogInformation($"Key '{redisKey}' has expired.");

            //Query Cosmos DB for the key and value
            IOrderedQueryable<CosmosData> queryable = container.GetItemLinqQueryable<CosmosData>();
            using FeedIterator<CosmosData> feed = queryable
                .Where(b => b.item == redisKey) //item name must be the same as the key in Redis
                .ToFeedIterator<CosmosData>();
            FeedResponse<CosmosData> response = await feed.ReadNextAsync();

            CosmosData data = response.FirstOrDefault(defaultValue: null);
            if (data != null)
            {
                logger.LogInformation($"Key: \"{data.item}\", Value: \"{data.price}\" added to Redis.");
                return $"{redisKey} {data.price}"; //Return the key and value to be written to Redis
            }
            else
            {
                logger.LogInformation($"Key not found");
                return $"{redisKey} false"; //set the value of the key to "false" if not found in Cosmos DB
            }
        }
}