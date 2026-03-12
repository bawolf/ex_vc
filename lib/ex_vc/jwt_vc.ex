defmodule ExVc.JwtVc do
  @moduledoc """
  `vc+jwt` proof implementation for `ExVc`.
  """

  @behaviour ExVc.Proof

  alias ExVc.VerificationKeys
  alias ExVc.VerificationResult

  @jwt_vc_typ "vc+jwt"

  @type verified_result :: VerificationResult.t()

  @impl true
  @spec sign(map(), JOSE.JWK.t() | map(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def sign(credential, jwk, opts \\ [])

  def sign(credential, jwk, opts) when is_map(credential) do
    with :ok <- validate(credential),
         {:ok, signing_jwk} <- normalize_jwk(jwk) do
      header = %{
        "alg" => Keyword.get(opts, :alg, "ES256"),
        "typ" => Keyword.get(opts, :typ, @jwt_vc_typ)
      }

      credential
      |> Jason.encode!()
      |> then(&JOSE.JWS.sign(signing_jwk, &1, header))
      |> JOSE.JWS.compact()
      |> then(fn {_jws, jwt} -> {:ok, jwt} end)
    else
      {:error, _report} -> {:error, :invalid_vc}
    end
  end

  def sign(_credential, _jwk, _opts), do: {:error, :invalid_vc}

  @impl true
  @spec verify(String.t(), keyword()) :: {:ok, verified_result()} | {:error, atom()}
  def verify(jwt, opts \\ [])

  def verify(jwt, opts) when is_binary(jwt) and is_list(opts) do
    with {:ok, header, credential} <- inspect_jwt(jwt),
         :ok <- validate_header(header, Keyword.get(opts, :allowed_algs, ["ES256", "EdDSA"])),
         {:ok, jwks} <-
           VerificationKeys.issuer_jwks(
             opts,
             credential,
             :missing_jwt_vc_key,
             :invalid_jwt_vc_key
           ),
         {:ok, verified_payload, _verified_jws, _verified_jwk} <-
           VerificationKeys.verify_compact(jwks, [header["alg"]], jwt),
         {:ok, credential_json} <- decode_verified_payload(verified_payload),
         true <- credential_json == credential,
         :ok <- validate(credential_json) do
      {:ok,
       %VerificationResult{
         credential: credential_json,
         proof: header,
         representation: jwt,
         format: :jwt_vc,
         verified: true
       }}
    else
      {:error, :invalid_signature} ->
        {:error, :invalid_jwt_vc_signature}

      {:error, _reason} = error ->
        error

      false ->
        {:error, :invalid_jwt_vc_payload}

      _ ->
        {:error, :invalid_jwt_vc_signature}
    end
  end

  def verify(_jwt, _opts), do: {:error, :invalid_jwt_vc}

  @spec inspect_jwt(String.t()) :: {:ok, map(), map()} | {:error, atom()}
  def inspect_jwt(jwt) when is_binary(jwt) do
    case String.split(jwt, ".", parts: 3) do
      [encoded_header, encoded_payload, encoded_signature]
      when encoded_header != "" and encoded_payload != "" and encoded_signature != "" ->
        with {:ok, header_json} <- url_decode(encoded_header),
             {:ok, payload_json} <- url_decode(encoded_payload),
             {:ok, header} <- decode_json_map(header_json, :invalid_jwt_vc_header),
             {:ok, credential} <- decode_json_map(payload_json, :invalid_jwt_vc_payload) do
          {:ok, header, credential}
        end

      _ ->
        {:error, :invalid_jwt_vc}
    end
  end

  def inspect_jwt(_jwt), do: {:error, :invalid_jwt_vc}

  @impl true
  @spec validate(map()) :: :ok | {:error, ExVc.ValidationReport.t()}
  def validate(credential) do
    case ExVc.validate(credential) do
      {:ok, _report} -> :ok
      {:error, report} -> {:error, report}
    end
  end

  defp validate_header(%{"typ" => @jwt_vc_typ, "alg" => alg}, allowed_algs)
       when is_binary(alg) do
    if alg in allowed_algs, do: :ok, else: {:error, :unsupported_jwt_vc_alg}
  end

  defp validate_header(%{"typ" => typ}, _allowed_algs) when typ != @jwt_vc_typ,
    do: {:error, :invalid_jwt_vc_typ}

  defp validate_header(%{"alg" => alg}, _allowed_algs) when not is_binary(alg) or alg == "",
    do: {:error, :invalid_jwt_vc_alg}

  defp validate_header(%{"alg" => "none"}, _allowed_algs), do: {:error, :invalid_jwt_vc_alg}
  defp validate_header(%{"alg" => _alg}, _allowed_algs), do: {:error, :unsupported_jwt_vc_alg}
  defp validate_header(_header, _allowed_algs), do: {:error, :invalid_jwt_vc_header}

  defp normalize_jwk(%JOSE.JWK{} = jwk), do: {:ok, jwk}

  defp normalize_jwk(jwk) when is_map(jwk) do
    try do
      {:ok, JOSE.JWK.from_map(jwk)}
    rescue
      _ -> {:error, :invalid_jwt_vc_key}
    end
  end

  defp normalize_jwk(_jwk), do: {:error, :invalid_jwt_vc_key}

  defp decode_verified_payload(payload) when is_binary(payload) do
    decode_json_map(payload, :invalid_jwt_vc_payload)
  end

  defp decode_verified_payload(_payload), do: {:error, :invalid_jwt_vc_payload}

  defp url_decode(segment) do
    Base.url_decode64(segment, padding: false)
    |> case do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_jwt_vc}
    end
  end

  defp decode_json_map(json, error) do
    case Jason.decode(json) do
      {:ok, %{} = map} -> {:ok, map}
      _ -> {:error, error}
    end
  end
end
