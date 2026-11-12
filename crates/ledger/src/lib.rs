//! Desktop Ledger adapter. No RPC, broadcasting, PIN entry or software-key fallback.
use serde_json::Value;

fn validate(request: &Value) -> Result<(), String> {
    let action = request["action"].as_str().ok_or("Missing Ledger action.")?;
    if ![
        "connect",
        "sign_enrollment",
        "sign_identity",
        "sign_approval",
    ]
    .contains(&action)
    {
        return Err("Unsupported Ledger operation.".into());
    }
    let path = request["derivation_path"]
        .as_str()
        .unwrap_or("m/44'/501'/0'");
    vow_core::profiles::validate_path(path)?;
    if action != "connect" {
        let message = request["message"]
            .as_str()
            .ok_or("Missing enrollment or approval message.")?;
        let expected = request["expected_address"]
            .as_str()
            .ok_or("Missing expected Ledger account.")?;
        let body: Value = serde_json::from_str(message).map_err(|_| "Invalid Ledger message.")?;
        if body["domain"]
            != if action == "sign_identity" {
                "vow.identity.enrollment.v1"
            } else if action == "sign_enrollment" {
                "vow.profile.enrollment.v1"
            } else {
                "vow.profile.approval.v1"
            }
            || body["address"] != expected
            || body["derivation_path"] != path
        {
            return Err("Ledger message type, account or path changed.".into());
        }
        let _ = vow_core::profiles::ledger_envelope(expected, message.as_bytes())?;
    }
    Ok(())
}
pub fn execute(request: &Value) -> Result<Value, String> {
    validate(request)?;
    #[cfg(target_os = "macos")]
    {
        desktop(request)
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = request;
        Err("Desktop Ledger HID is unavailable on this platform.".into())
    }
}
// The backend intentionally redacts Display. Translate device-state details into
// fixed user guidance instead of exposing raw HID paths or arbitrary payloads.
#[cfg(target_os = "macos")]
fn desktop_error(error: solana_keychain::SignerError) -> String {
    use solana_keychain::SignerError;
    match error {
        SignerError::NotAvailable(detail) if detail.contains("configuration format") =>
            "This version of Vow cannot read the Ledger Solana app. Update Vow; your Ledger does not need to be reset.".into(),
        SignerError::NotAvailable(detail) if detail.contains("devices connected") =>
            "Connect only one Ledger, then retry.".into(),
        SignerError::NotAvailable(detail) if detail.contains("already") || detail.contains("in progress") =>
            "Finish the pending Ledger request, then retry.".into(),
        SignerError::NotAvailable(_) =>
            "Vow could not access your Ledger. Unlock it, open Solana, and close Ledger Live or other wallet apps. Check the USB connection, then retry.".into(),
        SignerError::UserRejected(_) => "The request was declined on your Ledger. Retry when ready.".into(),
        SignerError::SigningFailed(_) => "Ledger could not sign. Dismiss any pending prompt on the device, check the Solana app settings, then retry.".into(),
        other => other.to_string(),
    }
}
#[cfg(target_os = "macos")]
fn desktop(request: &Value) -> Result<Value, String> {
    use serde_json::json;
    use solana_keychain::{LedgerConfig, LedgerSigner, SolanaSigner};
    let action = request["action"].as_str().ok_or("Missing Ledger action.")?;
    if ![
        "connect",
        "sign_enrollment",
        "sign_identity",
        "sign_approval",
    ]
    .contains(&action)
    {
        return Err("Unsupported Ledger operation.".into());
    }
    let path = request["derivation_path"]
        .as_str()
        .unwrap_or("m/44'/501'/0'");
    if path.len() > 80 || !path.starts_with("m/44'/501'/") {
        return Err("Choose a Solana account derivation path.".into());
    }
    let message = if action != "connect" {
        let message = request["message"]
            .as_str()
            .ok_or("Missing enrollment challenge.")?;
        if serde_json::from_str::<Value>(message).ok().is_none_or(|v| {
            v["domain"]
                != if action == "sign_identity" {
                    "vow.identity.enrollment.v1"
                } else if action == "sign_enrollment" {
                    "vow.profile.enrollment.v1"
                } else {
                    "vow.profile.approval.v1"
                }
        }) || message.len() > 1130
        {
            return Err("Only a bounded Vow enrollment challenge is accepted here.".into());
        }
        Some(message)
    } else {
        None
    };
    let signer = LedgerSigner::connect_with(LedgerConfig {
        derivation_path: Some(path.into()),
        confirm_pubkey_on_device: action == "connect",
        auto_open_app: false,
        ..LedgerConfig::default()
    })
    .map_err(desktop_error)?;
    let address = signer.pubkey().to_string();
    if action == "connect" {
        return Ok(
            json!({"address":address,"derivation_path":path,"proof":"device_address_confirmation_only"}),
        );
    }
    if request["expected_address"].as_str() != Some(address.as_str()) {
        return Err(
            "The Ledger account changed. Verify the enrolled account on the device.".into(),
        );
    }
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|_| "Cannot start the Ledger runtime.")?;
    let signature = runtime
        .block_on(signer.sign_message(message.expect("checked").as_bytes()))
        .map_err(desktop_error)?;
    Ok(
        json!({"address":address,"derivation_path":path,"signature_hex":hex::encode(signature.as_ref()),"scheme":"ledger_offchain_v0"}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn bad_requests_are_rejected_before_any_hardware_operation() {
        for request in [
            json!({}),
            json!({"action":"sign_transaction"}),
            json!({"action":"connect","derivation_path":"m/44'/0'/0'"}),
            json!({"action":"sign_approval","message":"{}"}),
            json!({"action":"sign_enrollment","message":"not json","expected_address":"bad"}),
        ] {
            assert!(validate(&request).is_err());
        }
        validate(&json!({"action":"connect","derivation_path":"m/44'/501'/0'"})).unwrap();
        let message=json!({"domain":"vow.identity.enrollment.v1","address":"11111111111111111111111111111111","derivation_path":"m/44'/501'/0'"}).to_string();
        let mut request = json!({"action":"sign_identity","expected_address":"11111111111111111111111111111111","message":message});
        validate(&request).unwrap();
        request["action"] = json!("sign_approval");
        assert!(validate(&request).is_err());
    }
    #[test]
    fn enrollment_and_approval_requests_cannot_exchange_domains() {
        let address = "11111111111111111111111111111111";
        let message=json!({"domain":"vow.profile.enrollment.v1","address":address,"derivation_path":"m/44'/501'/0'"}).to_string();
        let mut request =
            json!({"action":"sign_enrollment","expected_address":address,"message":message});
        validate(&request).unwrap();
        request["action"] = json!("sign_approval");
        assert!(validate(&request).is_err());
        request["action"] = json!("sign_enrollment");
        request["derivation_path"] = json!("m/44'/501'/1'");
        assert!(validate(&request).is_err());
    }
    #[cfg(target_os = "macos")]
    #[test]
    fn desktop_errors_explain_recovery_without_exposing_backend_details() {
        use solana_keychain::SignerError;
        let incompatible = desktop_error(SignerError::NotAvailable(
            "configuration format unsupported".into(),
        ));
        assert!(incompatible.contains("Update Vow"));
        assert!(incompatible.contains("does not need to be reset"));
        let unavailable = desktop_error(SignerError::NotAvailable(
            "private HID path /secret/device".into(),
        ));
        assert!(unavailable.contains("open Solana"));
        assert!(!unavailable.contains("/secret/device"));
        assert!(desktop_error(SignerError::UserRejected("private".into())).contains("declined"));
        assert!(
            desktop_error(SignerError::NotAvailable(
                "2 Ledger devices connected".into()
            ))
            .contains("only one")
        );
    }
    #[cfg(target_os = "macos")]
    #[test]
    fn mobile_envelopes_match_the_pr_pinned_keychain_backend() {
        let address = "11111111111111111111111111111111";
        let public = address.parse().unwrap();
        for payload in [
            b"Vow profile".as_slice(),
            b"line\nbreak".as_slice(),
            "café".as_bytes(),
            &vec![b'a'; 1130],
        ] {
            assert_eq!(
                vow_core::profiles::ledger_envelope(address, payload).unwrap(),
                solana_keychain::ledger::ledger_offchain_envelope(&public, payload).unwrap()
            );
        }
    }
}
