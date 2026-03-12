# Supported Features

## Human-Readable Matrix

| Area | Status | Notes |
| --- | --- | --- |
| VC 2.0 envelope validation | Supported | Context, type, issuer, subject, status, proof shape, and temporal validation |
| VC issuance helper | Supported | `ExVc.issue/2` builds normalized credentials and supports release-1 `vc+jwt` issuance |
| Verifiable Presentation boundary | Supported | Structural VP validation plus embedded credential verification hooks that fail closed |
| VC-JWT (`vc+jwt`) | Supported | ES256 and EdDSA signing and verification, with direct JWK or `ex_did`-resolved verification keys |
| DID-based verification | Supported | Delegated to `ex_did` for method-aware verification key normalization |
| DCB released parity fixtures | Supported | Contractual today for VC envelope validation |
| Spruce released parity fixtures | Supported | Contractual today for VC envelope validation |
| TS parity recorder | Supported for fixture refresh | Maintainer-only tooling under `scripts/upstream_parity/` |
| Rust parity recorder | Supported for fixture refresh | Maintainer-only tooling under `scripts/ssi_parity/` |

## Deferred From Release 1 Contract

These modules remain in-tree for later parity work but are not part of the
release 1 support contract or Hex support posture:

| Area | Release 1 Status | Notes |
| --- | --- | --- |
| Data Integrity | Deferred | Not advertised as a supported release feature until upstream-recorded parity exists |
| SD-JWT VC | Deferred | Not advertised as a supported release feature until upstream-recorded parity exists |

## Machine-Readable Matrix

```json
{
  "vc_model": {
    "validation": "supported",
    "issuance_helper": "supported",
    "presentations": "supported"
  },
  "proof_formats": {
    "jwt_vc": {
      "status": "supported",
      "algs": ["ES256", "EdDSA"]
    },
    "data_integrity": {
      "status": "deferred"
    },
    "sd_jwt_vc": {
      "status": "deferred"
    }
  },
  "did_integration": {
    "status": "supported",
    "source_of_truth": "ex_did"
  },
  "interop": {
    "typescript": {
      "status": "supported",
      "released_surfaces": ["vc_envelope_validation"]
    },
    "rust": {
      "status": "supported",
      "released_surfaces": ["vc_envelope_validation"]
    }
  }
}
```
