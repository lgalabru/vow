//! Offline device enrollment. Proofs bind two keys, not a person or chain membership.
use crate::{canonical_bytes, digest, text};
use p256::ecdsa::{Signature, VerifyingKey, signature::Verifier};
use p256::elliptic_curve::rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
pub const FIDO_RP_ID: &str = "vow.invalid";

const FORMAT: &str = "vow.device-enrollment.v1";
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Enrollment {
    format: String,
    device_public_key: String,
    security_key_public_key: String,
    key_source: String,
    nonce: String,
    security_key_slot: String,
    pin_policy: String,
    touch_policy: String,
    purpose: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    security_key_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    credential_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    rp_id: Option<String>,
}
fn key(value: &str) -> Result<VerifyingKey, String> {
    if value.len() != 66
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err("Use a compressed P-256 public key.".into());
    }
    VerifyingKey::from_sec1_bytes(&hex::decode(value).map_err(|_| "Invalid key encoding.")?)
        .map_err(|_| "Invalid P-256 public key.".into())
}
pub fn prepare(request: &Value) -> Result<Value, String> {
    let device = text(request, "device_public_key")?;
    let security = text(request, "security_key_public_key")?;
    key(device)?;
    key(security)?;
    let source = text(request, "key_source")?;
    if !["secure_enclave", "simulator_software"].contains(&source) || device == security {
        return Err("Device enrollment requires two distinct signing keys.".into());
    }
    let mut nonce = [0u8; 32];
    OsRng
        .try_fill_bytes(&mut nonce)
        .map_err(|_| "Cannot create enrollment challenge.")?;
    for field in ["security_key_kind", "credential_id"] {
        if !request[field].is_null() && !request[field].is_string() {
            return Err("Invalid enrollment method field type.".into());
        }
    }
    let kind = request["security_key_kind"].as_str().unwrap_or("piv");
    validate_kind(kind, request["credential_id"].as_str())?;
    let native = kind == "webauthn";
    let fido = kind == "fido2" || native;
    let message = canonical_bytes(&Enrollment {
        format: if native {
            "vow.device-enrollment.v3"
        } else if fido {
            "vow.device-enrollment.v2"
        } else {
            FORMAT
        }
        .into(),
        device_public_key: device.into(),
        security_key_public_key: security.into(),
        key_source: source.into(),
        nonce: hex::encode(nonce),
        security_key_slot: if fido { "" } else { "82" }.into(),
        pin_policy: if fido {
            "user_verification_required"
        } else {
            "always"
        }
        .into(),
        touch_policy: if fido {
            "user_presence_required"
        } else {
            "always"
        }
        .into(),
        purpose: "offline_device_enrollment_only".into(),
        security_key_kind: fido.then(|| kind.into()),
        credential_id: if fido {
            Some(text(request, "credential_id")?.into())
        } else {
            None
        },
        rp_id: if native {
            Some(
                crate::native_webauthn::rp_id()
                    .ok_or("Native security-key domain is not configured.")?
                    .into(),
            )
        } else {
            fido.then(|| FIDO_RP_ID.into())
        },
    });
    Ok(json!({"message_hex": hex::encode(message)}))
}
pub fn verify_signature(
    public_key: &str,
    message: &[u8],
    signature_hex: &str,
) -> Result<(), String> {
    if signature_hex.len() != 128 {
        return Err("Invalid P-256 signature size.".into());
    }
    let signature = Signature::from_slice(
        &hex::decode(signature_hex).map_err(|_| "Invalid signature encoding.")?,
    )
    .map_err(|_| "Invalid signature.")?;
    key(public_key)?
        .verify(message, &signature)
        .map_err(|_| "Signing-key proof does not match the reviewed bytes.".into())
}
pub fn validate_kind(kind: &str, credential: Option<&str>) -> Result<(), String> {
    match kind {
        "piv" if credential.is_none() => Ok(()),
        "fido2" | "webauthn"
            if (kind != "webauthn" || crate::native_webauthn::rp_id().is_some())
                && credential.is_some_and(|id| {
                    !id.is_empty()
                        && id.len() <= 2048
                        && id.len().is_multiple_of(2)
                        && id
                            .bytes()
                            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
                }) =>
        {
            Ok(())
        }
        _ => Err("Unsupported registered-key method or credential identifier.".into()),
    }
}
/// Verify an offline CTAP assertion. No website origin or factory attestation is implied.
pub fn verify_fido_signature(
    public: &str,
    message: &[u8],
    signature: &str,
    auth_hex: &str,
) -> Result<(), String> {
    if auth_hex.len() != 74 {
        return Err("Unsupported FIDO authenticator data.".into());
    }
    let auth = hex::decode(auth_hex).map_err(|_| "Invalid FIDO authenticator data.")?;
    let rp_hash = Sha256::digest(FIDO_RP_ID.as_bytes());
    if auth[..32] != rp_hash[..] || auth[32] != 0x05 {
        return Err("FIDO proof requires the Vow namespace, user presence, user verification and a non-backup credential.".into());
    }
    let mut signed = auth;
    signed.extend_from_slice(&Sha256::digest(message));
    verify_signature(public, &signed, signature)
}
pub fn verify(request: &Value) -> Result<Value, String> {
    let encoded = text(request, "message_hex")?;
    if encoded.len() > 8192 {
        return Err("Enrollment exceeds size limit.".into());
    }
    let message = hex::decode(encoded).map_err(|_| "Invalid enrollment encoding.")?;
    let enrollment: Enrollment =
        serde_json::from_slice(&message).map_err(|_| "Invalid enrollment structure.")?;
    let native = enrollment.security_key_kind.as_deref() == Some("webauthn");
    let fido = enrollment.security_key_kind.as_deref() == Some("fido2");
    validate_kind(
        enrollment.security_key_kind.as_deref().unwrap_or("piv"),
        enrollment.credential_id.as_deref(),
    )?;
    let policy_valid = if native {
        enrollment.format == "vow.device-enrollment.v3"
            && enrollment.security_key_slot.is_empty()
            && enrollment.pin_policy == "user_verification_required"
            && enrollment.touch_policy == "user_presence_required"
            && enrollment.rp_id.as_deref() == crate::native_webauthn::rp_id()
            && enrollment.rp_id.is_some()
    } else if fido {
        enrollment.format == "vow.device-enrollment.v2"
            && enrollment.security_key_slot.is_empty()
            && enrollment.pin_policy == "user_verification_required"
            && enrollment.touch_policy == "user_presence_required"
            && enrollment.rp_id.as_deref() == Some(FIDO_RP_ID)
    } else {
        enrollment.format == FORMAT
            && enrollment.security_key_slot == "82"
            && enrollment.pin_policy == "always"
            && enrollment.touch_policy == "always"
            && enrollment.security_key_kind.is_none()
            && enrollment.rp_id.is_none()
    };
    if !policy_valid
        || enrollment.purpose != "offline_device_enrollment_only"
        || !["secure_enclave", "simulator_software"].contains(&enrollment.key_source.as_str())
        || enrollment.nonce.len() != 64
        || hex::decode(&enrollment.nonce).is_err()
        || enrollment.device_public_key == enrollment.security_key_public_key
        || canonical_bytes(&enrollment) != message
    {
        return Err("Unsupported enrollment policy.".into());
    }
    let device_signature = text(request, "device_signature")?;
    let security_signature = text(request, "security_key_signature")?;
    verify_signature(&enrollment.device_public_key, &message, device_signature)?;
    if native {
        crate::native_webauthn::verify_assertion(
            &enrollment.security_key_public_key,
            &message,
            security_signature,
            text(request, "security_key_authenticator_data")?,
            text(request, "security_key_client_data_json")?,
        )?;
    } else if fido {
        verify_fido_signature(
            &enrollment.security_key_public_key,
            &message,
            security_signature,
            text(request, "security_key_authenticator_data")?,
        )?;
    } else {
        verify_signature(
            &enrollment.security_key_public_key,
            &message,
            security_signature,
        )?;
    }
    let fingerprint =
        digest(&hex::decode(&enrollment.device_public_key).map_err(|_| "Invalid key.")?);
    let mut package = json!({"format":enrollment.format,"message_hex":encoded,"device_signature":device_signature,
        "security_key_signature":security_signature,"identity_fingerprint":fingerprint,
        "on_chain_registration":"not_registered","hardware_attestation":"not_verified"});
    if native {
        package["security_key_client_data_json"] =
            json!(text(request, "security_key_client_data_json")?);
    }
    if fido || native {
        package["security_key_authenticator_data"] =
            json!(text(request, "security_key_authenticator_data")?);
    }
    Ok(
        json!({"fingerprint":fingerprint,"package":serde_json::to_string_pretty(&package).map_err(|_| "Cannot export identity.")?}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use p256::ecdsa::{SigningKey, signature::Signer};
    fn fido_proof(key: &SigningKey, message: &[u8], flags: u8, rp: &str) -> (String, String) {
        let mut auth = Sha256::digest(rp.as_bytes()).to_vec();
        auth.extend_from_slice(&[flags, 0, 0, 0, 1]);
        let mut signed = auth.clone();
        signed.extend_from_slice(&Sha256::digest(message));
        let signature: Signature = key.sign(&signed);
        (hex::encode(auth), hex::encode(signature.to_bytes()))
    }
    #[test]
    fn fido_enrollment_requires_exact_namespace_up_uv_and_both_keys() {
        let device = SigningKey::random(&mut OsRng);
        let security = SigningKey::random(&mut OsRng);
        let public = hex::encode(security.verifying_key().to_encoded_point(true));
        let challenge = prepare(&json!({"device_public_key":hex::encode(device.verifying_key().to_encoded_point(true)),"security_key_public_key":public,"key_source":"secure_enclave","security_key_kind":"fido2","credential_id":"aabbcc"})).unwrap();
        let message = hex::decode(challenge["message_hex"].as_str().unwrap()).unwrap();
        let device_signature: Signature = device.sign(&message);
        for (flags, rp, valid) in [
            (5, FIDO_RP_ID, true),
            (1, FIDO_RP_ID, false),
            (4, FIDO_RP_ID, false),
            (13, FIDO_RP_ID, false),
            (5, "other.invalid", false),
        ] {
            let (auth, signature) = fido_proof(&security, &message, flags, rp);
            let proof = json!({"message_hex":challenge["message_hex"],"device_signature":hex::encode(device_signature.to_bytes()),"security_key_signature":signature,"security_key_authenticator_data":auth});
            assert_eq!(verify(&proof).is_ok(), valid);
            if valid {
                let result = verify(&proof).unwrap();
                let package: Value =
                    serde_json::from_str(result["package"].as_str().unwrap()).unwrap();
                assert_eq!(package["format"], "vow.device-enrollment.v2");
                assert_eq!(package["on_chain_registration"], "not_registered");
                assert_eq!(verify(&package).unwrap()["package"], result["package"]);
                assert!(
                    verify_fido_signature(&public, b"another request", &signature, &auth).is_err()
                );
                assert!(
                    verify_fido_signature(&public, &message, &signature, &(auth + "00")).is_err()
                );
            }
        }
    }
    #[test]
    fn enrollment_requires_both_exact_key_proofs_and_domain() {
        let device = SigningKey::random(&mut OsRng);
        let security = SigningKey::random(&mut OsRng);
        let challenge = prepare(&json!({"device_public_key":hex::encode(device.verifying_key().to_encoded_point(true)),
            "security_key_public_key":hex::encode(security.verifying_key().to_encoded_point(true)),"key_source":"secure_enclave"})).unwrap();
        let device_hex = hex::encode(device.verifying_key().to_encoded_point(true));
        assert!(prepare(&json!({"device_public_key":device_hex,"security_key_public_key":device_hex,"key_source":"secure_enclave"})).is_err());
        assert!(prepare(&json!({"device_public_key":device_hex.to_uppercase(),"security_key_public_key":hex::encode(security.verifying_key().to_encoded_point(true)),"key_source":"secure_enclave"})).is_err());
        let message = hex::decode(challenge["message_hex"].as_str().unwrap()).unwrap();
        let ds: Signature = device.sign(&message);
        let ss: Signature = security.sign(&message);
        let mut proof = json!({"message_hex":challenge["message_hex"],"device_signature":hex::encode(ds.to_bytes()),"security_key_signature":hex::encode(ss.to_bytes())});
        assert_eq!(
            serde_json::from_str::<Value>(verify(&proof).unwrap()["package"].as_str().unwrap())
                .unwrap()["on_chain_registration"],
            "not_registered"
        );
        proof["security_key_signature"] = proof["device_signature"].clone();
        assert!(verify(&proof).is_err());
        proof["security_key_signature"] = json!(hex::encode(ss.to_bytes()));
        let mut altered: Value = serde_json::from_slice(&message).unwrap();
        altered["purpose"] = json!("approve_transaction");
        proof["message_hex"] = json!(hex::encode(canonical_bytes(&altered)));
        assert!(verify(&proof).is_err());
    }
}
