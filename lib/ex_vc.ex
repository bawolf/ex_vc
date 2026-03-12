defmodule ExVc do
  @moduledoc """
  Verifiable Credentials facade.

  `ex_vc` owns generic VC 2.0 envelope loading, validation, presentation
  handling, and proof-format boundaries. Product-specific credential semantics
  should remain in the caller and plug into `validate/2` through custom
  validators.
  """

  alias ExVc.Credential
  alias ExVc.FormatRegistry
  alias ExVc.IssueOptions
  alias ExVc.Presentation
  alias ExVc.PresentationValidation
  alias ExVc.PresentationVerification
  alias ExVc.Validation
  alias ExVc.ValidationError
  alias ExVc.ValidationReport
  alias ExVc.VerificationResult
  alias ExVc.VerifyOptions

  @type validation_error :: ValidationError.t()
  @type validation_report :: ValidationReport.t()
  @type credential :: Credential.t()
  @type verification_result :: VerificationResult.t()
  @type presentation :: Presentation.t()
  @type presentation_verification :: PresentationVerification.t()
  @type custom_validator ::
          (map(), validation_report() -> [validation_error()] | validation_error() | nil)

  @spec load(map()) :: {:ok, credential()} | {:error, :invalid_credential}
  def load(credential), do: Credential.new(credential)

  @spec to_map(credential()) :: map()
  def to_map(%Credential{} = credential), do: Credential.to_map(credential)

  @doc false
  @spec load_presentation(map()) :: {:ok, presentation()} | {:error, :invalid_presentation}
  def load_presentation(presentation), do: Presentation.new(presentation)

  @doc false
  @spec presentation_to_map(presentation()) :: map()
  def presentation_to_map(%Presentation{} = presentation), do: Presentation.to_map(presentation)

  @spec validate(map(), keyword()) :: {:ok, validation_report()} | {:error, validation_report()}
  def validate(credential, opts \\ []), do: Validation.validate(credential, opts)

  @spec valid?(map(), keyword()) :: boolean()
  def valid?(credential, opts \\ []) do
    match?({:ok, _report}, validate(credential, opts))
  end

  @doc """
  Issues a normalized credential and optionally signs it as `vc+jwt`.

  Release 1 treats `vc+jwt` as the supported signing contract. Other proof
  adapters may exist in-tree for future work but are not part of the release
  support posture.
  """
  @spec issue(map(), keyword()) ::
          {:ok, map() | String.t()} | {:error, validation_report() | atom()}
  def issue(claims, opts \\ [])

  def issue(claims, opts) when is_map(claims) do
    with {:ok, options} <- IssueOptions.new(opts),
         {:ok, credential} <- build_issued_credential(claims, options),
         {:ok, _report} <- validate(credential) do
      issue_format(credential, options)
    else
      {:error, %NimbleOptions.ValidationError{}} ->
        {:error, :invalid_issue_options}

      {:error, %ValidationReport{} = report} ->
        {:error, report}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def issue(_claims, _opts), do: {:error, :invalid_vc}

  @doc false
  @spec sign(map(), JOSE.JWK.t() | map(), keyword()) ::
          {:ok, map() | String.t()} | {:error, atom()}
  def sign(credential, jwk, opts \\ []) when is_map(credential) do
    format = Keyword.get(opts, :format, :jwt_vc)
    proof_module = FormatRegistry.proof_module(format)
    proof_module.sign(credential, jwk, opts)
  end

  @doc """
  Verifies a VC representation with automatic format detection.

  Release 1 support is centered on `vc+jwt`, with DID-based verification key
  resolution delegated to `ex_did`.
  """
  @spec verify(String.t() | map(), keyword()) ::
          {:ok, verification_result()} | {:error, atom()}
  def verify(representation, opts \\ []) do
    with {:ok, options} <- VerifyOptions.new(opts),
         format <- verify_format(representation, options),
         :ok <- ensure_known_format(format) do
      FormatRegistry.proof_module(format).verify(representation, opts)
    else
      {:error, %NimbleOptions.ValidationError{}} -> {:error, :invalid_verify_options}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec verify_presentation(map(), keyword()) ::
          {:ok, presentation_verification()} | {:error, [validation_error()] | atom()}
  def verify_presentation(presentation, opts \\ [])

  def verify_presentation(presentation, opts) when is_map(presentation) do
    verify_credentials = Keyword.get(opts, :verify_credentials, false)

    with {:ok, normalized} <- PresentationValidation.validate(presentation, opts) do
      with {:ok, credentials} <-
             verify_presentation_credentials(
               normalized.verifiable_credentials,
               verify_credentials,
               opts
             ) do
        {:ok,
         %PresentationVerification{
           presentation: Presentation.to_map(normalized),
           credentials: credentials,
           metadata: %{"verifiedCredentials" => count_verified(credentials)},
           verified: true
         }}
      end
    end
  end

  def verify_presentation(_presentation, _opts), do: {:error, :invalid_presentation}

  @doc """
  Signs a VC payload as a `vc+jwt` representation.
  """
  @spec sign_jwt_vc(map(), JOSE.JWK.t() | map(), keyword()) ::
          {:ok, String.t()} | {:error, atom()}
  def sign_jwt_vc(credential, jwk, opts \\ []), do: ExVc.JwtVc.sign(credential, jwk, opts)

  @doc """
  Verifies and decodes a `vc+jwt` representation.
  """
  @spec verify_jwt_vc(String.t(), keyword()) ::
          {:ok, verification_result()} | {:error, atom()}
  def verify_jwt_vc(jwt, opts \\ []), do: ExVc.JwtVc.verify(jwt, opts)

  defp build_issued_credential(claims, options) do
    credential =
      claims
      |> maybe_put("@context", options.contexts)
      |> maybe_put("id", options.id)
      |> maybe_put("type", options.types)
      |> maybe_put("issuer", options.issuer || claims["issuer"])
      |> maybe_put("validFrom", datetime_to_iso8601(options.valid_from))
      |> maybe_put("validUntil", datetime_to_iso8601(options.valid_until))
      |> maybe_put("credentialStatus", options.credential_status)
      |> maybe_put("proof", options.proof)

    {:ok, credential}
  end

  defp issue_format(credential, %IssueOptions{format: :map}), do: {:ok, credential}

  defp issue_format(credential, %IssueOptions{format: format, jwk: jwk} = options)
       when format in [:jwt_vc, :data_integrity] do
    opts =
      [
        format: format,
        alg: options.alg,
        suite: options.suite,
        verification_method: options.verification_method
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    sign(credential, jwk, opts)
  end

  defp issue_format(credential, %IssueOptions{format: :sd_jwt_vc, jwk: jwk} = options) do
    opts =
      [format: :sd_jwt_vc, alg: options.alg, disclose_paths: options.disclose_paths]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    sign(credential, jwk, opts)
  end

  defp issue_format(_credential, %IssueOptions{}), do: {:error, :missing_issuing_key}

  defp verify_format(_representation, %VerifyOptions{format: format}) when format != :auto,
    do: format

  defp verify_format(representation, %VerifyOptions{}), do: FormatRegistry.detect(representation)

  defp ensure_known_format(:unknown), do: {:error, :unknown_vc_format}
  defp ensure_known_format(_format), do: :ok

  defp count_verified(credentials) do
    Enum.count(credentials, &match?(%VerificationResult{verified: true}, &1))
  end

  defp verify_presentation_credentials(credentials, false, _opts), do: {:ok, credentials}

  defp verify_presentation_credentials(credentials, true, opts) do
    credentials
    |> Enum.reduce_while({:ok, []}, fn
      %{} = credential, {:ok, acc} ->
        {:cont, {:ok, [credential | acc]}}

      representation, {:ok, acc} when is_binary(representation) ->
        case verify(representation, Keyword.drop(opts, [:verify_credentials])) do
          {:ok, result} -> {:cont, {:ok, [result | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      representation, {:ok, acc} ->
        {:cont, {:ok, [representation | acc]}}
    end)
    |> case do
      {:ok, verified} -> {:ok, Enum.reverse(verified)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp datetime_to_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp datetime_to_iso8601(value), do: value
end
