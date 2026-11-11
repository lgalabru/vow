//! Stable member identity for the pinned external-signature bridge.
//! Derivation is offline; it does not initialize or verify an on-chain account.
use crate::text;
use p256::ecdsa::VerifyingKey;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use solana_pubkey::Pubkey;
use std::str::FromStr;

pub const BRIDGE_PROGRAM: &str = "ExtSgUPtP3JyKUysFw2S5fpL5fWfUPzGUQLd2bTwftXN";

/// Derive the bridge's ExternalAccount signer from a canonical compressed P-256 key.
pub fn derive(request: &Value) -> Result<Value, String> {
    let encoded = text(request, "public_key")?;
    if encoded.len() != 66
        || !encoded
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("Use a canonical compressed P-256 public key.".into());
    }
    let key = hex::decode(encoded).map_err(|_| "Invalid public-key encoding.")?;
    let verifying = VerifyingKey::from_sec1_bytes(&key).map_err(|_| "Invalid P-256 public key.")?;
    if verifying.to_encoded_point(true).as_bytes() != key {
        return Err("Public key is not canonical compressed P-256.".into());
    }
    let program = Pubkey::from_str(BRIDGE_PROGRAM).map_err(|_| "Invalid pinned bridge program.")?;
    let key_hash = Sha256::digest(&key);
    let (member, bump) = Pubkey::try_find_program_address(&[b"passkey", &key_hash], &program)
        .ok_or("Cannot derive member address.")?;
    Ok(json!({
        "format":"vow.member-address.v1", "address":member.to_string(), "bump":bump,
        "bridge_program":BRIDGE_PROGRAM, "signer_execution_scheme":"external_account",
        "device_public_key":encoded, "registration_status":"not_checked",
        "network_binding":"same_program_id_same_address_across_clusters"
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use p256::ecdsa::SigningKey;

    #[test]
    fn independent_sdk_vector_matches_external_account_and_is_off_curve() {
        // Cross-checked with solders.Pubkey.find_program_address and the pinned SDK seeds.
        let public = "037676f5d8ab2ca08362d79d872869f0bc20eda6fe75eb62a1db5bce501266bfba";
        let result = derive(&json!({"public_key":public})).unwrap();
        assert_eq!(
            result["address"],
            "CEtC6SL3x6Zf8GUsDvuC2t5FXR7DPWDKjzZdpxBCQDcn"
        );
        assert_eq!(result["bump"], 253);
        assert_eq!(result["signer_execution_scheme"], "external_account");
        assert_eq!(result["registration_status"], "not_checked");
        let member = Pubkey::from_str(result["address"].as_str().unwrap()).unwrap();
        assert!(!member.is_on_curve());
        let program = Pubkey::from_str(BRIDGE_PROGRAM).unwrap();
        let (legacy, _) =
            Pubkey::find_program_address(&[member.as_ref(), b"execution_account"], &program);
        assert_eq!(
            legacy.to_string(),
            "33XjFUFBwwqBKeRK9Vg8gWx3drj1x9VpVdQtMkgZNpKp"
        );
        assert_ne!(member, legacy);
    }

    #[test]
    fn malformed_or_ambiguous_keys_never_produce_an_address() {
        let valid = SigningKey::from_slice(&[3; 32])
            .unwrap()
            .verifying_key()
            .to_encoded_point(true);
        let valid_hex = hex::encode(valid);
        for key in [
            String::new(),
            "00".repeat(33),
            "02".to_owned() + &"ff".repeat(32),
            valid_hex.to_uppercase(),
            valid_hex[..64].into(),
            "00".repeat(65),
            "zz".repeat(33),
        ] {
            assert!(derive(&json!({"public_key":key})).is_err());
        }
        assert!(derive(&json!({"public_key":null})).is_err());
        let other = SigningKey::from_slice(&[4; 32]).unwrap();
        assert_ne!(
            derive(&json!({"public_key":valid_hex})).unwrap()["address"],
            derive(
                &json!({"public_key":hex::encode(other.verifying_key().to_encoded_point(true))})
            )
            .unwrap()["address"]
        );
    }
}
