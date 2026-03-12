defmodule ExVc.VerificationResult do
  @moduledoc """
  Normalized verification result for credential proof formats.
  """

  @enforce_keys [:credential, :format, :verified]
  defstruct [
    :credential,
    :proof,
    :representation,
    :warnings,
    :metadata,
    format: :unknown,
    verified: false
  ]

  @typedoc "Supported credential proof representations."
  @type format :: :jwt_vc | :data_integrity | :sd_jwt_vc | :unknown

  @typedoc "Verification result."
  @type t :: %__MODULE__{
          credential: map(),
          proof: map() | nil,
          representation: String.t() | map() | nil,
          warnings: [String.t()] | nil,
          metadata: map() | nil,
          format: format(),
          verified: boolean()
        }
end
