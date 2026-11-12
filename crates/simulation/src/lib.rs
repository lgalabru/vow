//! Connected preparation and snapshot-only simulation through the Surfpool SDK.
use serde_json::Value;
#[cfg(target_os = "macos")]
use serde_json::json;
pub mod clipboard;
mod offline;

pub fn profile(request: &Value) -> Result<Value, String> {
    if request["mode"] == "offline" {
        return offline::profile(request);
    }
    #[cfg(target_os = "macos")]
    {
        if request["mode"] == "clipboard" {
            clipboard::profile(request)
        } else {
            mac::profile(request)
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = request;
        Err(
            "Connected preparation is available on Mac. Use bundled account fixtures for offline simulation on this device."
                .into(),
        )
    }
}
#[cfg(target_os = "macos")]
mod mac {
    use super::*;
    use base64::Engine;
    use solana_rpc_client_api::request::RpcRequest;
    use std::{collections::BTreeMap, str::FromStr};
    use surfpool_sdk::{Pubkey, Surfnet};
    use vow_core::transaction::{TransactionIntent, decode};

    pub fn profile(request: &Value) -> Result<Value, String> {
        let intent: TransactionIntent = serde_json::from_value(request["intent"].clone())
            .map_err(|_| "Invalid profiling request.")?;
        let decoded = decode(&intent)?;
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(2)
            .build()
            .map_err(|_| "Cannot start the local simulation runtime.")?;
        runtime.block_on(async move {
            let source=Pubkey::from_str(&decoded.source).map_err(|_|"Invalid source account.")?;
            let mut surfnet=Surfnet::builder().offline(true).skip_blockhash_check(true)
                .airdrop_addresses(vec![source]).airdrop_sol(10_000_000_000).start().await.map_err(|e|format!("Cannot start Surfpool: {e}"))?;
            let rpc=surfnet.rpc_client();
            let encoded=base64::prelude::BASE64_STANDARD.encode(hex::decode(&intent.transaction_hex).map_err(|_|"Invalid wire bytes.")?);
            // Execute only in this isolated, synthetic fork. The unsigned dapp input
            // cannot pass profileTransaction's explicit signature verification.
            let signature:String=rpc.send(RpcRequest::Custom {method:"sendTransaction"},json!([encoded,{"encoding":"base64","skipPreflight":true,"skipSigVerify":true}]))
                .map_err(|e|format!("Surfpool local execution failed: {e}"))?;
            let profile:Value=rpc.send(RpcRequest::Custom {method:"surfnet_getTransactionProfile"},json!([signature,{"encoding":"base64","depth":"instruction"}]))
                .map_err(|e|format!("Surfpool profiling failed: {e}"))?;
            let exported:Value=rpc.send(RpcRequest::Custom {method:"surfnet_exportSnapshot"},json!([{"includeParsedAccounts":false,"scope":{"preTransaction":signature},"filter":{"includeProgramAccounts":true}}]))
                .map_err(|e|format!("Surfpool snapshot export failed: {e}"))?;
            let snapshot=exported.get("value").and_then(Value::as_object).ok_or("Surfpool returned no pre-state snapshot.")?;
            let mut accounts=BTreeMap::new();
            for address in [&decoded.source,&decoded.recipient] {
                if let Some(value)=snapshot.get(address) {
                    let mut value=value.clone(); if let Some(obj)=value.as_object_mut(){obj.remove("parsed_data");obj.remove("parsedData");}
                    let account:vow_replay::AccountSnapshot=serde_json::from_value(value).map_err(|_|"Unsupported snapshot account schema.")?;
                    accounts.insert(address.clone(),account);
                }
            }
            if !accounts.contains_key(&decoded.source) { return Err("The pre-state snapshot is missing the source account.".into()); }
            let addresses=vec![decoded.source.clone(),decoded.recipient.clone()];
            let replay=vow_replay::replay(&intent.transaction_hex,&accounts,&addresses)?;
            for address in &addresses {
                let key=Pubkey::from_str(address).map_err(|_|"Invalid output account.")?;
                let balance=rpc.get_balance(&key).map_err(|e|format!("Cannot fetch local result: {e}"))?;
                if replay.balances.get(address) != Some(&balance) { return Err("Independent offline replay does not match Surfpool’s post-state.".into()); }
            }
            let slot=rpc.get_slot().map_err(|e|format!("Cannot fetch the local slot: {e}"))?;
            surfnet.stop().map_err(|e|format!("Surfpool did not shut down cleanly: {e}"))?;
            Ok(json!({"format":"vow.prototype.reproduction.v1","engine":"surfpool-sdk 1.7.0","runtime_fingerprint":"surfpool-sdk-1.7.0-agave-4.3.2",
                "target_chain":intent.chain,"source":"synthetic_fixture","context_slot":slot,
                "signature_checks":false,"blockhash_checks":false,"snapshot":accounts,
                "absent_accounts":addresses.iter().filter(|a|!accounts.contains_key(*a)).collect::<Vec<_>>(),"expected":replay,"profile":profile,"wire_digest":decoded.wire_digest}))
        })
    }
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;
    #[test]
    fn sdk_profile_exports_prestate_and_matches_offline_replay() {
        let mut session = vow_core::Session::default();
        let fixture = session
            .dispatch(&json!({"action":"browser_fixture"}))
            .unwrap();
        let intent = json!({"transaction_hex":fixture["transaction_hex"],"source_origin":"vow-demo://playground","chain":fixture["chain"],"require_security_key":false,"require_app_attest":false});
        let result = profile(&json!({"intent":intent})).unwrap();
        assert_eq!(result["source"], "synthetic_fixture");
        assert_eq!(result["signature_checks"], false);
        let bundle: vow_replay::ReproductionBundle = serde_json::from_value(result).unwrap();
        let source = fixture["account"].as_str().unwrap().to_owned();
        let parsed: vow_core::transaction::TransactionIntent =
            serde_json::from_value(intent.clone()).unwrap();
        let decoded = vow_core::transaction::decode(&parsed).unwrap();
        bundle
            .verify(
                fixture["transaction_hex"].as_str().unwrap(),
                &[source.clone(), decoded.recipient.clone()],
            )
            .unwrap();
        let addresses = [source, decoded.recipient];
        let mut altered = bundle.clone();
        altered.expected.compute_units += 1;
        assert!(altered.verify(&parsed.transaction_hex, &addresses).is_err());
        let mut altered = bundle.clone();
        altered.snapshot.remove(&addresses[0]);
        assert!(altered.verify(&parsed.transaction_hex, &addresses).is_err());
        let mut altered = bundle.clone();
        altered.wire_digest = "00".repeat(32);
        assert!(altered.verify(&parsed.transaction_hex, &addresses).is_err());
        let captured=session.dispatch(&json!({"action":"capture_transaction","transaction_hex":fixture["transaction_hex"],"source_origin":"vow-demo://playground","chain":fixture["chain"]})).unwrap();
        let file=session.dispatch(&json!({"action":"prepare_transaction_file","id":captured["id"],"require_security_key":false,"require_app_attest":false,"reproduction":bundle})).unwrap();
        let mut ipad = vow_core::Session::default();
        ipad.dispatch(&json!({"action":"import","data":file["package"]}))
            .unwrap();
        let replay = ipad
            .dispatch(&json!({"action":"replay_transaction"}))
            .unwrap();
        assert!(replay["compute_units"].as_u64().unwrap() > 0);
        let review = ipad
            .dispatch(&json!({"action":"inspect_current_proposal"}))
            .unwrap();
        assert_eq!(review["simulation"]["state_source"], "synthetic_fixture");
        let local =
            profile(&json!({"mode":"offline","chain":"solana:devnet","package":review["package"]}))
                .unwrap();
        assert!(local["result"]["err"].is_null());
        assert_eq!(local["execution_ready"], false);
    }
}
