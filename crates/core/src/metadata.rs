//! Canonical Program Metadata IDL decoding. RPC-reported state is not a chain proof.
use crate::{Chain, digest};
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use solana_pubkey::Pubkey;
use std::{io::Read, str::FromStr};
pub const METADATA_PROGRAM: &str = "ProgM6JCCvbYkfKqJYHePx4xxSUSqJp7rh8Lyv7nk7S";
const MAX_IDL: usize = 1024 * 1024;
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IdlArtifact {
    pub program: String,
    pub metadata_address: String,
    pub owner: String,
    pub account_data_base64: String,
    pub chain: String,
    pub genesis_hash: String,
    pub context_slot: u64,
    pub idl_json: String,
    pub idl_sha256: String,
}
pub fn locator(program: &str, chain: Chain) -> Result<Value, String> {
    let program_key = Pubkey::from_str(program).map_err(|_| "Enter a valid program address.")?;
    let owner = Pubkey::from_str(METADATA_PROGRAM).map_err(|_| "Invalid metadata program.")?;
    let mut seed = [0u8; 16];
    seed[..3].copy_from_slice(b"idl");
    let (address, _) = Pubkey::find_program_address(&[program_key.as_ref(), &seed], &owner);
    Ok(
        json!({"program":program,"metadata_address":address.to_string(),"owner":METADATA_PROGRAM,"chain":chain.snapshot()}),
    )
}
pub fn decode_idl(
    program: &str,
    address: &str,
    owner: &str,
    encoded: &str,
    chain: Chain,
    genesis_hash: &str,
    slot: u64,
) -> Result<IdlArtifact, String> {
    if genesis_hash != chain.genesis_hash() {
        return Err("The RPC genesis hash does not match the project network.".into());
    }
    let loc = locator(program, chain)?;
    if loc["metadata_address"] != address
        || owner != METADATA_PROGRAM
        || encoded.len() > 2 * MAX_IDL
    {
        return Err(
            "Metadata address, owner or size does not match the canonical IDL account.".into(),
        );
    }
    let data = base64::prelude::BASE64_STANDARD
        .decode(encoded)
        .map_err(|_| "Invalid metadata account encoding.")?;
    let program_key = Pubkey::from_str(program).map_err(|_| "Invalid program address.")?;
    let mut seed = [0u8; 16];
    seed[..3].copy_from_slice(b"idl");
    if data.len() < 96
        || data[0] != 2
        || data[1..33] != program_key.to_bytes()
        || data[66] != 1
        || data[67..83] != seed
        || data[83] != 1
        || data[85] != 1
        || data[86] != 0
    {
        return Err("This canonical IDL must contain direct UTF-8 JSON data. URL/external metadata is not enabled.".into());
    }
    let len = u32::from_le_bytes(
        data[87..91]
            .try_into()
            .map_err(|_| "Invalid metadata length.")?,
    ) as usize;
    if len > MAX_IDL || len > data.len() - 96 {
        return Err("Metadata payload length is invalid.".into());
    }
    let content = &data[96..96 + len];
    let mut decompressed = Vec::new();
    match data[84] {
        0 => decompressed.extend_from_slice(content),
        1 => {
            flate2::read::GzDecoder::new(content)
                .take((MAX_IDL + 1) as u64)
                .read_to_end(&mut decompressed)
                .map_err(|_| "Invalid compressed IDL.")?;
        }
        2 => {
            flate2::read::ZlibDecoder::new(content)
                .take((MAX_IDL + 1) as u64)
                .read_to_end(&mut decompressed)
                .map_err(|_| "Invalid compressed IDL.")?;
        }
        _ => return Err("Unsupported IDL compression.".into()),
    }
    if decompressed.len() > MAX_IDL {
        return Err("The decompressed IDL exceeds 1 MB.".into());
    }
    let idl: Value = serde_json::from_slice(&decompressed)
        .map_err(|_| "Metadata does not contain a supported JSON IDL.")?;
    let declared = idl
        .get("address")
        .and_then(Value::as_str)
        .or_else(|| idl["program"]["publicKey"].as_str())
        .or_else(|| idl["metadata"]["address"].as_str())
        .ok_or("The IDL has no declared program identity.")?;
    if declared != program {
        return Err("The IDL declares another program address.".into());
    }
    Ok(IdlArtifact {
        program: program.into(),
        metadata_address: address.into(),
        owner: owner.into(),
        account_data_base64: encoded.into(),
        chain: chain.wallet_id().into(),
        genesis_hash: genesis_hash.into(),
        context_slot: slot,
        idl_json: String::from_utf8(decompressed.clone()).map_err(|_| "Invalid IDL text.")?,
        idl_sha256: digest(&decompressed),
    })
}
impl IdlArtifact {
    pub fn validate(&self, chain: Chain) -> Result<(), String> {
        if self.chain != chain.wallet_id() {
            return Err("An IDL targets a different network.".into());
        }
        let decoded = decode_idl(
            &self.program,
            &self.metadata_address,
            &self.owner,
            &self.account_data_base64,
            chain,
            &self.genesis_hash,
            self.context_slot,
        )?;
        if decoded.idl_json != self.idl_json || decoded.idl_sha256 != self.idl_sha256 {
            return Err("The IDL does not match the bundled metadata account.".into());
        }
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn canonical_idl_binds_program_chain_and_content() {
        let program = "CHNLxYvVA28MJP9PrFuDXccuoGXAx7jBacfLEkahyGsX";
        let loc = locator(program, Chain::Devnet).unwrap();
        let mut bytes = vec![0; 96];
        bytes[0] = 2;
        bytes[1..33].copy_from_slice(Pubkey::from_str(program).unwrap().as_ref());
        bytes[66] = 1;
        bytes[67..70].copy_from_slice(b"idl");
        bytes[83] = 1;
        bytes[85] = 1;
        let json = json!({"kind":"rootNode","program":{"publicKey":program}}).to_string();
        bytes[87..91].copy_from_slice(&(json.len() as u32).to_le_bytes());
        bytes.extend_from_slice(json.as_bytes());
        let encoded = base64::prelude::BASE64_STANDARD.encode(bytes);
        let artifact = decode_idl(
            program,
            loc["metadata_address"].as_str().unwrap(),
            METADATA_PROGRAM,
            &encoded,
            Chain::Devnet,
            Chain::Devnet.genesis_hash(),
            1,
        )
        .unwrap();
        artifact.validate(Chain::Devnet).unwrap();
        assert!(artifact.validate(Chain::Mainnet).is_err());
        let mut altered = artifact;
        altered.idl_json = "{}".into();
        assert!(altered.validate(Chain::Devnet).is_err());
    }
}
