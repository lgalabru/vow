//! Bounded, read-only Squads RPC access. Endpoint selection always comes from Chain.
use base64::Engine;
use serde_json::{Value, json};
use solana_rpc_client_api::request::RpcRequest;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use surfpool_sdk::RpcClient;
use vow_core::{Chain, squads};

pub fn request(input: &Value) -> Result<Value, String> {
    let chain = match input["chain"].as_str() {
        Some("solana:devnet") => Chain::Devnet,
        Some("solana:mainnet") => Chain::Mainnet,
        _ => return Err("Choose Devnet or Mainnet.".into()),
    };
    let address = input["address"]
        .as_str()
        .ok_or("Enter a multisig address.")?;
    squads::key(address)?;
    let rpc = RpcClient::new_with_timeout(chain.rpc_url().to_string(), Duration::from_secs(10));
    let genesis = rpc
        .get_genesis_hash()
        .map_err(|e| format!("Cannot verify the selected network: {e}"))?
        .to_string();
    if genesis != chain.genesis_hash() {
        return Err("RPC genesis does not match the selected network.".into());
    }
    let root = account(&rpc, address)?;
    let (owner, data) = decode_account(&root["value"])?;
    let resolved = squads::resolve_multisig(address, &owner, &data)?;
    let root = if resolved == address {
        root
    } else {
        account(&rpc, &resolved)?
    };
    let (owner, data) = decode_account(&root["value"])?;
    let multisig = squads::decode_multisig(&resolved, &owner, &data)?;
    match input["operation"].as_str() {
        Some("resolve") => {
            Ok(json!({"multisig":multisig,"chain":chain.snapshot(),"slot":root["context"]["slot"]}))
        }
        Some("fetch") => fetch(
            &rpc,
            input,
            multisig,
            root["context"]["slot"]
                .as_u64()
                .ok_or("Missing RPC slot.")?,
        ),
        Some("prepare_approval") => prepare(
            &rpc,
            input,
            chain,
            multisig,
            root["context"]["slot"]
                .as_u64()
                .ok_or("Missing RPC slot.")?,
        ),
        _ => Err("Unsupported multisig observation operation.".into()),
    }
}
fn account(rpc: &RpcClient, address: &str) -> Result<Value, String> {
    rpc.send(
        RpcRequest::GetAccountInfo,
        json!([address,{"encoding":"base64","commitment":"confirmed"}]),
    )
    .map_err(|e| format!("Cannot read the Squads account: {e}"))
}
fn decode_account(value: &Value) -> Result<(String, Vec<u8>), String> {
    if value.is_null() {
        return Err("No Squads account at this address on the selected network.".into());
    }
    let owner = value["owner"].as_str().ok_or("Account owner is missing.")?;
    squads::require_owner(owner)?;
    let encoded = value["data"][0]
        .as_str()
        .filter(|_| value["data"][1] == "base64")
        .ok_or("Unsupported RPC account encoding.")?;
    if encoded.len() > squads::ACCOUNT_BYTES_MAX.div_ceil(3) * 4 {
        return Err("Squads account exceeds the 64 KB inspection limit.".into());
    }
    let data = base64::prelude::BASE64_STANDARD
        .decode(encoded)
        .map_err(|_| "Invalid RPC account data.")?;
    if data.len() > squads::ACCOUNT_BYTES_MAX {
        return Err("Squads account exceeds the inspection limit.".into());
    }
    Ok((owner.into(), data))
}
fn accounts(rpc: &RpcClient, addresses: &[String], minimum_slot: u64) -> Result<Value, String> {
    if addresses.len() > 64 {
        return Err("Too many proposal accounts requested.".into());
    }
    rpc.send(RpcRequest::GetMultipleAccounts,json!([addresses,{"encoding":"base64","commitment":"confirmed","minContextSlot":minimum_slot}])).map_err(|e|format!("Cannot fetch multisig proposals: {e}"))
}
fn fetch(
    rpc: &RpcClient,
    input: &Value,
    multisig: squads::Multisig,
    minimum_slot: u64,
) -> Result<Value, String> {
    let start = match input.get("before").filter(|v| !v.is_null()) {
        Some(value) => value
            .as_u64()
            .filter(|v| *v > 0)
            .ok_or("Invalid proposal pagination cursor.")?
            .saturating_sub(1)
            .min(multisig.transaction_index),
        None => multisig.transaction_index,
    };
    let count = start.min(squads::PAGE_SIZE);
    let mut addresses = Vec::with_capacity(count as usize * 2);
    for offset in 0..count {
        let index = start - offset;
        addresses.push(squads::transaction_address(&multisig.address, index, true)?);
        addresses.push(squads::transaction_address(
            &multisig.address,
            index,
            false,
        )?);
    }
    let response = if addresses.is_empty() {
        json!({"context":{"slot":minimum_slot},"value":[]})
    } else {
        accounts(rpc, &addresses, minimum_slot)?
    };
    let values = response["value"]
        .as_array()
        .filter(|v| v.len() == addresses.len())
        .ok_or("RPC returned an incomplete proposal batch.")?;
    let mut proposals = Vec::with_capacity(count as usize);
    let mut unavailable = 0u64;
    for offset in 0..count as usize {
        if values[offset * 2].is_null() {
            unavailable += 1;
            continue;
        }
        let (owner, data) = decode_account(&values[offset * 2])?;
        let index = start - offset as u64;
        let proposal =
            squads::decode_proposal(&addresses[offset * 2], &owner, &data, &multisig, index)?;
        let decoded = decode_account(&values[offset * 2 + 1]).and_then(|(owner, data)| {
            squads::decode_transaction(
                &addresses[offset * 2 + 1],
                &owner,
                &data,
                &multisig.address,
                index,
            )
        });
        match decoded {
            Ok(transaction) => proposals
                .push(json!({"proposal":proposal,"transaction":transaction,"detail_error":null})),
            Err(error) => {
                proposals.push(json!({"proposal":proposal,"transaction":null,"detail_error":error}))
            }
        }
    }
    let now = now_unix_ms()?;
    Ok(
        json!({"multisig":multisig,"proposals":proposals,"unavailable":unavailable,"page_start":start,"page_size":squads::PAGE_SIZE,"next_before":(start>count).then_some(start-count+1),"slot":response["context"]["slot"],"observed_at_unix_ms":now}),
    )
}
fn prepare(
    rpc: &RpcClient,
    input: &Value,
    chain: Chain,
    multisig: squads::Multisig,
    minimum_slot: u64,
) -> Result<Value, String> {
    let index = input["index"]
        .as_u64()
        .filter(|i| *i > 0 && *i <= multisig.transaction_index)
        .ok_or("Choose an existing proposal.")?;
    let member = input["member"]
        .as_str()
        .ok_or("Choose the member who will sign.")?;
    let addresses = [
        squads::transaction_address(&multisig.address, index, true)?,
        squads::transaction_address(&multisig.address, index, false)?,
    ];
    let response = accounts(rpc, &addresses, minimum_slot)?;
    let values = response["value"]
        .as_array()
        .filter(|v| v.len() == 2)
        .ok_or("RPC returned an incomplete proposal.")?;
    let (owner, data) = decode_account(&values[0])?;
    let proposal = squads::decode_proposal(&addresses[0], &owner, &data, &multisig, index)?;
    let (owner, data) = decode_account(&values[1])?;
    let details =
        squads::decode_transaction(&addresses[1], &owner, &data, &multisig.address, index)?;
    if !details.lookups.is_empty() {
        return Err(
            "Resolve this proposal's address lookup tables before preparing its approval.".into(),
        );
    }
    let observation = blockhash_context(rpc, chain)?;
    let wire = squads::approval_wire(&multisig, &proposal, member, &observation.blockhash)?;
    let context = json!({"transaction_hex":hex::encode(wire),"chain":chain.wallet_id(),"genesis_hash":chain.genesis_hash(),"blockhash_context":observation});
    let mut captured =
        crate::clipboard::profile(&json!({"chain":chain.wallet_id(),"data":context.to_string()}))?;
    if captured["simulation"]["result"].get("err") != Some(&Value::Null) {
        return Err(format!(
            "Approval simulation failed: {}",
            captured["failure_summary"]
                .as_str()
                .unwrap_or("inspect the current proposal state and retry")
        ));
    }
    // The approval references only its proposal PDA. Include its immutable stored
    // action as additional review context, so offline clients can inspect it too.
    let mut package: Value = serde_json::from_str(
        captured["package"]
            .as_str()
            .ok_or("Missing review package.")?,
    )
    .map_err(|_| "Invalid captured package.")?;
    package["simulation"]["snapshot"][&addresses[1]] =
        serde_json::to_value(snapshot_account(&values[1])?)
            .map_err(|_| "Cannot encode the stored transaction fixture.")?;
    let encoded =
        serde_json::to_string_pretty(&package).map_err(|_| "Cannot encode proposal review.")?;
    if encoded.len() > 8 * 1024 * 1024 {
        return Err("The proposal review exceeds 8 MB.".into());
    }
    // Run the same strict importer before crossing the FFI boundary. RPC-only
    // metadata must never leak into a portable AccountSnapshot.
    vow_core::inspection::inspect(&json!({"data":encoded}), chain)?;
    captured["package"] = json!(encoded);
    Ok(captured)
}

