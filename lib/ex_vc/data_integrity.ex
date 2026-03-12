defmodule ExVc.DataIntegrity do
  @moduledoc false

  @behaviour ExVc.Proof

  alias ExVc.JsonCanonicalization
  alias ExVc.VerificationKeys
  alias ExVc.VerificationResult

  @supported_suites %{
    "eddsa-jcs-2022" => "EdDSA",
    "ecdsa-jcs-2019" => "ES256"
  }

  @spec supported_suites() :: [String.t()]
  def supported_suites, do: Map.keys(@supported_suites)

  @impl true
  @spec sign(map(), JOSE.JWK.t() | map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def sign(credential, jwk, opts \\ [])

  def sign(credential, jwk, opts) when is_map(credential) do
    with {:ok, _report} <- ExVc.validate(Map.delete(credential, "proof")),
         {:ok, signing_jwk} <- normalize_jwk(jwk),
         {:ok, suite, alg} <- suite_and_alg(opts),
         canonical <- canonical_payload(credential),
         proof_value <- compact_signature(signing_jwk, canonical, alg),
         proof <- build_proof(proof_value, suite, opts) do
      {:ok, Map.put(credential, "proof", proof)}
    else
      {:error, %ExVc.ValidationReport{}} -> {:error, :invalid_vc}
      {:error, reason} -> {:error, reason}
    end
  end

  def sign(_credential, _jwk, _opts), do: {:error, :invalid_vc}

  @impl true
  @spec verify(map(), keyword()) :: {:ok, VerificationResult.t()} | {:error, atom()}
  def verify(credential, opts \\ [])

  def verify(%{} = credential, opts) do
    with {:ok, proof} <- extract_proof(credential),
         {:ok, suite, alg} <- suite_and_alg(proof: proof),
         {:ok, jwks} <-
           VerificationKeys.proof_jwks(
             opts,
             credential,
             proof,
             :missing_data_integrity_key,
             :invalid_data_integrity_key
           ),
         canonical <- canonical_payload(credential),
         {:ok, verified_payload, _verified_jws, _verified_jwk} <-
           VerificationKeys.verify_compact(jwks, [alg], proof["proofValue"]),
         true <- verified_payload == canonical,
         {:ok, _report} <- ExVc.validate(credential) do
      {:ok,
       %VerificationResult{
         credential: credential,
         proof: proof,
         representation: credential,
         metadata: %{"cryptosuite" => suite},
         format: :data_integrity,
         verified: true
       }}
    else
      {:error, %ExVc.ValidationReport{}} -> {:error, :invalid_vc}
      {:error, :invalid_signature} -> {:error, :invalid_data_integrity_signature}
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_data_integrity_payload}
    end
  end

  def verify(_credential, _opts), do: {:error, :invalid_data_integrity}

  @impl true
  @spec validate(map()) :: :ok | {:error, ExVc.ValidationReport.t()}
  def validate(%{} = credential) do
    case ExVc.validate(credential) do
      {:ok, _report} -> :ok
      {:error, report} -> {:error, report}
    end
  end

  defp extract_proof(%{"proof" => %{"type" => "DataIntegrityProof"} = proof}), do: {:ok, proof}

  defp extract_proof(%{"proof" => proofs}) when is_list(proofs) do
    case Enum.find(proofs, &match?(%{"type" => "DataIntegrityProof"}, &1)) do
      %{} = proof -> {:ok, proof}
      nil -> {:error, :missing_data_integrity_proof}
    end
  end

  defp extract_proof(_credential), do: {:error, :missing_data_integrity_proof}

  defp suite_and_alg(opts) do
    suite = Keyword.get(opts, :suite)
    alg = Keyword.get(opts, :alg)
    proof_suite = get_in(opts, [:proof, "cryptosuite"])

    cond do
      is_binary(proof_suite) and proof_suite in supported_suites() ->
        {:ok, proof_suite, Map.fetch!(@supported_suites, proof_suite)}

      is_binary(proof_suite) ->
        {:error, :unsupported_data_integrity_suite}

      is_binary(suite) and suite in supported_suites() ->
        {:ok, suite, Map.fetch!(@supported_suites, suite)}

      is_binary(suite) ->
        {:error, :unsupported_data_integrity_suite}

      is_binary(alg) and alg in ["EdDSA", "ES256"] ->
        {:ok, suite_for_alg(alg), alg}

      true ->
        {:ok, "ecdsa-jcs-2019", "ES256"}
    end
  end

  defp suite_for_alg("EdDSA"), do: "eddsa-jcs-2022"
  defp suite_for_alg("ES256"), do: "ecdsa-jcs-2019"

  defp build_proof(proof_value, suite, opts) do
    %{
      "type" => "DataIntegrityProof",
      "cryptosuite" => suite,
      "proofPurpose" => Keyword.get(opts, :proof_purpose, "assertionMethod"),
      "verificationMethod" => Keyword.get(opts, :verification_method, "did:key:issuer#key-1"),
      "created" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "proofValue" => proof_value
    }
  end

  defp canonical_payload(credential) do
    credential
    |> Map.delete("proof")
    |> JsonCanonicalization.encode()
  end

  defp compact_signature(jwk, canonical, alg) do
    JOSE.JWS.sign(jwk, canonical, %{"alg" => alg, "typ" => "application/data-integrity-proof+jws"})
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp normalize_jwk(%JOSE.JWK{} = jwk), do: {:ok, jwk}

  defp normalize_jwk(jwk) when is_map(jwk) do
    try do
      {:ok, JOSE.JWK.from_map(jwk)}
    rescue
      _ -> {:error, :invalid_data_integrity_key}
    end
  end

  defp normalize_jwk(_jwk), do: {:error, :invalid_data_integrity_key}
end
