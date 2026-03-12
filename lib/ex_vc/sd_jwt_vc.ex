defmodule ExVc.SdJwtVc do
  @moduledoc false

  @behaviour ExVc.Proof

  alias ExVc.VerificationKeys
  alias ExVc.VerificationResult

  @default_typ "dc+sd-jwt"
  @default_hash "sha-256"

  @type parsed_representation :: %{
          issuer_jwt: String.t(),
          disclosures: [String.t()],
          key_binding_jwt: String.t() | nil
        }

  @impl true
  @spec sign(map(), JOSE.JWK.t() | map(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def sign(credential, jwk, opts \\ [])

  def sign(%{} = credential, jwk, opts) do
    with {:ok, _report} <- ExVc.validate(credential),
         {:ok, signing_jwk} <- normalize_jwk(jwk),
         {:ok, disclosure_result} <-
           disclosure_payload(credential, Keyword.get(opts, :disclose_paths, [])),
         {:ok, issuer_jwt} <- sign_issuer_jwt(disclosure_result.claims, signing_jwk, opts),
         bound_representation <-
           build_bound_representation(issuer_jwt, disclosure_result.disclosures),
         {:ok, key_binding_jwt} <- maybe_sign_key_binding(bound_representation, opts) do
      parts =
        [issuer_jwt | disclosure_result.disclosures]
        |> maybe_append_key_binding(key_binding_jwt)

      {:ok, Enum.join(parts, "~")}
    else
      {:error, %ExVc.ValidationReport{}} -> {:error, :invalid_vc}
      {:error, reason} -> {:error, reason}
    end
  end

  def sign(_credential, _jwk, _opts), do: {:error, :invalid_vc}

  @impl true
  @spec verify(String.t(), keyword()) :: {:ok, VerificationResult.t()} | {:error, atom()}
  def verify(representation, opts \\ [])

  def verify(representation, opts) when is_binary(representation) do
    with {:ok, parsed} <- parse(representation),
         {:ok, issuer_claims, issuer_header} <- verify_issuer_jwt(parsed.issuer_jwt, opts),
         :ok <- validate_sd_alg(issuer_claims),
         {:ok, credential} <-
           apply_disclosures(
             issuer_claims,
             parsed.disclosures,
             Keyword.get(opts, :verify_disclosures, true)
           ),
         :ok <- maybe_verify_key_binding(parsed, credential, opts),
         {:ok, _report} <- ExVc.validate(credential) do
      {:ok,
       %VerificationResult{
         credential: credential,
         proof: issuer_header,
         representation: representation,
         metadata: %{
           "disclosures" => length(parsed.disclosures),
           "keyBinding" => not is_nil(parsed.key_binding_jwt)
         },
         format: :sd_jwt_vc,
         verified: true
       }}
    else
      {:error, %ExVc.ValidationReport{}} -> {:error, :invalid_vc}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(_representation, _opts), do: {:error, :invalid_sd_jwt_vc}

  @impl true
  @spec validate(map()) :: :ok | {:error, ExVc.ValidationReport.t()}
  def validate(credential) do
    case ExVc.validate(credential) do
      {:ok, _report} -> :ok
      {:error, report} -> {:error, report}
    end
  end

  @spec parse(String.t()) :: {:ok, parsed_representation()} | {:error, atom()}
  def parse(representation) when is_binary(representation) do
    case String.split(representation, "~") do
      [issuer_jwt | disclosures] when issuer_jwt != "" ->
        {disclosures, key_binding_jwt} = split_key_binding(disclosures)

        {:ok,
         %{
           issuer_jwt: issuer_jwt,
           disclosures: Enum.reject(disclosures, &(&1 == "")),
           key_binding_jwt: key_binding_jwt
         }}

      _ ->
        {:error, :invalid_sd_jwt_vc}
    end
  end

  def parse(_representation), do: {:error, :invalid_sd_jwt_vc}

  defp disclosure_payload(credential, disclose_paths) do
    {base_credential, disclosures, digests} =
      Enum.reduce(disclose_paths, {credential, [], []}, fn path,
                                                           {acc_credential, acc_disclosures,
                                                            acc_digests} ->
        case pop_path(acc_credential, String.split(path, ".")) do
          {:ok, value, next_credential} ->
            disclosure = build_disclosure(path, value)

            {next_credential, acc_disclosures ++ [disclosure],
             acc_digests ++ [digest(disclosure)]}

          :error ->
            {acc_credential, acc_disclosures, acc_digests}
        end
      end)

    claims =
      %{
        "vc" => base_credential,
        "_sd_alg" => @default_hash
      }
      |> maybe_put_sd(digests)

    {:ok, %{claims: claims, disclosures: disclosures}}
  end

  defp sign_issuer_jwt(claims, jwk, opts) do
    alg = Keyword.get(opts, :alg, "ES256")

    header = %{"alg" => alg, "typ" => Keyword.get(opts, :typ, @default_typ)}

    claims
    |> Jason.encode!()
    |> then(fn payload -> JOSE.JWS.sign(jwk, payload, header) end)
    |> JOSE.JWS.compact()
    |> then(fn {_jws, jwt} -> {:ok, jwt} end)
  end

  defp maybe_sign_key_binding(_bound_representation, opts)
       when not is_list(opts),
       do: {:ok, nil}

  defp maybe_sign_key_binding(bound_representation, opts) do
    holder_jwk = Keyword.get(opts, :holder_jwk)

    if holder_jwk do
      with {:ok, jwk} <- normalize_jwk(holder_jwk) do
        alg = Keyword.get(opts, :holder_alg, "ES256")
        header = %{"alg" => alg, "typ" => "kb+jwt"}

        claims = %{
          "iat" => System.system_time(:second),
          "aud" => Keyword.get(opts, :audience, "delegate"),
          "nonce" => Keyword.get(opts, :nonce, "nonce"),
          "sd_hash" => digest(bound_representation)
        }

        claims
        |> Jason.encode!()
        |> then(fn payload -> JOSE.JWS.sign(jwk, payload, header) end)
        |> JOSE.JWS.compact()
        |> then(fn {_jws, jwt} -> {:ok, jwt} end)
      end
    else
      {:ok, nil}
    end
  end

  defp maybe_append_key_binding(parts, nil), do: parts
  defp maybe_append_key_binding(parts, jwt), do: parts ++ [jwt]

  defp verify_issuer_jwt(jwt, opts) do
    with {:ok, header, claims} <- inspect_jwt(jwt),
         {:ok, jwks} <-
           VerificationKeys.issuer_jwks(
             opts,
             Map.get(claims, "vc", %{}),
             :missing_sd_jwt_vc_key,
             :invalid_sd_jwt_vc_key
           ),
         {:ok, verified_payload, _verified_jws, _verified_jwk} <-
           VerificationKeys.verify_compact(
             jwks,
             Keyword.get(opts, :allowed_algs, ["ES256", "EdDSA"]),
             jwt
           ),
         {:ok, verified_claims} <- decode_json_map(verified_payload, :invalid_sd_jwt_vc_payload),
         true <- verified_claims == claims do
      {:ok, claims, header}
    else
      {:error, :invalid_signature} -> {:error, :invalid_sd_jwt_vc_signature}
      {:error, _reason} = error -> error
      false -> {:error, :invalid_sd_jwt_vc_payload}
    end
  end

  defp validate_sd_alg(%{"_sd_alg" => @default_hash}), do: :ok
  defp validate_sd_alg(%{"_sd_alg" => _alg}), do: {:error, :unsupported_sd_jwt_hash}
  defp validate_sd_alg(_claims), do: :ok

  defp apply_disclosures(%{"vc" => %{} = credential} = claims, disclosures, verify_disclosures) do
    with {:ok, applied} <-
           Enum.reduce_while(
             disclosures,
             {:ok, credential},
             &apply_disclosure(&1, &2, claims, verify_disclosures)
           ) do
      {:ok, applied}
    end
  end

  defp apply_disclosures(_claims, _disclosures, _verify_disclosures),
    do: {:error, :invalid_sd_jwt_vc_payload}

  defp apply_disclosure(disclosure, {:ok, credential}, claims, verify_disclosures) do
    with {:ok, [_salt, path, value]} <- decode_disclosure(disclosure),
         :ok <- verify_disclosure_digest(disclosure, claims, verify_disclosures),
         {:ok, updated} <- put_path(credential, String.split(path, "."), value) do
      {:cont, {:ok, updated}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp verify_disclosure_digest(_disclosure, _claims, false), do: :ok

  defp verify_disclosure_digest(disclosure, %{"_sd" => digests}, true) when is_list(digests) do
    if digest(disclosure) in digests do
      :ok
    else
      {:error, :invalid_sd_jwt_disclosure}
    end
  end

  defp verify_disclosure_digest(_disclosure, _claims, true),
    do: {:error, :invalid_sd_jwt_disclosure}

  defp maybe_verify_key_binding(%{key_binding_jwt: nil}, _credential, _opts), do: :ok

  defp maybe_verify_key_binding(%{key_binding_jwt: jwt} = parsed, _credential, opts) do
    with {:ok, jwks} <-
           VerificationKeys.holder_jwks(
             opts,
             :missing_sd_jwt_holder_key,
             :invalid_sd_jwt_vc_key
           ),
         {:ok, payload, _verified_jws, _verified_jwk} <-
           VerificationKeys.verify_compact(
             jwks,
             Keyword.get(opts, :allowed_algs, ["ES256", "EdDSA"]),
             jwt
           ),
         {:ok, claims} <- decode_json_map(payload, :invalid_sd_jwt_kb_payload),
         :ok <- verify_key_binding_claims(claims, parsed, opts) do
      :ok
    else
      {:error, :invalid_signature} -> {:error, :invalid_sd_jwt_kb_signature}
      {:error, _reason} = error -> error
    end
  end

  defp verify_key_binding_claims(claims, parsed, opts) do
    expected_sd_hash =
      parsed.issuer_jwt
      |> build_bound_representation(parsed.disclosures)
      |> digest()

    cond do
      Keyword.has_key?(opts, :audience) and claims["aud"] != Keyword.get(opts, :audience) ->
        {:error, :invalid_sd_jwt_kb_audience}

      Keyword.has_key?(opts, :nonce) and claims["nonce"] != Keyword.get(opts, :nonce) ->
        {:error, :invalid_sd_jwt_kb_nonce}

      claims["sd_hash"] != expected_sd_hash ->
        {:error, :invalid_sd_jwt_kb_hash}

      true ->
        :ok
    end
  end

  defp build_bound_representation(issuer_jwt, disclosures) do
    [issuer_jwt | disclosures]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("~")
  end

  defp split_key_binding([]), do: {[], nil}

  defp split_key_binding(disclosures) do
    case List.last(disclosures) do
      candidate when is_binary(candidate) ->
        if length(String.split(candidate, ".", parts: 4)) == 3 do
          {Enum.drop(disclosures, -1), candidate}
        else
          {disclosures, nil}
        end

      _ ->
        {disclosures, nil}
    end
  end

  defp build_disclosure(path, value) do
    [random_salt(), path, value]
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp decode_disclosure(encoded) do
    with {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, [salt, path, value]} <- Jason.decode(json) do
      {:ok, [salt, path, value]}
    else
      _ -> {:error, :invalid_sd_jwt_disclosure}
    end
  end

  defp digest(disclosure) do
    :crypto.hash(:sha256, disclosure)
    |> Base.url_encode64(padding: false)
  end

  defp random_salt do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp maybe_put_sd(claims, []), do: claims
  defp maybe_put_sd(claims, digests), do: Map.put(claims, "_sd", digests)

  defp normalize_jwk(%JOSE.JWK{} = jwk), do: {:ok, jwk}

  defp normalize_jwk(jwk) when is_map(jwk) do
    try do
      {:ok, JOSE.JWK.from_map(jwk)}
    rescue
      _ -> {:error, :invalid_sd_jwt_vc_key}
    end
  end

  defp normalize_jwk(_jwk), do: {:error, :invalid_sd_jwt_vc_key}

  defp pop_path(container, [key]) when is_map(container) do
    if Map.has_key?(container, key) do
      {:ok, Map.fetch!(container, key), Map.delete(container, key)}
    else
      :error
    end
  end

  defp pop_path(container, [key | rest]) when is_map(container) do
    with %{} = nested <- Map.get(container, key),
         {:ok, value, updated_nested} <- pop_path(nested, rest) do
      {:ok, value, Map.put(container, key, updated_nested)}
    else
      _ -> :error
    end
  end

  defp put_path(container, [key], value) when is_map(container),
    do: {:ok, Map.put(container, key, value)}

  defp put_path(container, [key | rest], value) when is_map(container) do
    nested = Map.get(container, key, %{})

    if is_map(nested) do
      with {:ok, updated_nested} <- put_path(nested, rest, value) do
        {:ok, Map.put(container, key, updated_nested)}
      end
    else
      {:error, :invalid_sd_jwt_disclosure}
    end
  end

  defp inspect_jwt(jwt) when is_binary(jwt) do
    case String.split(jwt, ".", parts: 3) do
      [encoded_header, encoded_payload, encoded_signature]
      when encoded_header != "" and encoded_payload != "" and encoded_signature != "" ->
        with {:ok, header_json} <- Base.url_decode64(encoded_header, padding: false),
             {:ok, payload_json} <- Base.url_decode64(encoded_payload, padding: false),
             {:ok, header} <- decode_json_map(header_json, :invalid_sd_jwt_vc_header),
             {:ok, claims} <- decode_json_map(payload_json, :invalid_sd_jwt_vc_payload) do
          {:ok, header, claims}
        end

      _ ->
        {:error, :invalid_sd_jwt_vc}
    end
  end

  defp decode_json_map(json, error) do
    case Jason.decode(json) do
      {:ok, %{} = map} -> {:ok, map}
      _ -> {:error, error}
    end
  end
end
