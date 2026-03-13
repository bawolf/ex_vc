defmodule ExVc.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/bawolf/ex_vc"

  def project do
    [
      app: :ex_vc,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Verifiable Credentials 2.0 validation, VP boundaries, and vc+jwt support for Elixir.",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "SUPPORTED_FEATURES.md",
          "INTEROP_NOTES.md",
          "FIXTURE_POLICY.md",
          "RELEASE_CHECKLIST.md",
          "CHANGELOG.md",
          "LICENSE"
        ],
        source_ref: "v#{@version}",
        source_url: @source_url
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key],
      mod: {ExVc.Application, []}
    ]
  end

  defp deps do
    [
      ex_did_dep(),
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:jason, "~> 1.4"},
      {:jose, "~> 1.11"},
      {:nimble_options, "~> 1.1"},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp ex_did_dep do
    if System.get_env("EX_VC_USE_LOCAL_DEPS") == "1" do
      {:ex_did, path: "../ex_did"}
    else
      {:ex_did, "~> 0.1.2"}
    end
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Bryant Wolf"],
      links: %{
        "GitHub" => @source_url,
        "Hex" => "https://hex.pm/packages/ex_vc",
        "Docs" => "https://hexdocs.pm/ex_vc",
        "CI" => "#{@source_url}/actions/workflows/ci.yml",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Fixture Policy" => "#{@source_url}/blob/main/FIXTURE_POLICY.md",
        "Interop Notes" => "#{@source_url}/blob/main/INTEROP_NOTES.md",
        "Supported Features" => "#{@source_url}/blob/main/SUPPORTED_FEATURES.md",
        "License" => "#{@source_url}/blob/main/LICENSE"
      }
    ]
  end
end
