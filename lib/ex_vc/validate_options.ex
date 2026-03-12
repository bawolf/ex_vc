defmodule ExVc.ValidateOptions do
  @moduledoc false

  @schema [
    required_types: [type: {:list, :string}, default: []],
    validators: [type: {:list, {:fun, 2}}, default: []]
  ]

  @type t :: %__MODULE__{
          required_types: [String.t()],
          validators: [function()]
        }

  defstruct required_types: [], validators: []

  @spec new(keyword()) :: {:ok, t()} | {:error, NimbleOptions.ValidationError.t()}
  def new(opts) do
    with {:ok, validated} <- NimbleOptions.validate(opts, @schema) do
      {:ok, struct(__MODULE__, validated)}
    end
  end
end
