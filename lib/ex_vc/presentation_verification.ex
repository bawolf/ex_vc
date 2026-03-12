defmodule ExVc.PresentationVerification do
  @moduledoc """
  Verifiable Presentation verification result.
  """

  @enforce_keys [:presentation, :verified]
  defstruct [:presentation, :credentials, :warnings, :metadata, verified: false]

  @type t :: %__MODULE__{
          presentation: map(),
          credentials: [ExVc.VerificationResult.t() | map() | String.t()] | nil,
          warnings: [String.t()] | nil,
          metadata: map() | nil,
          verified: boolean()
        }
end
