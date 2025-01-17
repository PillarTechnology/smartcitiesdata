use Mix.Config

config :forklift,
  topic_writer: MockTopic,
  table_writer: MockTable,
  message_processing_cadence: 15_000,
  user: "forklift"

config :prestige, base_url: "http://127.0.0.1:8080"

config :redix,
       args: [host: "localhost"]

config :forklift, :brook,
  instance: :forklift,
  handlers: [Forklift.EventHandler],
  storage: [
    module: Brook.Storage.Ets,
    init_arg: [
      namespace: "forklift:view"
    ]
  ]

config :forklift, :dead_letter,
  driver: [
    module: DeadLetter.Carrier.Test,
    init_args: []
  ]

config :libcluster,
  topologies: [
    forklift_cluster: [
      strategy: Elixir.Cluster.Strategy.Epmd,
      config: [
        hosts: [:"a@127.0.0.1", :"b@127.0.0.1"]
      ]
    ]
  ]
