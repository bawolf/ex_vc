defmodule ExVc.JsonCanonicalization do
  @moduledoc false

  @spec encode(term()) :: String.t()
  def encode(value) do
    IO.iodata_to_binary(encode_value(value))
  end

  defp encode_value(%{} = map) do
    entries =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, value} ->
        [Jason.encode!(to_string(key)), ?:, encode_value(value)]
      end)

    [?{, Enum.intersperse(entries, ?,), ?}]
  end

  defp encode_value(list) when is_list(list) do
    [?[, Enum.intersperse(Enum.map(list, &encode_value/1), ?,), ?]]
  end

  defp encode_value(value) when is_binary(value), do: Jason.encode!(value)
  defp encode_value(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_value(value) when is_float(value), do: Jason.encode!(value)
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(nil), do: "null"
end
