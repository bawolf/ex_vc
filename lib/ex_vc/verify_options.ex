defmodule ExVc.VerifyOptions do
  @moduledoc false

  @schema [
    format: [type: {:in, [:auto, :jwt_vc, :data_integrity, :sd_jwt_vc]}, default: :auto],
    jwk: [type: {:custom, __MODULE__, :validate_any, []}],
    holder_jwk: [type: {:custom, __MODULE__, :validate_any, []}],
    issuer_did: [type: :string],
    holder_did: [type: :string],
    allowed_algs: [type: {:list, :string}, default: ["ES256", "EdDSA"]],
    audience: [type: :string],
    nonce: [type: :string],
    verify_disclosures: [type: :boolean, default: true],
    fetch_json: [type: {:custom, __MODULE__, :validate_any, []}],
    method_registry: [type: {:custom, __MODULE__, :validate_any, []}],
    did_validation: [type: {:in, [:strict, :compat]}]
  ]

  defstruct [
    :format,
    :jwk,
    :holder_jwk,
    :issuer_did,
    :holder_did,
    :audience,
    :nonce,
    :fetch_json,
    :method_registry,
    :did_validation,
    allowed_algs: ["ES256", "EdDSA"],
    verify_disclosures: true
  ]

  @type t :: %__MODULE__{
          format: :auto | :jwt_vc | :data_integrity | :sd_jwt_vc,
          jwk: term(),
          holder_jwk: term(),
          issuer_did: String.t() | nil,
          holder_did: String.t() | nil,
          audience: String.t() | nil,
          nonce: String.t() | nil,
          fetch_json: term(),
          method_registry: term(),
          did_validation: :strict | :compat | nil,
          allowed_algs: [String.t()],
          verify_disclosures: boolean()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, NimbleOptions.ValidationError.t()}
  def new(opts) do
    with {:ok, validated} <- NimbleOptions.validate(opts, @schema) do
      {:ok, struct(__MODULE__, validated)}
    end
  end

  @spec validate_any(term()) :: {:ok, term()}
  def validate_any(value), do: {:ok, value}
end
