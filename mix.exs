defmodule Smartcitiesdata.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      description: description()
    ]
  end

  defp deps, do: []

  defp aliases do
    [
      test: "cmd mix test --color",
      "test.e2e": "cmd --app e2e mix test.integration --color --include e2e",
      sobelow: "cmd --app andi mix sobelow -i Config.HTTPS --skip --compact --exit low"
    ]
  end

  defp description, do: "A data ingestion and processing platform for the next generation."

  defp docs() do
    [
      main: "readme",
      source_url: "https://github.com/smartcitiesdata/smartcitiesdata.git",
      extras: [
        "README.md",
        "apps/andi/README.md",
        "apps/reaper/README.md",
        "apps/valkyrie/README.md",
        "apps/odo/README.md",
        "apps/discovery_streams/README.md",
        "apps/forklift/README.md",
        "apps/flair/README.md"
      ]
    ]
  end
end
