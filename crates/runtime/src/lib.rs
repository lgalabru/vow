//! One Surfpool SDK backend for both Apple platforms. No caller-supplied RPC endpoint.
pub mod diff;
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use solana_rpc_client_api::request::RpcRequest;
use std::{collections::BTreeMap, str::FromStr};
use surfpool_sdk::{Pubkey, Surfnet, cheatcodes::builders::SetAccount};

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AccountSnapshot {
    pub lamports: u64,
    pub owner: String,
    pub executable: bool,
    #[serde(alias = "rentEpoch")]
    pub rent_epoch: u64,
    pub data: String,
}
pub struct Execution {
    pub result: Value,
    pub profile: Value,
    pub balances: BTreeMap<String, u64>,
    pub account_states: Value,
}

/// Execute only in an ephemeral, offline fork. Original bytes are never rewritten.
/// The SDK's own slot cache owns managed sysvars; other fixtures are loaded exactly.
pub fn execute(
    wire: &str,
    snapshot: BTreeMap<String, Option<AccountSnapshot>>,
    addresses: Vec<String>,
    clock: Option<(u64, u64)>,
) -> Result<Execution, String> {
    if wire.len() > 2464 || snapshot.len() > 1024 || addresses.len() > 256 {
        return Err("Simulation exceeds this build's resource limits.".into());
    }
    let mut total = 0usize;
    let mut accounts = Vec::with_capacity(snapshot.len());
    for (address, value) in snapshot {
        let key = Pubkey::from_str(&address).map_err(|_| "Invalid fixture address.")?;
        let Some(account) = value else { continue };
        total = total
            .checked_add(account.data.len())
            .ok_or("Snapshot is too large.")?;
        if total > 6 * 1024 * 1024 {
            return Err("Snapshot is too large.".into());
        }
        let owner = Pubkey::from_str(&account.owner).map_err(|_| "Invalid fixture owner.")?;
        let data = base64::prelude::BASE64_STANDARD
            .decode(&account.data)
            .map_err(|_| "Invalid fixture bytes.")?;
        accounts.push((key, owner, data, account));
    }
    for address in &addresses {
        Pubkey::from_str(address).map_err(|_| "Invalid result address.")?;
    }
    accounts.sort_by_key(|(_, _, _, account)| account.executable);
    let encoded = base64::prelude::BASE64_STANDARD
        .encode(hex::decode(wire).map_err(|_| "Invalid wire bytes.")?);
    // Callers include synchronous core validation from inside another SDK runtime.
    // Owning this runtime on its own thread avoids nested-runtime panics and ensures shutdown.
    std::thread::Builder::new().name("vow-surfpool-offline".into()).spawn(move || {
        let runtime = tokio::runtime::Builder::new_multi_thread().enable_all().worker_threads(2).build().map_err(|_| "Cannot start the local simulation runtime.")?;
        runtime.block_on(async move {
            let mut surfnet = Surfnet::builder().offline(true).airdrop_sol(0).skip_blockhash_check(true).start().await.map_err(|e|format!("Cannot start offline Surfpool: {e}"))?;
            let rpc = surfnet.rpc_client();
            if let Some((slot,timestamp)) = clock {
                let current = rpc.get_epoch_info().map_err(|_| "Cannot read the SDK startup clock.")?;
                if slot < current.absolute_slot { return Err(format!("Snapshot slot {slot} precedes the SDK startup slot {}.",current.absolute_slot)); }
                let _:Value=rpc.send(RpcRequest::Custom{method:"surfnet_timeTravel"},json!([{"absoluteSlotAt":{"slot":slot,"timestamp":timestamp}}])).map_err(|e|format!("Cannot restore snapshot clock at slot {slot}, from slot {}: {e}",current.absolute_slot))?;
            }
            for (key, owner, data, account) in accounts {
                if account.owner == "NativeLoader1111111111111111111111111111111" || managed_sysvar(&key.to_string()) { continue; }
                surfnet.cheatcodes().execute(SetAccount::new(key).owner(owner).lamports(account.lamports).data(data).rent_epoch(account.rent_epoch).executable(account.executable))
                    .map_err(|e|format!("Cannot restore account {key}: {e}"))?;
            }
            let simulated:Value = rpc.send(RpcRequest::SimulateTransaction,json!([encoded,{"encoding":"base64","sigVerify":false,"replaceRecentBlockhash":false,"innerInstructions":true,"accounts":{"encoding":"base64","addresses":addresses}}])).map_err(|e|format!("Offline simulation could not run: {e}"))?;
            let result=simulated.get("value").ok_or("Surfpool returned no simulation result.")?.clone();
            let mut profile=Value::Null;
            let mut parsed_profile=Value::Null;
            if result["err"].is_null() {
                let signature:String=rpc.send(RpcRequest::SendTransaction,json!([encoded,{"encoding":"base64","skipPreflight":true,"skipSigVerify":true}])).map_err(|e|format!("Local execution failed: {e}"))?;
                profile=rpc.send(RpcRequest::Custom{method:"surfnet_getTransactionProfile"},json!([signature,{"encoding":"base64","depth":"instruction"}])).map_err(|e|format!("Cannot read execution profile: {e}"))?;
                parsed_profile=rpc.send(RpcRequest::Custom{method:"surfnet_getTransactionProfile"},json!([signature,{"encoding":"jsonParsed","depth":"instruction"}])).map_err(|e|format!("Cannot read parsed execution state: {e}"))?;
            }
            let mut balances=BTreeMap::new();
            for address in addresses {
                let key=Pubkey::from_str(&address).map_err(|_|"Invalid output address.")?;
                balances.insert(address,rpc.get_balance(&key).map_err(|_|"Cannot read local output balance.")?);
            }
            surfnet.stop().map_err(|_|"The local simulator did not stop cleanly.")?;
            Ok(Execution{account_states:diff::report(&profile,&parsed_profile),result,profile,balances})
        })
    }).map_err(|_| "Cannot start the simulation worker.")?.join().map_err(|_| "Local simulation failed. No approval was produced.")?
}
fn managed_sysvar(address: &str) -> bool {
    matches!(
        address,
        "SysvarC1ock11111111111111111111111111111111"
            | "SysvarS1otHashes111111111111111111111111111"
            | "SysvarRecentB1ockHashes11111111111111111111"
            | "SysvarEpochSchedu1e111111111111111111111111"
            | "SysvarLastRestartS1ot1111111111111111111111"
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn malformed_and_oversized_inputs_are_rejected_before_starting_a_fork() {
        assert!(execute(&"00".repeat(1233), BTreeMap::new(), vec![], None).is_err());
        assert!(execute("zz", BTreeMap::new(), vec![], None).is_err());
        let mut accounts = BTreeMap::new();
        accounts.insert("invalid".into(), None);
        assert!(execute("00", accounts, vec![], None).is_err());
        assert!(execute("00", BTreeMap::new(), vec!["invalid".into()], None).is_err());
        let key = "11111111111111111111111111111111";
        let mut accounts = BTreeMap::new();
        accounts.insert(
            key.into(),
            Some(AccountSnapshot {
                lamports: 1,
                owner: key.into(),
                executable: false,
                rent_epoch: 0,
                data: "x".repeat(6 * 1024 * 1024 + 1),
            }),
        );
        assert!(execute("00", accounts, vec![], None).is_err());
    }
}
