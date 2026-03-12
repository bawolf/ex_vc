defmodule ExVcTest do
  use ExUnit.Case, async: true

  alias ExVc.Credential
  alias ExVc.Presentation
  alias ExVc.ValidationError
  alias ExVc.VerificationResult

  @fixtures_dir Path.expand("fixtures", __DIR__)
  @golden_dir Path.join(@fixtures_dir, "golden")

  defp signing_jwk do
    JOSE.JWK.generate_key({:ec, "P-256"})
  end

  defp holder_jwk do
    JOSE.JWK.generate_key({:ec, "P-256"})
  end

  defp did_key_for_p256_jwk(jwk) do
    {_kty, public_jwk} = JOSE.JWK.to_public_map(jwk)
    x = Base.url_decode64!(public_jwk["x"], padding: false)
    y = Base.url_decode64!(public_jwk["y"], padding: false)
    fingerprint = ExDid.Base58Btc.encode(<<0x80, 0x24, 4, x::binary, y::binary>>)
    did = "did:key:" <> fingerprint
    {did, did <> "#" <> fingerprint}
  end

  defp sign_compact_jwt(jwk, header, claims) do
    claims
    |> Jason.encode!()
    |> then(&JOSE.JWS.sign(jwk, &1, header))
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp eddsa_jwk do
    JOSE.JWK.generate_key({:okp, :Ed25519})
  end

  defp valid_credential do
    %{
      "@context" => ["https://www.w3.org/ns/credentials/v2"],
      "id" => "urn:delegate:credential:test",
      "type" => ["VerifiableCredential", "AgentDelegationCredential"],
      "issuer" => %{
        "id" => "did:web:greenfield.gov",
        "name" => "Greenfield Water Utility"
      },
      "validFrom" => "2026-03-10T12:00:00Z",
      "validUntil" => "2026-03-11T12:00:00Z",
      "credentialStatus" => %{
        "id" => "https://delegate.local/status-lists/revocation#7",
        "type" => "BitstringStatusListEntry",
        "statusPurpose" => "revocation",
        "statusListCredential" => "https://delegate.local/status-lists/revocation",
        "statusListIndex" => "7"
      },
      "credentialSubject" => %{
        "id" => "did:key:z6MkexampleAgent",
        "principal" => %{
          "id" => "did:web:greenfield.gov",
          "displayName" => "Greenfield Water Utility"
        },
        "issuerActor" => %{
          "id" => "issuer_123",
          "displayName" => "Maria Santos",
          "role" => "Customer Service Manager"
        },
        "agent" => %{
          "id" => "did:key:z6MkexampleAgent",
          "displayName" => "Billing Support Agent",
          "verificationMethod" => "did:key:z6MkexampleAgent#key-1"
        },
        "grants" => [],
        "expectedChannels" => []
      }
    }
  end

  test "generic VC 2.0 validation passes for valid credentials" do
    assert {:ok, report} = ExVc.validate(valid_credential())
    assert report.errors == []
    assert %Credential{} = report.parsed.normalized
    assert %DateTime{} = report.parsed.valid_from
    assert %DateTime{} = report.parsed.valid_until
  end

  test "load/1 normalizes common VC envelope fields" do
    assert {:ok, credential} = ExVc.load(valid_credential())
    assert credential.types == ["VerifiableCredential", "AgentDelegationCredential"]
    assert credential.issuer["id"] == "did:web:greenfield.gov"

    assert ExVc.to_map(credential)["type"] == [
             "VerifiableCredential",
             "AgentDelegationCredential"
           ]
  end

  test "issue/2 builds a validated credential map" do
    assert {:ok, credential} =
             ExVc.issue(%{"credentialSubject" => %{"id" => "did:key:z6MkwExample"}},
               issuer: "did:web:example.com",
               id: "urn:delegate:issued",
               valid_from: "2026-03-11T12:00:00Z",
               types: ["VerifiableCredential", "ExampleCredential"]
             )

    assert credential["issuer"] == "did:web:example.com"
    assert credential["type"] == ["VerifiableCredential", "ExampleCredential"]
    assert {:ok, _report} = ExVc.validate(credential)
  end

  test "issue/2 can sign a vc+jwt directly" do
    jwk = signing_jwk()

    assert {:ok, jwt} =
             ExVc.issue(valid_credential(),
               issuer: valid_credential()["issuer"],
               format: :jwt_vc,
               jwk: jwk
             )

    assert {:ok, %VerificationResult{format: :jwt_vc, verified: true}} =
             ExVc.verify(jwt, jwk: jwk)
  end

  test "missing required fields fail with stable error output" do
    assert {:error, report} = ExVc.validate(%{"type" => ["VerifiableCredential"]})

    assert Enum.any?(report.errors, &(&1.field == "@context"))
    assert Enum.any?(report.errors, &(&1.field == "issuer"))
    assert Enum.any?(report.errors, &(&1.field == "credentialSubject"))
  end

  test "custom required types are enforced by validation options" do
    credential =
      valid_credential()
      |> Map.put("type", ["VerifiableCredential"])

    assert {:error, report} =
             ExVc.validate(credential, required_types: ["AgentDelegationCredential"])

    assert Enum.any?(report.errors, &(&1.code == "missing_required_type"))
  end

  test "custom validators add profile-specific errors without changing the core package" do
    validator = fn credential, _report ->
      case get_in(credential, ["credentialSubject", "principal", "displayName"]) do
        value when is_binary(value) and value != "" ->
          []

        _ ->
          [
            ValidationError.new(
              "credentialSubject.principal.displayName",
              "required",
              "principal.displayName is required"
            )
          ]
      end
    end

    credential = put_in(valid_credential(), ["credentialSubject", "principal"], %{})

    assert {:error, report} = ExVc.validate(credential, validators: [validator])
    assert Enum.any?(report.errors, &(&1.field == "credentialSubject.principal.displayName"))
  end

  test "invalid timestamps fail validation when present" do
    credential =
      valid_credential()
      |> Map.put("validFrom", "not-a-date")
      |> Map.put("validUntil", "also-not-a-date")

    assert {:error, report} = ExVc.validate(credential)

    assert Enum.any?(report.errors, &(&1.field == "validFrom"))
    assert Enum.any?(report.errors, &(&1.field == "validUntil"))
  end

  test "valid_until before valid_from fails validation" do
    credential =
      valid_credential()
      |> Map.put("validFrom", "2026-03-11T12:00:00Z")
      |> Map.put("validUntil", "2026-03-10T12:00:00Z")

    assert {:error, report} = ExVc.validate(credential)

    assert Enum.any?(report.errors, &(&1.code == "invalid_temporal_order"))
  end

  test "bitstring status entries require status list fields" do
    credential =
      put_in(valid_credential(), ["credentialStatus"], %{"type" => "BitstringStatusListEntry"})

    assert {:error, report} = ExVc.validate(credential)

    assert Enum.any?(report.errors, &(&1.field == "credentialStatus.id"))
    assert Enum.any?(report.errors, &(&1.field == "credentialStatus.statusListIndex"))
  end

  test "credentialSubject may be an array of subject objects" do
    credential =
      valid_credential()
      |> Map.put("credentialSubject", [
        %{"id" => "did:key:z6Mksubject1"},
        %{"id" => "did:key:z6Mksubject2"}
      ])

    assert {:ok, _report} = ExVc.validate(credential)
  end

  test "proof entries are validated when present" do
    credential =
      valid_credential()
      |> Map.put("proof", %{"type" => "DataIntegrityProof", "created" => "invalid"})

    assert {:error, report} = ExVc.validate(credential)
    assert Enum.any?(report.errors, &(&1.field == "proof.created"))
  end

  test "load_presentation/1 and verify_presentation/2 support verifiable presentations" do
    presentation = fixture!("valid_presentation.json")

    assert {:ok, normalized} = ExVc.load_presentation(presentation)
    assert %Presentation{} = normalized

    assert {:ok, verification} = ExVc.verify_presentation(presentation, verify_credentials: true)
    assert verification.verified
    assert verification.metadata["verifiedCredentials"] == 0
  end

  test "verify_presentation/2 rejects malformed embedded credentials" do
    presentation =
      fixture!("valid_presentation.json")
      |> put_in(["verifiableCredential"], [%{"issuer" => "did:web:example.com"}])

    assert {:error, errors} = ExVc.verify_presentation(presentation)
    assert Enum.any?(errors, &(&1.field == "verifiableCredential[0]"))
  end

  test "verify_presentation/2 fails closed when embedded credential verification fails" do
    credential = valid_credential()
    good_jwk = signing_jwk()
    bad_jwk = signing_jwk()
    {:ok, jwt} = ExVc.sign_jwt_vc(credential, good_jwk)

    presentation =
      fixture!("valid_presentation.json")
      |> Map.put("verifiableCredential", [jwt])

    assert {:error, errors} =
             ExVc.verify_presentation(presentation,
               verify_credentials: true,
               jwk: bad_jwk
             )

    assert Enum.any?(errors, &(&1.field == "verifiableCredential[0]"))
    assert Enum.any?(errors, &(&1.code == "invalid_credential"))
  end

  test "valid?/2 returns a boolean" do
    assert ExVc.valid?(valid_credential())
    refute ExVc.valid?(%{"issuer" => "did:web:greenfield.gov"})
  end

  test "sign_jwt_vc/3 signs a vc+jwt and verify_jwt_vc/2 decodes it" do
    credential = valid_credential()
    jwk = signing_jwk()

    assert {:ok, jwt} = ExVc.sign_jwt_vc(credential, jwk)
    assert is_binary(jwt)

    assert {:ok, verification} = ExVc.verify_jwt_vc(jwt, jwk: jwk)
    assert verification.credential["id"] == credential["id"]
    assert verification.proof["typ"] == "vc+jwt"
    assert verification.representation == jwt
    assert verification.format == :jwt_vc
  end

  test "generic verify/2 auto-detects vc+jwt" do
    credential = valid_credential()
    jwk = signing_jwk()
    {:ok, jwt} = ExVc.sign_jwt_vc(credential, jwk)

    assert {:ok, %VerificationResult{format: :jwt_vc, verified: true}} =
             ExVc.verify(jwt, jwk: jwk)
  end

  test "vc+jwt verification can resolve issuer keys through ex_did multikey normalization" do
    jwk = signing_jwk()
    {issuer_did, _verification_method} = did_key_for_p256_jwk(jwk)

    credential =
      valid_credential()
      |> Map.put("issuer", issuer_did)

    {:ok, jwt} = ExVc.sign_jwt_vc(credential, jwk)

    assert {:ok, %VerificationResult{format: :jwt_vc, verified: true}} =
             ExVc.verify_jwt_vc(jwt, issuer_did: issuer_did)
  end

  test "data integrity adapter signs and verifies supported suites" do
    credential = valid_credential()
    jwk = eddsa_jwk()

    assert {:ok, signed} =
             ExVc.sign(credential, jwk,
               format: :data_integrity,
               alg: "EdDSA",
               verification_method: "did:key:z6Mkissuer#key-1"
             )

    assert %{"proof" => %{"type" => "DataIntegrityProof", "cryptosuite" => "eddsa-jcs-2022"}} =
             signed

    assert {:ok, %VerificationResult{format: :data_integrity, verified: true}} =
             ExVc.verify(signed, format: :data_integrity, jwk: jwk)
  end

  test "data integrity verification resolves multikey verification methods through ex_did" do
    jwk = signing_jwk()
    {issuer_did, verification_method} = did_key_for_p256_jwk(jwk)

    credential =
      valid_credential()
      |> Map.put("issuer", issuer_did)

    assert {:ok, signed} =
             ExVc.sign(credential, jwk,
               format: :data_integrity,
               alg: "ES256",
               verification_method: verification_method
             )

    assert {:ok, %VerificationResult{format: :data_integrity, verified: true}} =
             ExVc.verify(signed, format: :data_integrity)
  end

  test "data integrity adapter rejects unsupported suites" do
    assert {:error, :unsupported_data_integrity_suite} =
             ExVc.sign(valid_credential(), signing_jwk(),
               format: :data_integrity,
               suite: "bbs-2023"
             )
  end

  test "sd-jwt vc signs and verifies disclosed claims" do
    credential = valid_credential()
    issuer_jwk = signing_jwk()

    assert {:ok, sd_jwt} =
             ExVc.sign(credential, issuer_jwk,
               format: :sd_jwt_vc,
               disclose_paths: ["credentialSubject.agent.displayName"]
             )

    assert {:ok, %VerificationResult{format: :sd_jwt_vc, verified: true} = verification} =
             ExVc.verify(sd_jwt, jwk: issuer_jwk)

    assert get_in(verification.credential, ["credentialSubject", "agent", "displayName"]) ==
             "Billing Support Agent"
  end

  test "sd-jwt vc verifies optional key binding when provided" do
    credential = valid_credential()
    issuer_jwk = signing_jwk()
    holder = holder_jwk()

    assert {:ok, sd_jwt} =
             ExVc.sign(credential, issuer_jwk,
               format: :sd_jwt_vc,
               disclose_paths: ["credentialSubject.agent.displayName"],
               holder_jwk: holder,
               audience: "delegate",
               nonce: "nonce"
             )

    assert {:ok, %VerificationResult{verified: true}} =
             ExVc.verify(sd_jwt,
               jwk: issuer_jwk,
               holder_jwk: holder,
               audience: "delegate",
               nonce: "nonce"
             )
  end

  test "sd-jwt vc rejects mismatched key binding hashes" do
    credential = valid_credential()
    issuer_jwk = signing_jwk()
    holder = holder_jwk()

    {:ok, sd_jwt} =
      ExVc.sign(credential, issuer_jwk,
        format: :sd_jwt_vc,
        disclose_paths: ["credentialSubject.agent.displayName"],
        holder_jwk: holder,
        audience: "delegate",
        nonce: "nonce"
      )

    [issuer_jwt, disclosure, key_binding_jwt] = String.split(sd_jwt, "~", parts: 3)

    [encoded_header, _encoded_payload, _encoded_signature] =
      String.split(key_binding_jwt, ".", parts: 3)

    header =
      encoded_header
      |> Base.url_decode64!(padding: false)
      |> Jason.decode!()

    tampered_key_binding_jwt =
      sign_compact_jwt(holder, header, %{
        "iat" => System.system_time(:second),
        "aud" => "delegate",
        "nonce" => "nonce",
        "sd_hash" => "wrong"
      })

    tampered = Enum.join([issuer_jwt, disclosure, tampered_key_binding_jwt], "~")

    assert {:error, :invalid_sd_jwt_kb_hash} =
             ExVc.verify(tampered,
               jwk: issuer_jwk,
               holder_jwk: holder,
               audience: "delegate",
               nonce: "nonce"
             )
  end

  test "sd-jwt vc can resolve issuer and holder keys through ex_did multikey normalization" do
    issuer_jwk = signing_jwk()
    holder = holder_jwk()
    {issuer_did, _issuer_verification_method} = did_key_for_p256_jwk(issuer_jwk)
    {holder_did, _holder_verification_method} = did_key_for_p256_jwk(holder)

    credential =
      valid_credential()
      |> Map.put("issuer", issuer_did)

    assert {:ok, sd_jwt} =
             ExVc.sign(credential, issuer_jwk,
               format: :sd_jwt_vc,
               disclose_paths: ["credentialSubject.agent.displayName"],
               holder_jwk: holder,
               audience: "delegate",
               nonce: "nonce"
             )

    assert {:ok, %VerificationResult{format: :sd_jwt_vc, verified: true}} =
             ExVc.verify(sd_jwt,
               issuer_did: issuer_did,
               holder_did: holder_did,
               audience: "delegate",
               nonce: "nonce"
             )
  end

  test "sd-jwt vc rejects tampered disclosures" do
    issuer_jwk = signing_jwk()

    {:ok, sd_jwt} =
      ExVc.sign(valid_credential(), issuer_jwk,
        format: :sd_jwt_vc,
        disclose_paths: ["credentialSubject.agent.displayName"]
      )

    tampered =
      sd_jwt
      |> String.split("~")
      |> List.update_at(1, fn disclosure -> disclosure <> "tampered" end)
      |> Enum.join("~")

    assert {:error, :invalid_sd_jwt_disclosure} = ExVc.verify(tampered, jwk: issuer_jwk)
  end

  test "rejects signing invalid credentials as vc+jwt" do
    assert {:error, :invalid_vc} =
             ExVc.sign_jwt_vc(%{"issuer" => "did:web:greenfield.gov"}, signing_jwk())
  end

  test "rejects vc+jwt values with invalid signatures" do
    credential = valid_credential()
    signing_jwk = signing_jwk()
    verifying_jwk = signing_jwk()

    assert {:ok, jwt} = ExVc.sign_jwt_vc(credential, signing_jwk)
    assert {:error, :invalid_jwt_vc_signature} = ExVc.verify_jwt_vc(jwt, jwk: verifying_jwk)
  end

  test "golden fixtures remain valid" do
    minimal = fixture!("minimal_vc.json")

    assert {:ok, _report} = ExVc.validate(minimal)
  end

  defp fixture!(name) do
    @golden_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end
end
