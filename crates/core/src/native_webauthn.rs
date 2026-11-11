//! Native Apple security-key proofs. The relying party is pinned by the signed build.
use crate::{digest, identity, text};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use ciborium::value::Value as Cbor;
use p256::elliptic_curve::rand_core::{OsRng, RngCore};
use p256::{EncodedPoint, ecdsa::VerifyingKey};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::io::Cursor;

pub fn rp_id() -> Option<&'static str> {
    let configured = option_env!("VOW_WEBAUTHN_RP_ID").filter(|value| !value.is_empty());
    #[cfg(any(test, all(debug_assertions, target_os = "ios", target_abi = "sim")))]
    let configured = configured.or(Some("vow-native.test.invalid"));
    configured.filter(|domain| valid_domain(domain))
}
fn valid_domain(domain: &str) -> bool {
    domain.len() <= 253
        && domain.contains('.')
        && domain.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .bytes()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        })
}
pub fn configuration() -> Value {
    json!({"enabled":rp_id().is_some(),"rp_id":rp_id()})
}
fn configured_rp() -> Result<&'static str, String> {
    rp_id().ok_or(
        "Native security-key signing needs a configured associated domain in this build.".into(),
    )
}
fn bounded_hex(request: &Value, field: &str, max: usize) -> Result<Vec<u8>, String> {
    let input = text(request, field)?;
    if input.is_empty() || input.len() > max * 2 || !input.len().is_multiple_of(2) {
        return Err(format!("Invalid {field} size."));
    }
    hex::decode(input).map_err(|_| format!("Invalid {field} encoding."))
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ClientData {
    #[serde(rename = "type")]
    ceremony_type: String,
    challenge: String,
    origin: String,
    #[serde(default, rename = "crossOrigin")]
    cross_origin: bool,
}
fn check_client(raw: &[u8], challenge: &[u8], kind: &str) -> Result<(), String> {
    if raw.len() > 4096 {
        return Err("Native client data exceeds size limit.".into());
    }
    let client: ClientData =
        serde_json::from_slice(raw).map_err(|_| "Invalid native client data.")?;
    let rp = configured_rp()?;
    if client.ceremony_type != kind
        || client.origin != format!("https://{rp}")
        || client.cross_origin
        || URL_SAFE_NO_PAD
            .decode(&client.challenge)
            .map_err(|_| "Invalid native challenge.")?
            != challenge
    {
        return Err("Native security-key origin, challenge or request type does not match.".into());
    }
    Ok(())
}
fn check_auth(auth: &[u8], registration: bool) -> Result<(), String> {
    let rp = configured_rp()?;
    if auth.len() < 37 || auth[..32] != Sha256::digest(rp.as_bytes())[..] {
        return Err("Native authenticator does not match Vow's relying party.".into());
    }
    if registration {
        if auth[32] & 0x7f != 0x45 {
            return Err("Native registration requires PIN verification, touch and a device-bound credential.".into());
        }
    } else if auth.len() != 37 || auth[32] != 0x05 {
        return Err(
            "Native approval requires PIN verification, touch and a device-bound credential."
                .into(),
        );
    }
    Ok(())
}
fn cbor_value(bytes: &[u8]) -> Result<(Cbor, usize), String> {
    let mut cursor = Cursor::new(bytes);
    let value = ciborium::de::from_reader_with_recursion_limit(&mut cursor, 16)
        .map_err(|_| "Invalid or overly nested native credential CBOR.")?;
    Ok((value, cursor.position() as usize))
}
fn map_unique(value: &Cbor) -> Result<&[(Cbor, Cbor)], String> {
    let Cbor::Map(map) = value else {
        return Err("Expected a native credential map.".into());
    };
    if map.len() > 32 {
        return Err("Native credential map exceeds size limit.".into());
    }
    for (index, (key, _)) in map.iter().enumerate() {
        if map[..index].iter().any(|(other, _)| other == key) {
            return Err("Duplicate native credential map key.".into());
        }
    }
    Ok(map)
}
fn integer(value: &Cbor) -> Option<i128> {
    if let Cbor::Integer(value) = value {
        Some((*value).into())
    } else {
        None
    }
}
pub fn registration_challenge(request: &Value) -> Result<Value, String> {
    configured_rp()?;
    let public =
        hex::decode(text(request, "device_public_key")?).map_err(|_| "Invalid device key.")?;
    VerifyingKey::from_sec1_bytes(&public).map_err(|_| "Invalid device public key.")?;
    let mut random = [0u8; 64];
    OsRng
        .try_fill_bytes(&mut random)
        .map_err(|_| "Cannot create native registration challenge.")?;
    let mut input = b"vow.native.registration.v1".to_vec();
    input.extend(public);
    input.extend(&random[..32]);
    Ok(json!({"challenge_hex":digest(&input),"user_handle_hex":hex::encode(&random[32..])}))
}
pub fn parse_registration(request: &Value) -> Result<Value, String> {
    let rp = configured_rp()?;
    let challenge = bounded_hex(request, "challenge_hex", 32)?;
    if challenge.len() != 32 {
        return Err("Invalid native registration challenge length.".into());
    }
    let client = bounded_hex(request, "client_data_json_hex", 4096)?;
    check_client(&client, &challenge, "webauthn.create")?;
    let object = bounded_hex(request, "attestation_object_hex", 16_384)?;
    let (value, consumed) = cbor_value(&object)?;
    if consumed != object.len() {
        return Err("Trailing native attestation data.".into());
    }
    let map = map_unique(&value)?;
    if map.len() != 3 || map.iter().any(|(key,_)| !matches!(key,Cbor::Text(name) if ["fmt","authData","attStmt"].contains(&name.as_str()))) {
        return Err("Unsupported native attestation object structure.".into());
    }
    let format = map
        .iter()
        .find_map(|(key, value)| (key == &Cbor::Text("fmt".into())).then_some(value));
    if !matches!(format,Some(Cbor::Text(name)) if ["none","packed","fido-u2f"].contains(&name.as_str()))
    {
        return Err("Unsupported native attestation format.".into());
    }
    let statement = map
        .iter()
        .find_map(|(key, value)| (key == &Cbor::Text("attStmt".into())).then_some(value))
        .ok_or("Native attestation statement missing.")?;
    map_unique(statement)?;
    let auth = map
        .iter()
        .find_map(|(key, value)| {
            if key == &Cbor::Text("authData".into()) {
                if let Cbor::Bytes(bytes) = value {
                    Some(bytes.as_slice())
                } else {
                    None
                }
            } else {
                None
            }
        })
        .ok_or("Native registration omitted authenticator data.")?;
    check_auth(auth, true)?;
    if auth.len() < 56 {
        return Err("Truncated native credential data.".into());
    }
    let length = usize::from(u16::from_be_bytes([auth[53], auth[54]]));
    if length == 0 || length > 1024 || auth.len() <= 55 + length {
        return Err("Invalid native credential identifier size.".into());
    }
    let credential = &auth[55..55 + length];
    if credential != bounded_hex(request, "credential_id", 1024)? {
        return Err("Native credential identifier does not match attestation data.".into());
    }
    let tail = &auth[55 + length..];
    let (cose, consumed) = cbor_value(tail)?;
    if consumed > 1024 {
        return Err("Native public key exceeds size limit.".into());
    }
    let map = map_unique(&cose)?;
    if map.len() != 5 {
        return Err("Unsupported native public-key parameters.".into());
    }
    let get = |key: i128| {
        map.iter()
            .find_map(|(candidate, value)| (integer(candidate) == Some(key)).then_some(value))
    };
    if get(1).and_then(integer) != Some(2)
        || get(3).and_then(integer) != Some(-7)
        || get(-1).and_then(integer) != Some(1)
    {
        return Err("Native security key must use ES256/P-256.".into());
    }
    let coordinate = |key| match get(key) {
        Some(Cbor::Bytes(bytes)) if bytes.len() == 32 => Ok(bytes.as_slice()),
        _ => Err("Invalid native public-key coordinate."),
    };
    let point = EncodedPoint::from_affine_coordinates(
        coordinate(-2)?.into(),
        coordinate(-3)?.into(),
        false,
    );
    let public =
        VerifyingKey::from_encoded_point(&point).map_err(|_| "Invalid native P-256 point.")?;
    if auth[32] & 0x80 == 0 {
        if consumed != tail.len() {
            return Err("Unexpected native credential trailing data.".into());
        }
    } else {
        let (extensions, used) = cbor_value(&tail[consumed..])?;
        map_unique(&extensions)?;
        if consumed + used != tail.len() {
            return Err("Trailing native extension data.".into());
        }
    }
    Ok(
        json!({"public_key_hex":hex::encode(public.to_encoded_point(true)),"credential_id_hex":hex::encode(credential),"rp_id":rp}),
    )
}
pub fn verify_assertion(
    public: &str,
    message: &[u8],
    signature: &str,
    auth_hex: &str,
    client_hex: &str,
) -> Result<(), String> {
    if auth_hex.len() != 74 || client_hex.len() > 8192 {
        return Err("Native assertion exceeds size limit.".into());
    }
    let auth = hex::decode(auth_hex).map_err(|_| "Invalid native authenticator data.")?;
    let client = hex::decode(client_hex).map_err(|_| "Invalid native client data encoding.")?;
    check_auth(&auth, false)?;
    check_client(&client, &Sha256::digest(message), "webauthn.get")?;
    let mut signed = auth;
    signed.extend_from_slice(&Sha256::digest(client));
    identity::verify_signature(public, &signed, signature)
}

#[cfg(any(test, all(debug_assertions, target_os = "ios", target_abi = "sim")))]
pub fn registration_fixture(request: &Value) -> Result<Value, String> {
    let public = hex::decode(text(request, "public_key")?).map_err(|_| "Invalid fixture key.")?;
    let public = VerifyingKey::from_sec1_bytes(&public)
        .map_err(|_| "Invalid fixture point.")?
        .to_encoded_point(false);
    let challenge = bounded_hex(request, "challenge_hex", 32)?;
    let credential = bounded_hex(request, "credential_id", 1024)?;
    let n = |value: i64| Cbor::Integer(value.into());
    let cose = Cbor::Map(vec![
        (n(1), n(2)),
        (n(3), n(-7)),
        (n(-1), n(1)),
        (n(-2), Cbor::Bytes(public.x().ok_or("Missing x.")?.to_vec())),
        (n(-3), Cbor::Bytes(public.y().ok_or("Missing y.")?.to_vec())),
    ]);
    let mut auth = Sha256::digest(configured_rp()?.as_bytes()).to_vec();
    auth.extend_from_slice(&[0x45, 0, 0, 0, 1]);
    auth.extend_from_slice(&[0; 16]);
    auth.extend_from_slice(&(credential.len() as u16).to_be_bytes());
    auth.extend(&credential);
    ciborium::ser::into_writer(&cose, &mut auth).map_err(|_| "Cannot encode fixture key.")?;
    let object = Cbor::Map(vec![
        (Cbor::Text("fmt".into()), Cbor::Text("none".into())),
        (Cbor::Text("authData".into()), Cbor::Bytes(auth)),
        (Cbor::Text("attStmt".into()), Cbor::Map(vec![])),
    ]);
    let mut encoded = Vec::new();
    ciborium::ser::into_writer(&object, &mut encoded).map_err(|_| "Cannot encode fixture.")?;
    let client = json!({"type":"webauthn.create","challenge":URL_SAFE_NO_PAD.encode(challenge),"origin":format!("https://{}",configured_rp()?),"crossOrigin":false});
    Ok(
        json!({"attestation_object_hex":hex::encode(encoded),"client_data_json_hex":hex::encode(serde_json::to_vec(&client).map_err(|_|"Cannot encode fixture client data.")?)}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use p256::ecdsa::{Signature, SigningKey, signature::Signer};
    fn client(challenge: &[u8], kind: &str, origin: &str) -> Vec<u8> {
        serde_json::to_vec(&json!({"type":kind,"challenge":URL_SAFE_NO_PAD.encode(challenge),"origin":origin,"crossOrigin":false})).unwrap()
    }
    fn assertion(
        key: &SigningKey,
        message: &[u8],
        flags: u8,
        origin: &str,
        kind: &str,
    ) -> (String, String, String) {
        let data = client(&Sha256::digest(message), kind, origin);
        let mut auth = Sha256::digest(rp_id().unwrap().as_bytes()).to_vec();
        auth.extend_from_slice(&[flags, 0, 0, 0, 1]);
        let mut signed = auth.clone();
        signed.extend_from_slice(&Sha256::digest(&data));
        let signature: Signature = key.sign(&signed);
        (
            hex::encode(signature.to_bytes()),
            hex::encode(auth),
            hex::encode(data),
        )
    }
    #[test]
    fn native_assertion_checks_origin_challenge_type_flags_and_signed_client_hash() {
        let key = SigningKey::from_slice(&[21; 32]).unwrap();
        let public = hex::encode(key.verifying_key().to_encoded_point(true));
        let message = b"a specific Vow action";
        let origin = format!("https://{}", rp_id().unwrap());
        for (flags, source, kind, valid) in [
            (5, origin.as_str(), "webauthn.get", true),
            (1, origin.as_str(), "webauthn.get", false),
            (13, origin.as_str(), "webauthn.get", false),
            (5, "https://other.invalid", "webauthn.get", false),
            (5, origin.as_str(), "webauthn.create", false),
        ] {
            let (signature, auth, data) = assertion(&key, message, flags, source, kind);
            assert_eq!(
                verify_assertion(&public, message, &signature, &auth, &data).is_ok(),
                valid
            );
            if valid {
                assert!(
                    verify_assertion(&public, b"different action", &signature, &auth, &data)
                        .is_err()
                );
            }
        }
        let duplicate = format!(
            "{{\"type\":\"webauthn.get\",\"origin\":\"https://other.invalid\",\"origin\":\"{origin}\",\"challenge\":\"{}\"}}",
            URL_SAFE_NO_PAD.encode(Sha256::digest(message))
        );
        assert!(
            check_client(
                duplicate.as_bytes(),
                &Sha256::digest(message),
                "webauthn.get"
            )
            .is_err()
        );
    }
    #[test]
    fn native_registration_parses_bounded_cose_and_binds_callback_credential() {
        let key = SigningKey::from_slice(&[22; 32]).unwrap();
        let public = hex::encode(key.verifying_key().to_encoded_point(true));
        let challenge = registration_challenge(&json!({"device_public_key":public})).unwrap();
        let fixture=registration_fixture(&json!({"public_key":public,"challenge_hex":challenge["challenge_hex"],"credential_id":"aabbccdd"})).unwrap();
        let mut request = json!({"challenge_hex":challenge["challenge_hex"],"credential_id":"aabbccdd","client_data_json_hex":fixture["client_data_json_hex"],"attestation_object_hex":fixture["attestation_object_hex"]});
        let parsed = parse_registration(&request).unwrap();
        assert_eq!(parsed["public_key_hex"], public);
        assert_eq!(parsed["rp_id"], rp_id().unwrap());
        request["credential_id"] = json!("ccdd");
        assert!(parse_registration(&request).is_err());
        request["credential_id"] = json!("aabbccdd");
        request["attestation_object_hex"] = json!("a1");
        assert!(parse_registration(&request).is_err());
        request["attestation_object_hex"] = json!("81".repeat(100) + "00");
        assert!(parse_registration(&request).is_err());
        request["attestation_object_hex"] = json!(
            fixture["attestation_object_hex"]
                .as_str()
                .unwrap()
                .to_string()
                + "00"
        );
        assert!(parse_registration(&request).is_err());
    }
    #[test]
    fn native_enrollment_v3_restores_and_binds_both_keys() {
        let device = SigningKey::from_slice(&[23; 32]).unwrap();
        let security = SigningKey::from_slice(&[24; 32]).unwrap();
        let prepared=identity::prepare(&json!({"device_public_key":hex::encode(device.verifying_key().to_encoded_point(true)),"security_key_public_key":hex::encode(security.verifying_key().to_encoded_point(true)),"key_source":"secure_enclave","security_key_kind":"webauthn","credential_id":"aabbcc"})).unwrap();
        let message = hex::decode(prepared["message_hex"].as_str().unwrap()).unwrap();
        let ds: Signature = device.sign(&message);
        let (signature, auth, data) = assertion(
            &security,
            &message,
            5,
            &format!("https://{}", rp_id().unwrap()),
            "webauthn.get",
        );
        let mut proof = json!({"message_hex":prepared["message_hex"],"device_signature":hex::encode(ds.to_bytes()),"security_key_signature":signature,"security_key_authenticator_data":auth,"security_key_client_data_json":data});
        let result = identity::verify(&proof).unwrap();
        let package: Value = serde_json::from_str(result["package"].as_str().unwrap()).unwrap();
        assert_eq!(package["format"], "vow.device-enrollment.v3");
        assert_eq!(
            identity::verify(&package).unwrap()["package"],
            result["package"]
        );
        proof
            .as_object_mut()
            .unwrap()
            .remove("security_key_client_data_json");
        assert!(identity::verify(&proof).is_err());
    }
    #[test]
    fn relying_party_rejects_urls_invalid_labels_and_uppercase() {
        for value in [
            "",
            "https://vow.example.com",
            "Vow.example.com",
            "-vow.example",
            "vow..example",
        ] {
            assert!(!valid_domain(value));
        }
        assert!(valid_domain("vow.example.com"));
    }
    fn sign_parts(key: &SigningKey, auth: &[u8], data: &[u8]) -> String {
        let mut bytes = auth.to_vec();
        bytes.extend(Sha256::digest(data));
        let signature: Signature = key.sign(&bytes);
        hex::encode(signature.to_bytes())
    }

    #[test]
    fn every_single_bit_change_in_a_valid_native_proof_is_rejected() {
        let key = SigningKey::from_slice(&[31; 32]).unwrap();
        let public = hex::encode(key.verifying_key().to_encoded_point(true));
        let message = b"specific request, consent and session";
        let (signature, auth, data) = assertion(
            &key,
            message,
            5,
            &format!("https://{}", rp_id().unwrap()),
            "webauthn.get",
        );
        let original = [
            message.to_vec(),
            hex::decode(&signature).unwrap(),
            hex::decode(&auth).unwrap(),
            hex::decode(&data).unwrap(),
        ];
        for component in 0..original.len() {
            for position in 0..original[component].len() {
                for bit in 0..8 {
                    let mut changed = original.clone();
                    changed[component][position] ^= 1 << bit;
                    assert!(
                        verify_assertion(
                            &public,
                            &changed[0],
                            &hex::encode(&changed[1]),
                            &hex::encode(&changed[2]),
                            &hex::encode(&changed[3])
                        )
                        .is_err(),
                        "accepted mutation of component {component}, byte {position}, bit {bit}"
                    );
                }
            }
        }
    }

    #[test]
    fn correctly_signed_assertions_still_require_exact_flags_and_client_semantics() {
        let key = SigningKey::from_slice(&[32; 32]).unwrap();
        let public = hex::encode(key.verifying_key().to_encoded_point(true));
        let message = b"Vow approval";
        let origin = format!("https://{}", rp_id().unwrap());
        let (_, auth_hex, data_hex) = assertion(&key, message, 5, &origin, "webauthn.get");
        let auth = hex::decode(auth_hex).unwrap();
        let data = hex::decode(data_hex).unwrap();
        for flags in 0..=255u8 {
            let mut changed = auth.clone();
            changed[32] = flags;
            let signature = sign_parts(&key, &changed, &data);
            assert_eq!(
                verify_assertion(
                    &public,
                    message,
                    &signature,
                    &hex::encode(changed),
                    &hex::encode(&data)
                )
                .is_ok(),
                flags == 5
            );
        }
        let value: Value = serde_json::from_slice(&data).unwrap();
        for (field, wrong) in [
            ("crossOrigin", json!(true)),
            ("type", json!("webauthn.create")),
            ("origin", json!(format!("{origin}/"))),
            ("origin", json!(format!("{origin}:443"))),
            ("origin", json!(origin.replace("https:", "http:"))),
            ("challenge", json!(URL_SAFE_NO_PAD.encode([0u8; 32]))),
            ("challenge", json!(123)),
            ("crossOrigin", json!("false")),
            ("unexpected", json!(true)),
        ] {
            let mut changed = value.clone();
            changed[field] = wrong;
            let data = serde_json::to_vec(&changed).unwrap();
            let signature = sign_parts(&key, &auth, &data);
            assert!(
                verify_assertion(
                    &public,
                    message,
                    &signature,
                    &hex::encode(&auth),
                    &hex::encode(data)
                )
                .is_err(),
                "accepted invalid {field}"
            );
        }
        // Equivalent JSON is valid only when the authenticator signed those exact bytes.
        let pretty = serde_json::to_vec_pretty(&value).unwrap();
        assert!(
            verify_assertion(
                &public,
                message,
                &sign_parts(&key, &auth, &pretty),
                &hex::encode(&auth),
                &hex::encode(pretty)
            )
            .is_ok()
        );
    }

    #[test]
    fn malformed_signature_key_and_proof_lengths_fail_closed() {
        let key = SigningKey::from_slice(&[33; 32]).unwrap();
        let public = hex::encode(key.verifying_key().to_encoded_point(true));
        let (signature, auth, data) = assertion(
            &key,
            b"request",
            5,
            &format!("https://{}", rp_id().unwrap()),
            "webauthn.get",
        );
        for invalid in [
            String::new(),
            "00".repeat(64),
            "ff".repeat(64),
            signature[..126].into(),
            signature.clone() + "00",
            "zz".repeat(64),
        ] {
            assert!(verify_assertion(&public, b"request", &invalid, &auth, &data).is_err());
        }
        for invalid in [
            String::new(),
            "00".repeat(33),
            "02".into(),
            public.to_uppercase(),
            hex::encode(key.verifying_key().to_encoded_point(false)),
        ] {
            assert!(verify_assertion(&invalid, b"request", &signature, &auth, &data).is_err());
        }
        for invalid in [
            String::new(),
            auth[..72].into(),
            auth.clone() + "00",
            "zz".repeat(37),
        ] {
            assert!(verify_assertion(&public, b"request", &signature, &invalid, &data).is_err());
        }
        for invalid in [String::new(), "00".repeat(4097), "zz".into(), "f".into()] {
            assert!(verify_assertion(&public, b"request", &signature, &auth, &invalid).is_err());
        }
    }

    #[test]
    fn registration_rejects_reserved_flags_and_every_truncated_attestation() {
        let key = SigningKey::from_slice(&[34; 32]).unwrap();
        let public = hex::encode(key.verifying_key().to_encoded_point(true));
        let challenge = registration_challenge(&json!({"device_public_key":public})).unwrap();
        let fixture = registration_fixture(&json!({"public_key":public,"challenge_hex":challenge["challenge_hex"],"credential_id":"aabbcc"})).unwrap();
        let bytes = hex::decode(fixture["attestation_object_hex"].as_str().unwrap()).unwrap();
        let mut request = json!({"challenge_hex":challenge["challenge_hex"],"credential_id":"aabbcc","client_data_json_hex":fixture["client_data_json_hex"],"attestation_object_hex":fixture["attestation_object_hex"]});
        for length in 0..bytes.len() {
            request["attestation_object_hex"] = json!(hex::encode(&bytes[..length]));
            assert!(
                parse_registration(&request).is_err(),
                "accepted truncation at {length}"
            );
        }
        let mut auth = Sha256::digest(rp_id().unwrap().as_bytes()).to_vec();
        auth.extend([0, 0, 0, 0, 0]);
        for flags in 0..=255u8 {
            auth[32] = flags;
            assert_eq!(
                check_auth(&auth, true).is_ok(),
                flags == 0x45 || flags == 0xc5
            );
        }
    }

    #[test]
    fn native_enrollment_rejects_tampering_of_either_proof_and_every_bound_field() {
        let device = SigningKey::from_slice(&[35; 32]).unwrap();
        let security = SigningKey::from_slice(&[36; 32]).unwrap();
        let request = json!({"device_public_key":hex::encode(device.verifying_key().to_encoded_point(true)),"security_key_public_key":hex::encode(security.verifying_key().to_encoded_point(true)),"key_source":"secure_enclave","security_key_kind":"webauthn","credential_id":"aabbcc"});
        let prepared = identity::prepare(&request).unwrap();
        let message = hex::decode(prepared["message_hex"].as_str().unwrap()).unwrap();
        let ds: Signature = device.sign(&message);
        let (signature, auth, data) = assertion(
            &security,
            &message,
            5,
            &format!("https://{}", rp_id().unwrap()),
            "webauthn.get",
        );
        let proof = json!({"message_hex":prepared["message_hex"],"device_signature":hex::encode(ds.to_bytes()),"security_key_signature":signature,"security_key_authenticator_data":auth,"security_key_client_data_json":data});
        assert!(identity::verify(&proof).is_ok());
        for field in [
            "device_signature",
            "security_key_signature",
            "security_key_authenticator_data",
            "security_key_client_data_json",
        ] {
            let mut changed = proof.clone();
            changed.as_object_mut().unwrap().remove(field);
            assert!(identity::verify(&changed).is_err());
            let mut changed = proof.clone();
            let mut bytes = hex::decode(changed[field].as_str().unwrap()).unwrap();
            bytes[0] ^= 1;
            changed[field] = json!(hex::encode(bytes));
            assert!(identity::verify(&changed).is_err());
        }
        let original: Value = serde_json::from_slice(&message).unwrap();
        for (field, value) in [
            ("nonce", json!("00".repeat(32))),
            ("rp_id", json!("other.example")),
            ("credential_id", json!("dd")),
            ("key_source", json!("simulator_software")),
            ("security_key_kind", json!("piv")),
            ("pin_policy", json!("never")),
            ("touch_policy", json!("never")),
            ("purpose", json!("approve")),
            (
                "device_public_key",
                request["security_key_public_key"].clone(),
            ),
            (
                "security_key_public_key",
                request["device_public_key"].clone(),
            ),
        ] {
            let mut changed = original.clone();
            changed[field] = value;
            let mut candidate = proof.clone();
            candidate["message_hex"] = json!(hex::encode(crate::canonical_bytes(&changed)));
            assert!(
                identity::verify(&candidate).is_err(),
                "accepted changed {field}"
            );
        }
        assert_ne!(
            identity::prepare(&request).unwrap()["message_hex"],
            prepared["message_hex"]
        );
    }
}
