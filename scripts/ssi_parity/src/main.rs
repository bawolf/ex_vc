use std::fs;
use std::path::PathBuf;

use chrono::Utc;
use serde::Serialize;
use serde_json::json;

#[derive(Serialize)]
struct Manifest<'a> {
    #[serde(rename = "schemaVersion")]
    schema_version: u8,
    advisory: bool,
    channel: &'a str,
    #[serde(rename = "generatedAt")]
    generated_at: String,
    recorder: serde_json::Value,
    packages: serde_json::Value,
    cases: Vec<serde_json::Value>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let channel = std::env::args().nth(1).unwrap_or_else(|| "released".to_string());

    if channel != "released" && channel != "main" {
        return Err(format!("unsupported channel: {channel}").into());
    }

    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../test/fixtures/upstream/ssi")
        .join(&channel);
    let cases_dir = root.join("cases");

    if cases_dir.exists() {
        fs::remove_dir_all(&cases_dir)?;
    }

    fs::create_dir_all(&cases_dir)?;

    let case = json!({
        "id": "minimal-vc-validation",
        "operation": "validate",
        "provenance": {
            "sourcePackage": "spruceid/ssi",
            "sourceUrl": "https://github.com/spruceid/ssi"
        },
        "expected": {
            "valid": true
        }
    });

    fs::write(
        cases_dir.join("minimal-vc-validation.json"),
        serde_json::to_string_pretty(&case)? + "\n",
    )?;

    let manifest = Manifest {
        schema_version: 1,
        advisory: channel == "main",
        channel: &channel,
        generated_at: Utc::now().to_rfc3339(),
        recorder: json!({
            "name": "ex_vc_ssi_parity",
            "packageManager": "cargo"
        }),
        packages: json!({
            "spruceid/ssi": "unversioned-recorder-scaffold"
        }),
        cases: vec![json!({
            "id": "minimal-vc-validation",
            "operation": "validate",
            "file": "minimal-vc-validation.json"
        })],
    };

    fs::write(
        root.join("manifest.json"),
        serde_json::to_string_pretty(&manifest)? + "\n",
    )?;

    Ok(())
}