fn blockhash_context(
    rpc: &RpcClient,
    chain: Chain,
) -> Result<vow_core::inspection::BlockhashContext, String> {
    let latest: Value = rpc
        .send(
            RpcRequest::GetLatestBlockhash,
            json!([{"commitment":"confirmed"}]),
        )
        .map_err(|e| format!("Cannot fetch a recent blockhash: {e}"))?;
    let height: u64 = rpc
        .send(
            RpcRequest::GetBlockHeight,
            json!([{"commitment":"confirmed"}]),
        )
        .map_err(|e| format!("Cannot observe the block height: {e}"))?;
    let hash = latest["value"]["blockhash"]
        .as_str()
        .ok_or("RPC blockhash missing.")?;
    let last = latest["value"]["lastValidBlockHeight"]
        .as_u64()
        .ok_or("RPC lifetime missing.")?;
    let remaining = last
        .checked_sub(height)
        .filter(|n| *n > 0 && *n <= 300)
        .ok_or("Blockhash window elapsed; refresh and retry.")?;
    let observed = now_unix_ms()?;
    let expires = observed
        .checked_add((remaining * 400).min(60_000))
        .ok_or("Invalid blockhash lifetime.")?;
    let context = vow_core::inspection::BlockhashContext {
        blockhash: hash.into(),
        chain: chain.wallet_id().into(),
        genesis_hash: chain.genesis_hash().into(),
        observed_at_unix_ms: observed,
        context_slot: latest["context"]["slot"]
            .as_u64()
            .ok_or("RPC context slot missing.")?,
        observed_block_height: height,
        last_valid_block_height: last,
        estimated_expires_at_unix_ms: expires,
    };
    context.validate(hash, chain)?;
    Ok(context)
}

