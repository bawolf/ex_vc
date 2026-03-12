defmodule ExVc.Presentation do
  @moduledoc """
  Normalized Verifiable Presentation shape.
  """

  @vp_context "https://www.w3.org/ns/credentials/v2"
  @vp_type "VerifiablePresentation"
  @known_fields ~w(@context id type holder verifiableCredential proof)a

  @enforce_keys [:raw, :context, :types, :verifiable_credentials, :extra_fields]
  defstruct [
    :id,
    :holder,
    :proof,
    :raw,
    context: [],
    types: [],
    verifiable_credentials: [],
    extra_fields: %{}
  ]

  @typedoc "Presentation holder."
  @type holder :: String.t() | map() | nil

  @typedoc "Embedded verifiable credential representation."
  @type embedded_credential :: map() | String.t()

  @typedoc "Normalized VP."
  @type t :: %__MODULE__{
          id: String.t() | nil,
          holder: holder(),
          proof: map() | [map()] | nil,
          raw: map(),
          context: [term()],
          types: [String.t()],
          verifiable_credentials: [embedded_credential()],
          extra_fields: map()
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_presentation}
  def new(%{} = presentation) do
    {:ok,
     %__MODULE__{
       raw: presentation,
       id: string_or_nil(presentation["id"]),
       holder: normalize_holder(presentation["holder"]),
       proof: presentation["proof"],
       context: normalize_context(presentation["@context"]),
       types: normalize_types(presentation["type"]),
       verifiable_credentials:
         normalize_embedded_credentials(presentation["verifiableCredential"]),
       extra_fields: Map.drop(presentation, @known_fields)
     }}
  end

  def new(_presentation), do: {:error, :invalid_presentation}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = presentation) do
    presentation.extra_fields
    |> maybe_put("@context", denormalize_context(presentation.context))
    |> maybe_put("id", presentation.id)
    |> maybe_put("type", denormalize_types(presentation.types))
    |> maybe_put("holder", presentation.holder)
    |> maybe_put(
      "verifiableCredential",
      denormalize_embedded_credentials(presentation.verifiable_credentials)
    )
    |> maybe_put("proof", presentation.proof)
  end

  @spec vc_context() :: String.t()
  def vc_context, do: @vp_context

  @spec vp_type() :: String.t()
  def vp_type, do: @vp_type

  defp normalize_holder(holder) when is_binary(holder) and holder != "", do: holder
  defp normalize_holder(%{} = holder), do: holder
  defp normalize_holder(_holder), do: nil

  defp normalize_context(nil), do: []
  defp normalize_context(context) when is_list(context), do: context
  defp normalize_context(context), do: [context]

  defp denormalize_context([single]), do: single
  defp denormalize_context(context), do: context

  defp normalize_types(nil), do: []
  defp normalize_types(types) when is_list(types), do: Enum.filter(types, &is_binary/1)
  defp normalize_types(type) when is_binary(type), do: [type]
  defp normalize_types(_types), do: []

  defp denormalize_types([single]), do: single
  defp denormalize_types(types), do: types

  defp normalize_embedded_credentials(nil), do: []
  defp normalize_embedded_credentials(credentials) when is_list(credentials), do: credentials

  defp normalize_embedded_credentials(credential)
       when is_map(credential) or is_binary(credential),
       do: [credential]

  defp normalize_embedded_credentials(_credentials), do: []

  defp denormalize_embedded_credentials([single]), do: single
  defp denormalize_embedded_credentials(credentials), do: credentials

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp string_or_nil(value) when is_binary(value) and value != "", do: value
  defp string_or_nil(_value), do: nil
end
