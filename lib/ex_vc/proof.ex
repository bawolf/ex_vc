defmodule ExVc.Proof do
  @moduledoc """
  Behaviour for VC proof representations.
  """

  alias ExVc.ValidationReport
  alias ExVc.VerificationResult

  @typedoc "Proof module result."
  @type result(value) :: {:ok, value} | {:error, atom()}

  @callback sign(map(), JOSE.JWK.t() | map(), keyword()) :: result(String.t() | map())
  @callback verify(String.t() | map(), keyword()) :: result(VerificationResult.t())
  @callback validate(map()) :: :ok | {:error, ValidationReport.t()}
end
