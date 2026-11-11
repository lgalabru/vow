//! Bounded Ledger Solana APDU and BLE framing shared with native Apple transport.
use crate::{profiles, text};
use serde_json::{Value, json};
use solana_pubkey::Pubkey;

pub fn commands(r: &Value) -> Result<Value, String> {
    if text(r, "operation")? == "app_info" {
        // BOLOS getAppAndVersion is read-only; it never opens or quits an app.
        return Ok(json!({"commands":["b001000000"]}));
    }
    let path = text(r, "derivation_path")?;
    profiles::validate_path(path)?;
    let parts: Vec<_> = path.split('/').skip(1).collect();
    let mut serialized = vec![parts.len() as u8];
    for part in parts {
        let n = part
            .trim_end_matches('\'')
            .parse::<u32>()
            .map_err(|_| "Invalid path.")?;
        serialized.extend((n | 0x8000_0000).to_be_bytes());
    }
    let operation = text(r, "operation")?;
    let (instruction, payload) = match operation {
        "public_key" => (5, serialized),
        "enrollment" | "identity" | "approval" => {
            let message = text(r, "message")?;
            let body: Value =
                serde_json::from_str(message).map_err(|_| "Invalid enrollment message.")?;
            if body["domain"]
                != if operation == "identity" {
                    "vow.identity.enrollment.v1"
                } else if operation == "enrollment" {
                    "vow.profile.enrollment.v1"
                } else {
                    "vow.profile.approval.v1"
                }
                || body["address"] != text(r, "expected_address")?
                || body["derivation_path"] != path
            {
                return Err("Ledger enrollment context changed.".into());
            }
            let envelope =
                profiles::ledger_envelope(text(r, "expected_address")?, message.as_bytes())?;
            let mut bytes = vec![1];
            bytes.extend(serialized);
            bytes.extend(envelope);
            (7, bytes)
        }
        _ => return Err("Unsupported mobile Ledger operation.".into()),
    };
    let chunks: Vec<_> = payload.chunks(255).collect();
    let commands: Vec<_> = chunks
        .iter()
        .enumerate()
        .map(|(i, chunk)| {
            let p2 = u8::from(i > 0) | if i + 1 < chunks.len() { 2 } else { 0 };
            let mut apdu = vec![0xe0, instruction, 1, p2, chunk.len() as u8];
            apdu.extend_from_slice(chunk);
            hex::encode(apdu)
        })
        .collect();
    Ok(json!({"commands":commands}))
}
pub fn response(r: &Value) -> Result<Value, String> {
    let response = hex::decode(text(r, "response_hex")?).map_err(|_| "Invalid Ledger response.")?;
    if response.len() < 2 || response.len() > 260 {
        return Err("Invalid Ledger response size.".into());
    }
    let (body, status) = response.split_at(response.len() - 2);
    if status != [0x90, 0] {
        let hint = match status {
            [0x69, 0x85] => "Request declined on the Ledger. Review its screen before retrying.",
            [0x69, 0x82] | [0x55, 0x15] => "Unlock your Ledger, open Solana, then retry in Vow.",
            [0x6d, 0x00] | [0x6e, 0x00] => {
                "Open the Solana app on your Ledger. If it is already open, update the Solana app using Ledger Live."
            }
            [0x6a, 0x80] => {
                "Ledger rejected the account path or request data. Check the account details and Solana app version."
            }
            _ => "Check the Ledger screen and its Solana app version before retrying.",
        };
        return Err(format!(
            "{hint} (Ledger status {:02X}{:02X}.)",
            status[0], status[1]
        ));
    }
    match text(r, "operation")? {
        "app_info" => {
            if body.first() != Some(&1) {
                return Err("Ledger returned an unsupported app-information format.".into());
            }
            let name_len = *body.get(1).ok_or("Missing Ledger app name.")? as usize;
            let name_end = 2 + name_len;
            let version_len = *body.get(name_end).ok_or("Missing Ledger app version.")? as usize;
            let name = body.get(2..name_end).ok_or("Truncated Ledger app name.")?;
            let version = body
                .get(name_end + 1..name_end + 1 + version_len)
                .ok_or("Truncated Ledger app version.")?;
            if name.is_empty()
                || name.len() > 64
                || version.is_empty()
                || version.len() > 64
                || !name
                    .iter()
                    .chain(version)
                    .all(|b| (0x20..=0x7e).contains(b))
            {
                return Err("Invalid Ledger app information.".into());
            }
            if name != b"Solana" {
                return Err("Open the Solana app on your Ledger, then retry. Bluetooth is connected; the Solana app is not open.".into());
            }
            Ok(
                json!({"name":"Solana","version":std::str::from_utf8(version).map_err(|_|"Invalid Ledger app version.")?}),
            )
        }
        "continue" if body.is_empty() => Ok(json!({"accepted":true})),
        "public_key" if body.len() == 32 => Ok(
            json!({"address":Pubkey::new_from_array(body.try_into().map_err(|_|"Invalid key.")?).to_string(),"derivation_path":text(r,"derivation_path")?}),
        ),
        "enrollment" | "identity" | "approval" if body.len() == 64 => {
            // Apply the same domain/account/path checks on receive as on send.
            commands(r)?;
            let address = text(r, "expected_address")?;
            let message = text(r, "message")?;
            let envelope = profiles::ledger_envelope(address, message.as_bytes())?;
            profiles::verify_ed25519(address, &envelope, &hex::encode(body))?;
            Ok(json!({"signature_hex":hex::encode(body),"scheme":"ledger_offchain_v0"}))
        }
        _ => Err("Ledger returned an unexpected response type or size.".into()),
    }
}
pub fn frames(r: &Value) -> Result<Value, String> {
    let apdu = hex::decode(text(r, "apdu_hex")?).map_err(|_| "Invalid APDU.")?;
    let mtu = r["mtu"].as_u64().ok_or("Missing BLE frame size.")? as usize;
    if !(20..=512).contains(&mtu) || apdu.is_empty() || apdu.len() > 260 {
        return Err("Invalid BLE frame limits.".into());
    }
    let mut frames = Vec::new();
    let mut offset = 0;
    let mut seq = 0u16;
    while offset < apdu.len() {
        let mut frame = vec![5];
        frame.extend(seq.to_be_bytes());
        if seq == 0 {
            frame.extend((apdu.len() as u16).to_be_bytes());
        }
        let end = (offset + mtu - frame.len()).min(apdu.len());
        frame.extend(&apdu[offset..end]);
        frames.push(hex::encode(frame));
        offset = end;
        seq += 1;
    }
    Ok(json!({"frames":frames}))
}
pub fn decode(r: &Value) -> Result<Value, String> {
    let frames = r["frames"].as_array().ok_or("Missing BLE frames.")?;
    if frames.is_empty() || frames.len() > 64 {
        return Err("Invalid BLE frame count.".into());
    }
    let mut result = Vec::new();
    let mut length = 0;
    for (seq, frame) in frames.iter().enumerate() {
        let hex = frame.as_str().ok_or("Invalid BLE frame.")?;
        if hex.len() > 1024 {
            return Err("BLE frame exceeds size limit.".into());
        }
        let frame = hex::decode(hex).map_err(|_| "Invalid BLE encoding.")?;
        let header = if seq == 0 { 5 } else { 3 };
        if frame.len() <= header
            || frame[0] != 5
            || u16::from_be_bytes([frame[1], frame[2]]) as usize != seq
        {
            return Err("BLE response sequence changed.".into());
        }
        if seq == 0 {
            length = u16::from_be_bytes([frame[3], frame[4]]) as usize;
            if !(2..=260).contains(&length) {
                return Err("Invalid BLE response length.".into());
            }
        }
        if result.len() == length {
            return Err("Unexpected extra BLE response frame.".into());
        }
        result.extend_from_slice(&frame[header..]);
        if result.len() > length {
            return Err("BLE response exceeds declared length.".into());
        }
    }
    Ok(
        json!({"complete":result.len()==length,"response_hex":if result.len()==length{Some(hex::encode(result))}else{None}}),
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn app_probe_requires_solana_and_reports_device_status() {
        assert_eq!(
            commands(&json!({"operation":"app_info"})).unwrap()["commands"][0],
            "b001000000"
        );
        let raw = hex::encode(b"\x01\x06Solana\x051.7.1\x01\x00\x90\x00");
        let request = json!({"operation":"app_info","response_hex":raw});
        assert_eq!(response(&request).unwrap()["version"], "1.7.1");
        for length in 0..14 {
            let mut body = b"\x01\x06Solana\x051.7.1"[..length].to_vec();
            body.extend([0x90, 0]);
            assert!(
                response(&json!({"operation":"app_info","response_hex":hex::encode(body)}))
                    .is_err()
            );
        }
        assert!(response(&json!({"operation":"app_info","response_hex":hex::encode(b"\x01\x05BOLOS\x051.0.0\x90\x00")})).unwrap_err().contains("Open the Solana app"));
        for status in ["5515", "6982", "6985", "6d00", "6e00", "6a80", "6f00"] {
            let error =
                response(&json!({"operation":"public_key","response_hex":status})).unwrap_err();
            assert!(error.contains(&status.to_uppercase()));
        }
    }
    #[test]
    fn apdus_match_remote_wallet_path_and_chunk_conventions() {
        let cmd =
            commands(&json!({"operation":"public_key","derivation_path":"m/44'/501'/0'"})).unwrap();
        assert_eq!(cmd["commands"][0], "e00501000d038000002c800001f580000000");
        assert!(
            commands(&json!({"operation":"transaction","derivation_path":"m/44'/501'/0'"}))
                .is_err()
        );
        let identity_message = json!({"domain":"vow.identity.enrollment.v1","address":"11111111111111111111111111111111","derivation_path":"m/44'/501'/0'"}).to_string();
        let mut identity_request = json!({"operation":"identity","derivation_path":"m/44'/501'/0'","expected_address":"11111111111111111111111111111111","message":identity_message});
        assert!(commands(&identity_request).is_ok());
        identity_request["operation"] = json!("approval");
        assert!(commands(&identity_request).is_err());
        identity_request["operation"] = json!("enrollment");
        assert!(commands(&identity_request).is_err());
    }
    #[test]
    fn ble_roundtrip_rejects_reordered_truncated_oversized_and_trailing_frames() {
        for length in [2, 20, 32, 66, 260] {
            for mtu in [20, 23, 153, 512] {
                let bytes = vec![0xab; length];
                let framed = frames(&json!({"apdu_hex":hex::encode(&bytes),"mtu":mtu})).unwrap();
                let input = json!({"frames":framed["frames"]});
                let result = decode(&input).unwrap();
                assert_eq!(result["complete"], true);
                assert_eq!(result["response_hex"], hex::encode(bytes));
                let mut bad = input.clone();
                bad["frames"]
                    .as_array_mut()
                    .unwrap()
                    .push(json!("05000101"));
                assert!(decode(&bad).is_err());
                let mut bad = input.clone();
                bad["frames"][0] = json!("050000ffff01");
                assert!(decode(&bad).is_err());
                let mut bad = input.clone();
                bad["frames"][0] = json!("050001000201");
                assert!(decode(&bad).is_err());
            }
        }
        assert!(decode(&json!({"frames":["05"]})).is_err());
        assert!(frames(&json!({"apdu_hex":"01","mtu":1})).is_err());
    }
    #[test]
    fn mobile_enrollment_responses_require_exact_signature_bytes_and_status() {
        use ed25519_zebra::{SigningKey, VerificationKeyBytes};
        let key = SigningKey::from([9; 32]);
        let address = Pubkey::new_from_array(VerificationKeyBytes::from(&key).into()).to_string();
        let message=json!({"domain":"vow.profile.enrollment.v1","address":address,"derivation_path":"m/44'/501'/0'","nonce":"a".repeat(64)}).to_string();
        let mut request = json!({"operation":"enrollment","expected_address":address,"derivation_path":"m/44'/501'/0'","message":message});
        let result = commands(&request).unwrap();
        let chunks = result["commands"].as_array().unwrap();
        assert!(chunks.len() > 1);
        let first = hex::decode(chunks[0].as_str().unwrap()).unwrap();
        assert_eq!(&first[..4], &[0xe0, 7, 1, 2]);
        assert_eq!(&first[5..7], &[1, 3]);
        let last = hex::decode(chunks.last().unwrap().as_str().unwrap()).unwrap();
        assert_eq!(last[3], 1);
        let sig = key.sign(&profiles::ledger_envelope(&address, message.as_bytes()).unwrap());
        let mut raw = sig.to_bytes().to_vec();
        raw.extend([0x90, 0]);
        request["response_hex"] = json!(hex::encode(&raw));
        assert!(response(&request).is_ok());
        for index in 0..raw.len() {
            let mut changed = raw.clone();
            changed[index] ^= 1;
            request["response_hex"] = json!(hex::encode(changed));
            assert!(response(&request).is_err(), "byte {index}");
        }
        request["operation"] = json!("approval");
        assert!(commands(&request).is_err());
        assert!(response(&request).is_err());
        assert!(response(&json!({"operation":"continue","response_hex":"9000"})).is_ok());
        assert!(response(&json!({"operation":"continue","response_hex":"009000"})).is_err());
    }
}
