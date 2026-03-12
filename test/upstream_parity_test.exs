defmodule ExVc.UpstreamParityTest do
  use ExUnit.Case, async: true

  @fixtures_root Path.expand("fixtures/upstream", __DIR__)

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

  defp run_operation("validate", input) do
    %{"valid" => ExVc.valid?(input)}
  end

  defp load_json(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end
end
