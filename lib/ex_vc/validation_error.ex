defmodule ExVc.ValidationError do
  @moduledoc """
  Stable validation error shape returned by `ExVc`.
  """

  @enforce_keys [:field, :code, :message]
  defstruct [:field, :code, :message]

  @typedoc "Validation error entry."
  @type t :: %__MODULE__{
          field: String.t(),
          code: String.t(),
          message: String.t()
        }

  @spec new(String.t(), String.t(), String.t()) :: t()
  def new(field, code, message) do
    %__MODULE__{field: field, code: code, message: message}
  end
end
