//! Generic wire simulation for clipboard review. No signing or public submission.
use serde_json::Value;
#[cfg(any(target_os = "macos", test))]
use serde_json::json;
use vow_core::{Chain, inspection};

pub fn inspect_request(request: &Value) -> Result<(Chain, Value), String> {
    let chain = match request["chain"].as_str() {
        Some("solana:devnet") => Chain::Devnet,
        Some("solana:mainnet") => Chain::Mainnet,
        _ => return Err("Choose Devnet or Mainnet before reading the clipboard.".into()),
    };
    let inspected = inspection::inspect(request, chain)?;
    Ok((chain, inspected))
}

#[cfg(target_os = "macos")]
pub fn profile(request: &Value) -> Result<Value, String> {
    let (chain, _) = inspect_request(request)?;
    profile_at(request, chain.rpc_url(), chain.genesis_hash())
}

#[cfg(target_os = "macos")]
fn profile_at(request: &Value, endpoint: &str, expected_genesis: &str) -> Result<Value, String> {
    use solana_rpc_client_api::request::RpcRequest;
    use std::time::{Duration, SystemTime, UNIX_EPOCH};
    use surfpool_sdk::{RpcClient, Surfnet};
    let (chain, inspected) = inspect_request(request)?;
    let wire = inspected["transaction_hex"]
        .as_str()
        .ok_or("Missing transaction bytes.")?;
    let tx =
        inspection::transaction(&hex::decode(wire).map_err(|_| "Invalid transaction bytes.")?)?;
    let remote = RpcClient::new_with_timeout(endpoint.to_string(), Duration::from_secs(30));
    let genesis = remote
        .get_genesis_hash()
        .map_err(|e| format!("Cannot verify RPC network: {e}"))?
        .to_string();
    if genesis != expected_genesis {
        return Err("RPC genesis does not match the selected network.".into());
    }
    let start_slot = remote
        .get_slot()
        .map_err(|e| format!("Cannot read the RPC slot: {e}"))?;
    let wall_clock_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "Check the Mac clock.")?
        .as_millis() as u64;
    let (clock_ms, clock_source) = match remote
        .get_block_time(start_slot)
        .ok()
        .and_then(|n| u64::try_from(n).ok())
        .and_then(|n| n.checked_mul(1000))
    {
        Some(time) => (time, "rpc_block_time"),
        None => (wall_clock_ms, "mac_wall_clock"),
    };
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .worker_threads(2)
        .build()
        .map_err(|_| "Cannot start Surfnet.")?;
    runtime.block_on(async move {
        let mut surfnet = Surfnet::builder().remote_rpc_url(endpoint).skip_blockhash_check(true)
            .start().await.map_err(|e|format!("Cannot start Surfnet: {e}"))?;
        let rpc = surfnet.rpc_client();
        let local_slot:u64=rpc.send(RpcRequest::GetSlot,json!([{"commitment":"processed"}]))
            .map_err(|e|format!("Cannot read local fork slot: {e}"))?;
        let fork_slot=start_slot.max(local_slot);
        let _:Value=rpc.send(RpcRequest::Custom{method:"surfnet_timeTravel"},
            json!([{"absoluteSlotAt":{"slot":fork_slot,"timestamp":clock_ms}}]))
            .map_err(|e|format!("Cannot establish the local fork clock: {e}"))?;
        let package: Value = serde_json::from_str(inspected["package"].as_str().ok_or("Missing review container.")?)
            .map_err(|_|"Invalid review container.")?;
        let encoded = package["transaction_base64"].as_str().ok_or("Missing encoded transaction.")?;
        let addresses = tx.message.static_account_keys().iter().map(ToString::to_string).collect::<Vec<_>>();
        // This endpoint belongs to the embedded fork. Never send to the remote RPC.
        let simulated: Value = rpc.send(RpcRequest::SimulateTransaction,
            json!([encoded,{"encoding":"base64","sigVerify":false,"replaceRecentBlockhash":false,
                "innerInstructions":true,"accounts":{"encoding":"base64","addresses":addresses}}]))
            .map_err(|e|format!("Surfnet simulation could not run: {e}"))?;
        let result = simulated.get("value").ok_or("Surfnet returned no simulation result.")?;
        // simulateTransaction does not commit account changes. Capture that exact
        // cached pre-state before a follow-up execution advances the fork clock.
        let snapshot:Value=rpc.send(RpcRequest::Custom{method:"surfnet_exportSnapshot"},
            json!([{"scope":"network","includeParsedAccounts":false,"filter":{"includeProgramAccounts":true}}]))
            .map_err(|e|format!("Cannot export Surfnet state fixtures: {e}"))?;
        let mut profile = Value::Null;
        if result["err"].is_null() {
            let signature: String = rpc.send(RpcRequest::SendTransaction,
                json!([encoded,{"encoding":"base64","skipPreflight":true,"skipSigVerify":true}]))
                .map_err(|e|format!("Local fork execution failed: {e}"))?;
            profile = rpc.send(RpcRequest::Custom{method:"surfnet_getTransactionProfile"},
                json!([signature,{"encoding":"base64","depth":"instruction"}]))
                .map_err(|e|format!("Cannot export execution profile: {e}"))?;
        }
        let mut accounts = snapshot.get("value").ok_or("Surfnet returned no snapshot.")?.clone();
        if let Some(accounts)=accounts.as_object_mut() {
            for account in accounts.values_mut() {
                if let Some(account)=account.as_object_mut() { account.remove("parsed_data"); account.remove("parsedData"); }
            }
        }
        let end_slot = remote.get_slot().map_err(|e|format!("Cannot record final RPC slot: {e}"))?;
        let observed = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_|"Check the Mac clock.")?.as_millis() as u64;
        let evidence = json!({"format":"vow.simulation.v1","chain":chain.wallet_id(),"genesis_hash":chain.genesis_hash(),
            "wire_digest":inspected["id"],"observed_at_unix_ms":observed,"rpc_slot_start":start_slot,"rpc_slot_end":end_slot,
            "engine":"surfpool-sdk 1.7.0","state_source":"rpc_snapshot_non_atomic",
            "fork_slot":fork_slot,"clock_unix_ms":clock_ms,"clock_source":clock_source,
            "profile_context":"followup_local_execution",
            "signature_checks":false,"blockhash_checks":false,"result":result,"profile":profile,"snapshot":accounts});
        let wire = inspected["transaction_hex"].as_str().ok_or("Missing transaction.")?;
        vow_replay::validate_simulation(&evidence,wire,chain.wallet_id(),chain.genesis_hash())?;
        let mut package = package;
        package["source_origin"] = json!("vow://clipboard");
        package["simulation"] = evidence.clone();
        let text = serde_json::to_string_pretty(&package).map_err(|_|"Cannot encode review file.")?;
        if text.len() > 8*1024*1024 { return Err("This transaction's fixtures exceed the 8 MB review-file limit. No partial bundle was exported.".into()); }
        surfnet.stop().map_err(|e|format!("Surfnet could not stop cleanly: {e}"))?;
        Ok(json!({"filename":format!("Vow-{}.vow",&inspected["id"].as_str().ok_or("Missing digest.")?[..12]),
            "package":text,"wire_digest":inspected["id"],"network_explicit":inspected["network_explicit"],
            "chain":chain.snapshot(),"instruction_count":inspected["instructions"].as_array().map(Vec::len),
            "simulation":evidence,"execution_ready":false}))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(target_os = "macos")]
    #[test]
    fn rpc_envelopes_are_accepted_but_batches_are_never_silently_truncated() {
        use base64::Engine;
        let encoded =
            base64::prelude::BASE64_STANDARD.encode(vow_core::transaction::fixture_transaction());
        for data in [
            json!([encoded, "base64"]),
            json!({"result":{"transaction":[encoded,"base64"]}}),
        ] {
            inspect_request(&json!({"chain":"solana:devnet","data":data.to_string()})).unwrap();
        }
        for data in [
            json!([encoded, encoded]),
            json!([encoded, "base64", encoded]),
        ] {
            assert!(
                inspect_request(&json!({"chain":"solana:devnet","data":data.to_string()})).is_err()
            );
        }
    }
    #[test]
    fn generic_profile_exports_multiple_instructions_and_never_submits_to_source_rpc() {
        use surfpool_sdk::{Pubkey, Surfnet};
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(2)
            .build()
            .unwrap();
        let payer = Pubkey::new_from_array([9; 32]);
        let mut source = runtime.block_on(async {
            Surfnet::builder()
                .offline(true)
                .airdrop_addresses(vec![payer])
                .airdrop_sol(10_000_000_000)
                .start()
                .await
                .unwrap()
        });
        let rpc = source.rpc_client();
        // SDK startup airdrops advance a fresh fork a few slots. Record fixtures
        // beyond that startup floor so exact clock restoration never rewinds.
        let _: Value = rpc
            .send(
                solana_rpc_client_api::request::RpcRequest::Custom {
                    method: "surfnet_timeTravel",
                },
                json!([{"absoluteSlotAt":{"slot":1000,"timestamp":1_790_000_000_000u64}}]),
            )
            .unwrap();
        // Advance commitment roots after the warp; getSlot on the source RPC
        // intentionally uses the same finalized view as a real connected source.
        for _ in 0..40 {
            source
                .send_command(surfpool_sdk::SimnetCommand::SlotForward(None))
                .unwrap();
        }
        for _ in 0..100 {
            if rpc.get_slot().unwrap() >= 1000 {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        assert!(rpc.get_slot().unwrap() >= 1000);
        let genesis = rpc.get_genesis_hash().unwrap().to_string();
        let before = rpc.get_balance(&payer).unwrap();
        let mut wire = vow_core::transaction::fixture_transaction();
        wire[1] = 17; // Existing signature bytes are preserved and not verified in simulation.
        // Mix two programs: Compute Budget plus System Program. No transfer-only
        // decoder or hardcoded preview account participates in this path.
        let compute: Pubkey = "ComputeBudget111111111111111111111111111111"
            .parse()
            .unwrap();
        wire[67] = 2;
        wire[68] = 4;
        wire.splice(165..165, compute.to_bytes());
        wire[229] = 2;
        let mut budget = vec![3, 0, 5, 2];
        budget.extend(200_000u32.to_le_bytes());
        wire.splice(230..230, budget);
        let original = wire.clone();
        let request = json!({"chain":"solana:devnet","data":hex::encode(wire)});
        let result = profile_at(&request, source.rpc_url(), &genesis).unwrap();
        assert_eq!(rpc.get_balance(&payer).unwrap(), before);
        assert_eq!(result["instruction_count"], 2);
        assert!(result["simulation"]["result"]["err"].is_null());
        assert!(result["simulation"]["snapshot"].is_object());
        assert_eq!(
            result["simulation"]["snapshot"][payer.to_string()]["lamports"],
            before
        );
        assert_eq!(
            hex::decode(
                inspect_request(&json!({"chain":"solana:devnet","data":result["package"]}))
                    .unwrap()
                    .1["transaction_hex"]
                    .as_str()
                    .unwrap()
            )
            .unwrap(),
            original
        );
        let offline = crate::profile(
            &json!({"mode":"offline","chain":"solana:devnet","package":result["package"]}),
        )
        .unwrap();
        let normalized = vow_core::inspection::inspect(
            &json!({"data":result["package"]}),
            vow_core::Chain::Devnet,
        )
        .unwrap();
        assert_eq!(
            offline["review_context_digest"],
            normalized["review_context_digest"]
        );
        let mut changed_context: Value =
            serde_json::from_str(result["package"].as_str().unwrap()).unwrap();
        changed_context["simulation"]["observed_at_unix_ms"] = json!(1);
        let changed_context = vow_core::inspection::inspect(
            &json!({"data":changed_context.to_string()}),
            vow_core::Chain::Devnet,
        )
        .unwrap();
        assert_eq!(normalized["id"], changed_context["id"]);
        assert_ne!(
            normalized["review_context_digest"],
            changed_context["review_context_digest"]
        );
        assert_eq!(offline["source"], "local_snapshot_execution");
        assert_eq!(offline["offline"], true);
        assert!(offline["result"]["err"].is_null());
        assert!(offline["result"]["unitsConsumed"].as_u64().unwrap() > 0);
        assert_eq!(
            offline["profile"]["value"]["instructionProfiles"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        assert_eq!(offline["execution_ready"], false);
        let package: Value = serde_json::from_str(result["package"].as_str().unwrap()).unwrap();
        for (key, value) in [
            ("chain", json!("solana:mainnet")),
            ("wire_digest", json!("00".repeat(32))),
            ("genesis_hash", json!("wrong")),
        ] {
            let mut altered = package.clone();
            altered["simulation"][key] = value;
            assert!(
                crate::profile(
                    &json!({"mode":"offline","chain":"solana:devnet","package":altered.to_string()})
                )
                .is_err()
            );
        }
        assert_eq!(rpc.get_balance(&payer).unwrap(), before);
        let mut failing = original.clone();
        let end = failing.len();
        failing[end - 8..].copy_from_slice(&20_000_000_000u64.to_le_bytes());
        let failed = profile_at(
            &json!({"chain":"solana:devnet","data":hex::encode(failing)}),
            source.rpc_url(),
            &genesis,
        )
        .unwrap();
        assert!(!failed["simulation"]["result"]["err"].is_null());
        assert_eq!(rpc.get_balance(&payer).unwrap(), before);
        assert!(profile_at(&request, source.rpc_url(), "wrong-network").is_err());
        let mut ipad = vow_core::Session::default();
        ipad.dispatch(&json!({"action":"reset_all"})).unwrap();
        let inspected = ipad
            .dispatch(&json!({"action":"inspect_transaction_dump","data":result["package"]}))
            .unwrap();
        assert_eq!(inspected["signed"], true);
        assert_eq!(inspected["execution_ready"], false);
        assert_eq!(inspected["simulation"]["wire_digest"], inspected["id"]);
        source.stop().unwrap();
    }
    #[test]
    fn arbitrary_signed_v0_multi_instruction_messages_keep_all_original_bytes() {
        let mut wire = vow_core::transaction::fixture_transaction();
        wire[1] = 17;
        wire[133..165].fill(8); // An unknown program, not the transfer preview.
        let instruction = wire[198..].to_vec();
        wire[197] = 2;
        wire.extend(instruction);
        wire.insert(65, 0x80); // Version 0 prefix.
        wire.push(1);
        wire.extend([5; 32]);
        wire.extend([1, 0, 1, 1]);
        let encoded = hex::encode(wire);
        let (_, inspected) =
            inspect_request(&json!({"chain":"solana:devnet","data":encoded})).unwrap();
        assert_eq!(inspected["transaction_hex"], encoded);
        assert_eq!(inspected["signed"], true);
        assert_eq!(inspected["unresolved_lookups"], true);
        assert_eq!(inspected["instructions"].as_array().unwrap().len(), 2);
        assert_eq!(inspected["execution_ready"], false);
    }
    #[test]
    fn clipboard_accepts_arbitrary_programs_signatures_and_lookup_tables_without_authorizing_them()
    {
        let wire =
            inspection::channel_fixture(Chain::Devnet, None, 123).unwrap()["transaction_hex"]
                .as_str()
                .unwrap()
                .to_owned();
        let (_, result) = inspect_request(&json!({"chain":"solana:devnet","data":wire})).unwrap();
        assert!(!result["instructions"].as_array().unwrap().is_empty());
        assert_eq!(result["execution_ready"], false);
        assert!(inspect_request(&json!({"chain":"solana:mainnet","data":json!({"chain":"solana:devnet","transaction_hex":wire}).to_string()})).is_err());
        assert!(inspect_request(&json!({"data":wire})).is_err());
    }
}
