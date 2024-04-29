public class Common
{
    public const string connectionString = "redisConnectionString";

    public class ChannelMessage
    {
        public string SubscriptionChannel { get; set; }
        public string Channel { get; set; }
        public string Message { get; set; }
    }
}

public record CosmosData(
        string id,
        string item,
        string price
);