fn snapshot_account(value: &Value) -> Result<vow_replay::AccountSnapshot, String> {
    let (owner, data) = decode_account(value)?;
    Ok(vow_replay::AccountSnapshot {
        lamports: value["lamports"]
            .as_u64()
            .ok_or("Stored transaction balance missing.")?,
        owner,
        executable: value["executable"]
            .as_bool()
            .ok_or("Stored transaction executable flag missing.")?,
        rent_epoch: value["rentEpoch"]
            .as_u64()
            .ok_or("Stored transaction rent epoch missing.")?,
        data: base64::prelude::BASE64_STANDARD.encode(data),
    })
}
fn now_unix_ms() -> Result<u64, String> {
    let elapsed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "Check the Mac clock.")?;
    u64::try_from(elapsed.as_millis()).map_err(|_| "Invalid Mac clock.".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rpc_metadata_is_normalized_before_becoming_a_strict_fixture() {
        let rpc = json!({"lamports":123,"owner":squads::PROGRAM,"executable":false,"rentEpoch":u64::MAX,"space":3,"data":["AQID","base64"]});
        assert!(serde_json::from_value::<vow_replay::AccountSnapshot>(rpc.clone()).is_err());
        let fixture = snapshot_account(&rpc).unwrap();
        let value = serde_json::to_value(&fixture).unwrap();
        assert!(value.get("space").is_none());
        let roundtrip: vow_replay::AccountSnapshot = serde_json::from_value(value).unwrap();
        assert_eq!(roundtrip.rent_epoch, u64::MAX);
        assert_eq!(roundtrip.data, "AQID");
        assert_eq!(roundtrip.lamports, 123);
        let mut malformed = rpc;
        malformed["rentEpoch"] = Value::Null;
        assert!(snapshot_account(&malformed).is_err());
    }
}
