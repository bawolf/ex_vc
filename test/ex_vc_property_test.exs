defmodule ExVcPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "load/to_map preserves extra fields" do
    check all(value <- string(:printable, min_length: 1)) do
      credential = %{
        "@context" => ["https://www.w3.org/ns/credentials/v2"],
        "type" => ["VerifiableCredential"],
        "issuer" => "did:web:example.com",
        "credentialSubject" => %{"id" => "did:key:z6MkwExample"},
        "delegateExtension" => value
      }

      assert {:ok, normalized} = ExVc.load(credential)
      assert ExVc.to_map(normalized)["delegateExtension"] == value
    end
  end

  property "temporal order validation is invariant across well-formed ISO8601 timestamps" do
    check all(offset <- integer(1..86_400)) do
      valid_from = ~U[2026-03-11 12:00:00Z]
      valid_until = DateTime.add(valid_from, offset, :second)

      credential = %{
        "@context" => ["https://www.w3.org/ns/credentials/v2"],
        "type" => ["VerifiableCredential"],
        "issuer" => "did:web:example.com",
        "validFrom" => DateTime.to_iso8601(valid_from),
        "validUntil" => DateTime.to_iso8601(valid_until),
        "credentialSubject" => %{"id" => "did:key:z6MkwExample"}
      }

      assert {:ok, _report} = ExVc.validate(credential)
    end
  end

  property "subject list cardinality is stable" do
    subject =
      fixed_map(%{
        "id" => string(:alphanumeric, min_length: 5)
      })

    check all(subjects <- list_of(subject, min_length: 1, max_length: 3)) do
      credential = %{
        "@context" => ["https://www.w3.org/ns/credentials/v2"],
        "type" => ["VerifiableCredential"],
        "issuer" => "did:web:example.com",
        "credentialSubject" => subjects
      }

      assert {:ok, _report} = ExVc.validate(credential)
    end
  end
end
