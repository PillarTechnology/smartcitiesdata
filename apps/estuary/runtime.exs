use Mix.Config

required_envars = [
  "PRESTO_USER",
  "PRESTO_URL",
  "KAFKA_BROKERS",
  "DATA_TOPIC",
  "SCHEMA_NAME",
  "TABLE_NAME",
  "DLQ_TOPIC"
]

Enum.each(required_envars, fn var ->
  if is_nil(System.get_env(var)) do
    raise ArgumentError, message: "Required environment variable #{var} is undefined"
  end
end)

kafka_brokers = System.get_env("KAFKA_BROKERS")
topic = System.get_env("DATA_TOPIC")
schema_name = System.get_env("SCHEMA_NAME")
table_name = System.get_env("TABLE_NAME")

endpoints =
  kafka_brokers
  |> String.split(",")
  |> Enum.map(&String.trim/1)
  |> Enum.map(fn entry -> String.split(entry, ":") end)
  |> Enum.map(fn [host, port] -> {host, String.to_integer(port)} end)

config :prestige,
  base_url: System.get_env("PRESTO_URL"),
  headers: [
    user: System.get_env("PRESTO_USER"),
    catalog: "hive",
    schema: schema_name
  ]

config :estuary,
  event_stream_topic: topic,
  elsa_endpoint: endpoints,
  event_stream_schema_name: schema_name,
  event_stream_table_name: table_name

config :logger,
  level: :warn

config :yeet,
  endpoint: endpoints,
  topic: System.get_env("DLQ_TOPIC")
