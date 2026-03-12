defmodule ExVc.ValidationReport do
  @moduledoc """
  Validation report returned by `ExVc.validate/2`.
  """

  alias ExVc.Credential
  alias ExVc.ValidationError

  @enforce_keys [:credential, :parsed, :errors]
  defstruct [:credential, :parsed, :errors]

  @typedoc "Validation report for a VC payload."
  @type t :: %__MODULE__{
          credential: map(),
          parsed: %{
            valid_from: DateTime.t() | nil,
            valid_until: DateTime.t() | nil,
            normalized: Credential.t() | nil
          },
          errors: [ValidationError.t()]
        }

  @spec new(map(), Credential.t() | nil, [ValidationError.t()]) :: t()
  def new(credential, normalized, errors) do
    %__MODULE__{
      credential: credential,
      parsed: %{
        valid_from: normalized && normalized.valid_from,
        valid_until: normalized && normalized.valid_until,
        normalized: normalized
      },
      errors: errors
    }
  end
end
