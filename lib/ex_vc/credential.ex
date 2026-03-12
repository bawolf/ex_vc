defmodule ExVc.Credential do
  @moduledoc """
  Normalized VC 2.0 credential shape.

  This struct normalizes the common VC envelope while preserving unknown claims
  in `extra_fields` so applications can layer profile semantics on top.
  """

  @known_fields ~w(@context id type issuer validFrom validUntil credentialSubject credentialStatus proof)a

  @enforce_keys [:raw, :context, :types, :extra_fields]
  defstruct [
    :id,
    :issuer,
    :valid_from,
    :valid_until,
    :credential_subject,
    :credential_status,
    :proof,
    :raw,
    context: [],
    types: [],
    extra_fields: %{}
  ]

  @typedoc "Issuer reference as a URI string or issuer object."
  @type issuer :: String.t() | map() | nil

  @typedoc "Credential subject as one or more subject objects."
  @type subject :: map() | [map()] | nil

  @typedoc "Credential status object(s)."
  @type credential_status :: map() | [map()] | nil

  @typedoc "Proof object(s)."
  @type proof :: map() | [map()] | nil

  @typedoc "Normalized VC 2.0 credential."
  @type t :: %__MODULE__{
          id: String.t() | nil,
          context: [term()],
          types: [String.t()],
          issuer: issuer(),
          valid_from: DateTime.t() | nil,
          valid_until: DateTime.t() | nil,
          credential_subject: subject(),
          credential_status: credential_status(),
          proof: proof(),
          raw: map(),
          extra_fields: map()
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_credential}
  def new(%{} = credential) do
    {:ok,
     %__MODULE__{
       raw: credential,
       id: string_or_nil(credential["id"]),
       context: normalize_context(credential["@context"]),
       types: normalize_string_list(credential["type"]),
       issuer: normalize_issuer(credential["issuer"]),
       valid_from: parse_datetime(credential["validFrom"]),
       valid_until: parse_datetime(credential["validUntil"]),
       credential_subject: credential["credentialSubject"],
       credential_status: credential["credentialStatus"],
       proof: credential["proof"],
       extra_fields: Map.drop(credential, @known_fields)
     }}
  end

  def new(_credential), do: {:error, :invalid_credential}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = credential) do
    credential.extra_fields
    |> maybe_put("@context", denormalize_context(credential.context))
    |> maybe_put("id", credential.id)
    |> maybe_put("type", denormalize_string_list(credential.types))
    |> maybe_put("issuer", credential.issuer)
    |> maybe_put("validFrom", credential.valid_from && DateTime.to_iso8601(credential.valid_from))
    |> maybe_put(
      "validUntil",
      credential.valid_until && DateTime.to_iso8601(credential.valid_until)
    )
    |> maybe_put("credentialSubject", credential.credential_subject)
    |> maybe_put("credentialStatus", credential.credential_status)
    |> maybe_put("proof", credential.proof)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_context(nil), do: []
  defp normalize_context(context) when is_list(context), do: context
  defp normalize_context(context), do: [context]

  defp denormalize_context([single]), do: single
  defp denormalize_context(context), do: context

  defp normalize_string_list(nil), do: []
  defp normalize_string_list(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp normalize_string_list(value) when is_binary(value), do: [value]
  defp normalize_string_list(_value), do: []

  defp denormalize_string_list([single]), do: single
  defp denormalize_string_list(values), do: values

  defp normalize_issuer(%{"id" => id} = issuer) when is_binary(id) and id != "", do: issuer
  defp normalize_issuer(issuer) when is_binary(issuer) and issuer != "", do: issuer
  defp normalize_issuer(_issuer), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp string_or_nil(value) when is_binary(value) and value != "", do: value
  defp string_or_nil(_value), do: nil
end
