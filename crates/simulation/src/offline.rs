//! Snapshot-only Surfpool execution. No remote endpoint or download path is accepted.
use serde_json::{Value, json};

pub fn profile(request: &Value) -> Result<Value, String> {
    let chain = match request["chain"].as_str() {
        Some("solana:devnet") => vow_core::Chain::Devnet,
        Some("solana:mainnet") => vow_core::Chain::Mainnet,
        _ => return Err("Choose the transaction network.".into()),
    };
    let inspected = vow_core::inspection::inspect(
        &json!({"data":request["package"].as_str().ok_or("Missing review file.")?}),
        chain,
    )?;
    let wire = inspected["transaction_hex"]
        .as_str()
        .ok_or("Missing transaction bytes.")?;
    let evidence = &inspected["simulation"];
    if evidence.is_null() {
        return Err(
            "No account snapshot is included. Prepare this file on a connected Mac first.".into(),
        );
    }
    vow_replay::validate_simulation(evidence, wire, chain.wallet_id(), chain.genesis_hash())?;
    let fixtures = evidence["snapshot"]
        .as_object()
        .ok_or("No account fixtures are included. Prepare this file on a connected Mac first.")?;
    let accounts = serde_json::from_value(evidence["snapshot"].clone())
        .map_err(|_| "Invalid account fixtures.")?;
    let tx =
        vow_core::inspection::transaction(&hex::decode(wire).map_err(|_| "Invalid transaction.")?)?;
    let addresses = tx
        .message
        .static_account_keys()
        .iter()
        .map(ToString::to_string)
        .collect();
    let clock = evidence["fork_slot"]
        .as_u64()
        .zip(evidence["clock_unix_ms"].as_u64());
    if clock.is_none() && evidence["state_source"] != "synthetic_fixture" {
        return Err("Snapshot clock context is missing. Prepare this request again on Mac.".into());
    }
    let output = vow_runtime::execute(wire, accounts, addresses, clock)?;
    Ok(
        json!({"engine":"surfpool-sdk 1.7.0","source":"local_snapshot_execution","wire_digest":inspected["id"],"review_context_digest":inspected["review_context_digest"],"chain":chain.wallet_id(),"offline":true,"signature_checks":false,"blockhash_checks":false,"result":output.result,"profile":output.profile,"fixture_count":fixtures.len(),"account_states":output.account_states,"execution_ready":false}),
    )
}
