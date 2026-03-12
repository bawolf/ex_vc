defmodule ExVc.VerificationKeys do
  @moduledoc false

  @spec issuer_jwks(keyword(), map(), atom(), atom()) ::
          {:ok, [JOSE.JWK.t()]} | {:error, atom()}
  def issuer_jwks(opts, credential, missing_error, invalid_error) when is_map(credential) do
    case Keyword.fetch(opts, :jwk) do
      {:ok, jwk} ->
        normalize_single_jwk(jwk, invalid_error)

      :error ->
        credential
        |> issuer_did(opts)
        |> resolve_did_jwks(opts, missing_error, invalid_error)
    end
  end

  @spec holder_jwks(keyword(), atom(), atom()) :: {:ok, [JOSE.JWK.t()]} | {:error, atom()}
  def holder_jwks(opts, missing_error, invalid_error) do
    cond do
      Keyword.has_key?(opts, :holder_jwk) ->
        opts
        |> Keyword.fetch!(:holder_jwk)
        |> normalize_single_jwk(invalid_error)

      Keyword.has_key?(opts, :holder_did) ->
        opts
        |> Keyword.fetch!(:holder_did)
        |> resolve_did_jwks(opts, missing_error, invalid_error)

      true ->
        {:error, missing_error}
    end
  end

  @spec proof_jwks(keyword(), map(), map(), atom(), atom()) ::
          {:ok, [JOSE.JWK.t()]} | {:error, atom()}
  def proof_jwks(opts, credential, proof, missing_error, invalid_error)
      when is_map(credential) and is_map(proof) do
    case Keyword.fetch(opts, :jwk) do
      {:ok, jwk} ->
        normalize_single_jwk(jwk, invalid_error)

      :error ->
        proof
        |> verification_method_did()
        |> case do
          nil -> issuer_did(credential, opts)
          did -> did
        end
        |> resolve_did_jwks(opts, missing_error, invalid_error)
    end
  end

  @spec verify_compact([JOSE.JWK.t()], [String.t()], String.t()) ::
          {:ok, binary(), term(), JOSE.JWK.t()} | {:error, :invalid_signature}
  def verify_compact(jwks, allowed_algs, compact) when is_list(jwks) and is_binary(compact) do
    Enum.reduce_while(jwks, {:error, :invalid_signature}, fn jwk, _acc ->
      case JOSE.JWS.verify_strict(jwk, allowed_algs, compact) do
        {true, payload, jws} -> {:halt, {:ok, payload, jws, jwk}}
        _ -> {:cont, {:error, :invalid_signature}}
      end
    end)
  end

  @spec normalize_single_jwk(term(), atom()) :: {:ok, [JOSE.JWK.t()]} | {:error, atom()}
  def normalize_single_jwk(%JOSE.JWK{} = jwk, _invalid_error), do: {:ok, [jwk]}

  def normalize_single_jwk(jwk, invalid_error) when is_map(jwk) do
    try do
      {:ok, [JOSE.JWK.from_map(jwk)]}
    rescue
      _ -> {:error, invalid_error}
    end
  end

  def normalize_single_jwk(_jwk, invalid_error), do: {:error, invalid_error}

  defp issuer_did(credential, opts) do
    Keyword.get_lazy(opts, :issuer_did, fn -> issuer_id(credential["issuer"]) end)
  end

  defp issuer_id(issuer) when is_binary(issuer), do: bare_did(issuer)
  defp issuer_id(%{"id" => issuer}) when is_binary(issuer), do: bare_did(issuer)
  defp issuer_id(_issuer), do: nil

  defp verification_method_did(%{"verificationMethod" => verification_method})
       when is_binary(verification_method),
       do: bare_did(verification_method)

  defp verification_method_did(_proof), do: nil

  defp bare_did("did:" <> _ = value) do
    value
    |> String.split(["#", "?"], parts: 2)
    |> hd()
  end

  defp bare_did(_value), do: nil

  defp resolve_did_jwks(nil, _opts, missing_error, _invalid_error), do: {:error, missing_error}

  defp resolve_did_jwks(did, opts, _missing_error, invalid_error) when is_binary(did) do
    case ExDid.resolve(did, did_resolver_opts(opts)) do
      %{did_document: %{} = document} ->
        document
        |> ExDid.verification_method_jwks()
        |> Enum.reduce_while({:ok, []}, fn jwk, {:ok, acc} ->
          case normalize_single_jwk(jwk, invalid_error) do
            {:ok, [normalized]} -> {:cont, {:ok, [normalized | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, []} -> {:error, invalid_error}
          {:ok, jwks} -> {:ok, Enum.reverse(jwks)}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, invalid_error}
    end
  end

  defp did_resolver_opts(opts) do
    []
    |> maybe_put_opt(:fetch_json, Keyword.get(opts, :fetch_json))
    |> maybe_put_opt(:method_registry, Keyword.get(opts, :method_registry))
    |> maybe_put_opt(:validation, Keyword.get(opts, :did_validation))
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
