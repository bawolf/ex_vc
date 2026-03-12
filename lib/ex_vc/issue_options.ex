defmodule ExVc.IssueOptions do
  @moduledoc false

  @schema [
    id: [type: :string],
    issuer: [type: {:custom, __MODULE__, :validate_issuer, []}],
    valid_from: [type: {:custom, __MODULE__, :validate_datetime_like, []}],
    valid_until: [type: {:custom, __MODULE__, :validate_datetime_like, []}],
    credential_status: [type: {:custom, __MODULE__, :validate_map_or_list, []}],
    proof: [type: {:custom, __MODULE__, :validate_map_or_list, []}],
    jwk: [type: {:custom, __MODULE__, :validate_any, []}],
    alg: [type: :string],
    suite: [type: :string],
    verification_method: [type: :string],
    contexts: [type: {:list, :any}, default: ["https://www.w3.org/ns/credentials/v2"]],
    types: [type: {:list, :string}, default: ["VerifiableCredential"]],
    disclose_paths: [type: {:list, :string}, default: []],
    format: [type: {:in, [:map, :jwt_vc, :data_integrity, :sd_jwt_vc]}, default: :map]
  ]

  defstruct [
    :id,
    :issuer,
    :valid_from,
    :valid_until,
    :credential_status,
    :proof,
    :jwk,
    :alg,
    :suite,
    :verification_method,
    contexts: ["https://www.w3.org/ns/credentials/v2"],
    types: ["VerifiableCredential"],
    disclose_paths: [],
    format: :map
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          issuer: String.t() | map() | nil,
          contexts: [term()],
          types: [String.t()],
          valid_from: DateTime.t() | String.t() | nil,
          valid_until: DateTime.t() | String.t() | nil,
          credential_status: map() | [map()] | nil,
          proof: map() | [map()] | nil,
          format: :map | :jwt_vc | :data_integrity | :sd_jwt_vc,
          jwk: term(),
          alg: String.t() | nil,
          suite: String.t() | nil,
          verification_method: String.t() | nil,
          disclose_paths: [String.t()]
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, NimbleOptions.ValidationError.t()}
  def new(opts) do
    with {:ok, validated} <- NimbleOptions.validate(opts, @schema) do
      {:ok, struct(__MODULE__, validated)}
    end
  end

  @spec validate_any(term()) :: {:ok, term()}
  def validate_any(value), do: {:ok, value}

  @spec validate_issuer(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_issuer(value) when is_binary(value) or is_map(value), do: {:ok, value}
  def validate_issuer(_value), do: {:error, "issuer must be a string or map"}

  @spec validate_datetime_like(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_datetime_like(%DateTime{} = value), do: {:ok, value}
  def validate_datetime_like(value) when is_binary(value), do: {:ok, value}
  def validate_datetime_like(_value), do: {:error, "value must be a DateTime or ISO8601 string"}

  @spec validate_map_or_list(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_map_or_list(nil), do: {:ok, nil}
  def validate_map_or_list(value) when is_map(value) or is_list(value), do: {:ok, value}
  def validate_map_or_list(_value), do: {:error, "value must be a map or list"}
end
