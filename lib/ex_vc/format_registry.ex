defmodule ExVc.FormatRegistry do
  @moduledoc false

  @spec proof_module(:jwt_vc | :data_integrity | :sd_jwt_vc) :: module()
  def proof_module(:jwt_vc), do: ExVc.JwtVc
  def proof_module(:data_integrity), do: ExVc.DataIntegrity
  def proof_module(:sd_jwt_vc), do: ExVc.SdJwtVc

  @spec detect(term()) :: :jwt_vc | :data_integrity | :sd_jwt_vc | :unknown
  def detect(%{"proof" => %{"type" => "DataIntegrityProof"}}), do: :data_integrity
  def detect(%{"proof" => proofs}) when is_list(proofs), do: detect_proof_list(proofs)
  def detect(value) when is_binary(value), do: detect_string(value)
  def detect(_value), do: :unknown

  defp detect_string(value) do
    cond do
      String.contains?(value, "~") -> :sd_jwt_vc
      length(String.split(value, ".", parts: 4)) == 3 -> :jwt_vc
      true -> :unknown
    end
  end

  defp detect_proof_list(proofs) do
    if Enum.any?(proofs, &match?(%{"type" => "DataIntegrityProof"}, &1)) do
      :data_integrity
    else
      :unknown
    end
  end
end
