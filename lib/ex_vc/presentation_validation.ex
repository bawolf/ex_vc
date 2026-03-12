defmodule ExVc.PresentationValidation do
  @moduledoc false

  alias ExVc.Presentation
  alias ExVc.ValidationError

  @spec validate(map(), keyword()) :: {:ok, Presentation.t()} | {:error, [ValidationError.t()]}
  def validate(presentation, opts \\ [])

  def validate(presentation, opts) when is_map(presentation) do
    with {:ok, normalized} <- Presentation.new(presentation) do
      errors =
        []
        |> validate_context(normalized)
        |> validate_type(normalized)
        |> validate_holder(normalized)
        |> validate_embedded_credentials(normalized, opts)
        |> validate_proof(normalized)
        |> Enum.reverse()

      if errors == [], do: {:ok, normalized}, else: {:error, errors}
    else
      {:error, :invalid_presentation} ->
        {:error,
         [
           ValidationError.new(
             "presentation",
             "invalid_type",
             "Presentation must be a JSON object"
           )
         ]}
    end
  end

  def validate(_presentation, _opts) do
    {:error,
     [ValidationError.new("presentation", "invalid_type", "Presentation must be a JSON object")]}
  end

  defp validate_context(errors, %Presentation{context: []}) do
    [ValidationError.new("@context", "required", "Presentation context is required") | errors]
  end

  defp validate_context(errors, %Presentation{context: context}) do
    if Enum.any?(context, &(&1 == Presentation.vc_context())) do
      errors
    else
      [
        ValidationError.new(
          "@context",
          "missing_vc_context",
          "Presentation context must include VC 2.0"
        )
        | errors
      ]
    end
  end

  defp validate_type(errors, %Presentation{types: types}) do
    cond do
      types == [] ->
        [ValidationError.new("type", "required", "Presentation type is required") | errors]

      Presentation.vp_type() in types ->
        errors

      true ->
        [
          ValidationError.new(
            "type",
            "missing_vp_type",
            "Presentation type must include VerifiablePresentation"
          )
          | errors
        ]
    end
  end

  defp validate_holder(errors, %Presentation{holder: nil}), do: errors
  defp validate_holder(errors, %Presentation{}), do: errors

  defp validate_embedded_credentials(errors, %Presentation{verifiable_credentials: []}, _opts) do
    [
      ValidationError.new("verifiableCredential", "required", "verifiableCredential is required")
      | errors
    ]
  end

  defp validate_embedded_credentials(
         errors,
         %Presentation{verifiable_credentials: credentials},
         opts
       ) do
    verify_credentials = Keyword.get(opts, :verify_credentials, false)

    Enum.with_index(credentials)
    |> Enum.reduce(errors, fn
      {%{} = credential, index}, acc ->
        case ExVc.validate(credential) do
          {:ok, _report} ->
            acc

          {:error, _report} ->
            [
              ValidationError.new(
                "verifiableCredential[#{index}]",
                "invalid_credential",
                "Embedded credential is invalid"
              )
              | acc
            ]
        end

      {representation, index}, acc ->
        cond do
          is_binary(representation) and verify_credentials ->
            case ExVc.verify(representation, Keyword.drop(opts, [:verify_credentials])) do
              {:ok, _result} ->
                acc

              {:error, reason} ->
                [
                  ValidationError.new(
                    "verifiableCredential[#{index}]",
                    "invalid_credential",
                    "Embedded credential verification failed: #{reason}"
                  )
                  | acc
                ]
            end

          is_binary(representation) ->
            acc

          true ->
            [
              ValidationError.new(
                "verifiableCredential[#{index}]",
                "invalid_credential",
                "Embedded credential must be a JSON object or string representation"
              )
              | acc
            ]
        end
    end)
  end

  defp validate_proof(errors, %Presentation{proof: nil}), do: errors

  defp validate_proof(errors, %Presentation{proof: %{} = proof}) do
    validate_proof_entry(errors, "proof", proof)
  end

  defp validate_proof(errors, %Presentation{proof: proofs}) when is_list(proofs) do
    Enum.with_index(proofs)
    |> Enum.reduce(errors, fn
      {%{} = proof, index}, acc ->
        validate_proof_entry(acc, "proof[#{index}]", proof)

      {_proof, index}, acc ->
        [
          ValidationError.new(
            "proof[#{index}]",
            "invalid_proof",
            "proof entries must be JSON objects"
          )
          | acc
        ]
    end)
  end

  defp validate_proof(errors, _presentation) do
    [
      ValidationError.new(
        "proof",
        "invalid_proof",
        "proof must be a JSON object or a list of JSON objects"
      )
      | errors
    ]
  end

  defp validate_proof_entry(errors, field_prefix, proof) do
    errors
    |> maybe_add_required_string(proof, "#{field_prefix}.type", "type")
    |> maybe_add_datetime(proof, "#{field_prefix}.created", "created")
  end

  defp maybe_add_required_string(errors, container, field_path, field) do
    case Map.get(container, field) do
      value when is_binary(value) and value != "" -> errors
      _ -> [ValidationError.new(field_path, "required", "#{field} is required") | errors]
    end
  end

  defp maybe_add_datetime(errors, container, field_path, field) do
    case Map.get(container, field) do
      nil ->
        errors

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, _datetime, _offset} ->
            errors

          _ ->
            [
              ValidationError.new(
                field_path,
                "invalid_datetime",
                "#{field_path} must be an ISO8601 datetime"
              )
              | errors
            ]
        end

      _ ->
        [
          ValidationError.new(
            field_path,
            "invalid_datetime",
            "#{field_path} must be an ISO8601 datetime"
          )
          | errors
        ]
    end
  end
end
