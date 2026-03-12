defmodule ExVc.Validation do
  @moduledoc false

  alias ExVc.Credential
  alias ExVc.ValidateOptions
  alias ExVc.ValidationError
  alias ExVc.ValidationReport

  @vc_context "https://www.w3.org/ns/credentials/v2"
  @vc_type "VerifiableCredential"

  @spec validate(map(), keyword()) :: {:ok, ValidationReport.t()} | {:error, ValidationReport.t()}
  def validate(credential, opts \\ [])

  def validate(credential, opts) when is_map(credential) do
    with {:ok, options} <- ValidateOptions.new(opts),
         {:ok, normalized} <- Credential.new(credential) do
      errors =
        []
        |> validate_context(normalized)
        |> validate_type(normalized)
        |> validate_required_types(normalized, options.required_types)
        |> validate_issuer(normalized)
        |> validate_temporal_fields(credential, normalized)
        |> validate_subject(normalized)
        |> validate_credential_status(normalized)
        |> validate_proof(normalized)
        |> run_custom_validators(credential, normalized, options.validators)
        |> Enum.reverse()

      report = ValidationReport.new(credential, normalized, errors)

      if report.errors == [], do: {:ok, report}, else: {:error, report}
    else
      {:error, %NimbleOptions.ValidationError{}} ->
        report =
          ValidationReport.new(
            credential,
            nil,
            [ValidationError.new("options", "invalid_options", "Validation options are invalid")]
          )

        {:error, report}

      {:error, :invalid_credential} ->
        invalid_type_report()
    end
  end

  def validate(_credential, _opts), do: invalid_type_report()

  defp invalid_type_report do
    report =
      ValidationReport.new(
        %{},
        nil,
        [ValidationError.new("credential", "invalid_type", "Credential must be a JSON object")]
      )

    {:error, report}
  end

  defp validate_context(errors, %Credential{context: []}) do
    [ValidationError.new("@context", "required", "Credential context is required") | errors]
  end

  defp validate_context(errors, %Credential{context: context}) do
    if Enum.any?(context, &(&1 == @vc_context)) do
      errors
    else
      [
        ValidationError.new(
          "@context",
          "missing_vc_context",
          "Credential context must include VC 2.0"
        )
        | errors
      ]
    end
  end

  defp validate_type(errors, %Credential{types: []}) do
    [ValidationError.new("type", "required", "Credential type is required") | errors]
  end

  defp validate_type(errors, %Credential{types: types}) do
    if @vc_type in types do
      errors
    else
      [
        ValidationError.new(
          "type",
          "missing_vc_type",
          "Credential type must include VerifiableCredential"
        )
        | errors
      ]
    end
  end

  defp validate_required_types(errors, _credential, []), do: errors

  defp validate_required_types(errors, %Credential{types: types}, required_types) do
    Enum.reduce(required_types, errors, fn required_type, acc ->
      if required_type in types do
        acc
      else
        [
          ValidationError.new(
            "type",
            "missing_required_type",
            "Credential type must include #{required_type}"
          )
          | acc
        ]
      end
    end)
  end

  defp validate_issuer(errors, %Credential{issuer: nil}) do
    [ValidationError.new("issuer", "required", "issuer is required") | errors]
  end

  defp validate_issuer(errors, _credential), do: errors

  defp validate_temporal_fields(errors, raw_credential, normalized) do
    errors
    |> maybe_add_datetime_error("validFrom", raw_credential["validFrom"], normalized.valid_from)
    |> maybe_add_datetime_error(
      "validUntil",
      raw_credential["validUntil"],
      normalized.valid_until
    )
    |> maybe_add_temporal_order_error(normalized)
  end

  defp maybe_add_datetime_error(errors, _field, nil, _normalized), do: errors

  defp maybe_add_datetime_error(errors, _field, value, %DateTime{}) when is_binary(value),
    do: errors

  defp maybe_add_datetime_error(errors, field, _value, _normalized) do
    [
      ValidationError.new(field, "invalid_datetime", "#{field} must be an ISO8601 datetime")
      | errors
    ]
  end

  defp maybe_add_temporal_order_error(
         errors,
         %Credential{valid_from: %DateTime{} = valid_from, valid_until: %DateTime{} = valid_until}
       ) do
    if DateTime.compare(valid_until, valid_from) == :lt do
      [
        ValidationError.new(
          "validUntil",
          "invalid_temporal_order",
          "validUntil must be on or after validFrom"
        )
        | errors
      ]
    else
      errors
    end
  end

  defp maybe_add_temporal_order_error(errors, _credential), do: errors

  defp validate_subject(errors, %Credential{credential_subject: nil}) do
    [
      ValidationError.new("credentialSubject", "required", "credentialSubject is required")
      | errors
    ]
  end

  defp validate_subject(errors, %Credential{credential_subject: %{} = subject}) do
    maybe_validate_subject_id(errors, "credentialSubject", subject)
  end

  defp validate_subject(errors, %Credential{credential_subject: subjects})
       when is_list(subjects) do
    if subjects == [] do
      [
        ValidationError.new(
          "credentialSubject",
          "invalid_subject",
          "credentialSubject must contain at least one subject"
        )
        | errors
      ]
    else
      Enum.with_index(subjects)
      |> Enum.reduce(errors, fn
        {%{} = subject, index}, acc ->
          maybe_validate_subject_id(acc, "credentialSubject[#{index}]", subject)

        {_subject, index}, acc ->
          [
            ValidationError.new(
              "credentialSubject[#{index}]",
              "invalid_subject",
              "credentialSubject entries must be JSON objects"
            )
            | acc
          ]
      end)
    end
  end

  defp validate_subject(errors, _credential) do
    [
      ValidationError.new(
        "credentialSubject",
        "invalid_subject",
        "credentialSubject must be a JSON object or a list of JSON objects"
      )
      | errors
    ]
  end

  defp maybe_validate_subject_id(errors, _field, %{} = subject) do
    case Map.get(subject, "id") do
      nil ->
        errors

      id when is_binary(id) and id != "" ->
        errors

      _id ->
        [
          ValidationError.new(
            "credentialSubject.id",
            "invalid_subject_id",
            "credentialSubject.id must be a non-empty string"
          )
          | errors
        ]
    end
  end

  defp validate_credential_status(errors, %Credential{credential_status: nil}), do: errors

  defp validate_credential_status(errors, %Credential{credential_status: %{} = status}) do
    validate_status_entry(errors, "credentialStatus", status)
  end

  defp validate_credential_status(errors, %Credential{credential_status: statuses})
       when is_list(statuses) do
    if statuses == [] do
      [
        ValidationError.new(
          "credentialStatus",
          "invalid_status",
          "credentialStatus must contain at least one status object"
        )
        | errors
      ]
    else
      Enum.with_index(statuses)
      |> Enum.reduce(errors, fn
        {%{} = status, index}, acc ->
          validate_status_entry(acc, "credentialStatus[#{index}]", status)

        {_status, index}, acc ->
          [
            ValidationError.new(
              "credentialStatus[#{index}]",
              "invalid_status",
              "credentialStatus entries must be JSON objects"
            )
            | acc
          ]
      end)
    end
  end

  defp validate_credential_status(errors, _credential) do
    [
      ValidationError.new(
        "credentialStatus",
        "invalid_status",
        "credentialStatus must be a JSON object or a list of JSON objects"
      )
      | errors
    ]
  end

  defp validate_status_entry(errors, field_prefix, status) do
    errors
    |> maybe_add_required_string(status, "#{field_prefix}.id", "id")
    |> maybe_add_required_string(status, "#{field_prefix}.type", "type")
    |> maybe_add_bitstring_requirements(field_prefix, status)
  end

  defp maybe_add_bitstring_requirements(
         errors,
         field_prefix,
         %{"type" => "BitstringStatusListEntry"} = status
       ) do
    errors
    |> maybe_add_required_string(status, "#{field_prefix}.statusPurpose", "statusPurpose")
    |> maybe_add_required_string(
      status,
      "#{field_prefix}.statusListCredential",
      "statusListCredential"
    )
    |> maybe_add_required_string(status, "#{field_prefix}.statusListIndex", "statusListIndex")
  end

  defp maybe_add_bitstring_requirements(errors, _field_prefix, _status), do: errors

  defp maybe_add_required_string(errors, container, field_path, field) do
    case Map.get(container, field) do
      value when is_binary(value) and value != "" -> errors
      _ -> [ValidationError.new(field_path, "required", "#{field} is required") | errors]
    end
  end

  defp validate_proof(errors, %Credential{proof: nil}), do: errors

  defp validate_proof(errors, %Credential{proof: %{} = proof}) do
    validate_proof_entry(errors, "proof", proof)
  end

  defp validate_proof(errors, %Credential{proof: proofs}) when is_list(proofs) do
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

  defp validate_proof(errors, _credential) do
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
    |> maybe_add_datetime_error("#{field_prefix}.created", proof["created"])
  end

  defp maybe_add_datetime_error(errors, _field, nil), do: errors

  defp maybe_add_datetime_error(errors, field, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} ->
        errors

      _ ->
        [
          ValidationError.new(field, "invalid_datetime", "#{field} must be an ISO8601 datetime")
          | errors
        ]
    end
  end

  defp maybe_add_datetime_error(errors, field, _value) do
    [
      ValidationError.new(field, "invalid_datetime", "#{field} must be an ISO8601 datetime")
      | errors
    ]
  end

  defp run_custom_validators(errors, credential, normalized, validators) do
    report = ValidationReport.new(credential, normalized, [])

    Enum.reduce(validators, errors, fn validator, acc ->
      validator_errors =
        case validator.(credential, report) do
          [] ->
            []

          nil ->
            []

          list when is_list(list) ->
            Enum.map(list, &normalize_error/1)

          %ValidationError{} = error ->
            [error]

          {:error, list} when is_list(list) ->
            Enum.map(list, &normalize_error/1)

          _other ->
            [
              ValidationError.new(
                "credential",
                "invalid_validator_result",
                "Custom validator returned an invalid result"
              )
            ]
        end

      Enum.reverse(validator_errors, acc)
    end)
  end

  defp normalize_error(%ValidationError{} = error), do: error

  defp normalize_error(%{field: field, code: code, message: message}) do
    ValidationError.new(to_string(field), to_string(code), to_string(message))
  end
end
