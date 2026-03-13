defmodule ExVc.UpstreamParityTest do
  use ExUnit.Case, async: true

  @fixtures_root Path.expand("fixtures/upstream", __DIR__)
  @divergence_manifest Path.expand("fixtures/divergences/released.json", __DIR__)

  test "released DCB and Spruce parity fixtures match current VC validation outputs" do
    for stack <- ["dcb", "ssi"] do
      manifest = load_json(Path.join([@fixtures_root, stack, "released", "manifest.json"]))

      assert manifest["schemaVersion"] == 1
      assert manifest["advisory"] == false

      for test_case <- manifest["cases"] do
        recorded =
          load_json(Path.join([@fixtures_root, stack, "released", "cases", test_case["file"]]))

        assert run_operation(recorded["operation"], recorded["input"]) == recorded["expected"],
               inspect(
                 %{stack: stack, case: test_case["id"], expected: recorded["expected"]},
                 pretty: true
               )
      end
    end
  end

  test "released divergence log covers every DCB vs Spruce disagreement" do
    manifest = load_json(@divergence_manifest)

    assert manifest["schemaVersion"] == 1
    assert manifest["advisory"] == false

    documented =
      manifest["divergences"]
      |> Enum.map(& &1["file"])
      |> MapSet.new()

    actual =
      overlap_files()
      |> Enum.filter(fn file ->
        dcb_case(file)["expected"] != ssi_case(file)["expected"]
      end)
      |> MapSet.new()

    assert documented == actual
  end

  defp run_operation("validate", input) do
    %{"valid" => ExVc.valid?(input)}
  end

  defp overlap_files do
    dcb =
      Path.join([@fixtures_root, "dcb", "released", "cases", "*.json"])
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> MapSet.new()

    ssi =
      Path.join([@fixtures_root, "ssi", "released", "cases", "*.json"])
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> MapSet.new()

    dcb
    |> MapSet.intersection(ssi)
    |> MapSet.to_list()
  end

  defp dcb_case(file),
    do: load_json(Path.join([@fixtures_root, "dcb", "released", "cases", file]))

  defp ssi_case(file),
    do: load_json(Path.join([@fixtures_root, "ssi", "released", "cases", file]))

  defp load_json(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end
end
