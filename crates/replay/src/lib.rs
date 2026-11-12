//! Snapshot replay through the shared offline Surfpool SDK runtime. No remote RPC fallback.
use base64::Engine;
use serde::{Deserialize, Serialize};
use solana_address::Address;
use solana_transaction_replay::versioned::VersionedTransaction;
use std::{collections::BTreeMap, str::FromStr};

pub use vow_runtime::AccountSnapshot;
#[derive(Clone, Serialize, Deserialize, PartialEq, Eq, Debug)]
#[serde(deny_unknown_fields)]
pub struct ReplayResult {
    pub engine: String,
    pub compute_units: u64,
    pub logs: Vec<String>,
    pub balances: BTreeMap<String, u64>,
}
pub fn replay(
    transaction_hex: &str,
    snapshot: &BTreeMap<String, AccountSnapshot>,
    addresses: &[String],
) -> Result<ReplayResult, String> {
    if transaction_hex.len() > 2464 || snapshot.len() > 128 || addresses.len() > 32 {
        return Err("Replay input exceeds this build’s resource limits.".into());
    }
    let bytes = hex::decode(transaction_hex).map_err(|_| "Invalid transaction bytes.")?;
    let tx: VersionedTransaction =
        wincode::deserialize(&bytes).map_err(|_| "Unsupported replay transaction.")?;
    // Legacy rehearsal approvals retain their stricter program-loading policy.
    // Generic review can inspect bundled programs but cannot become an approval.
    if snapshot.values().any(|account| account.executable) {
        return Err(
            "Downloaded executable programs are not enabled in this approval profile.".into(),
        );
    }
    let _ = tx; // Deserialize before starting an SDK worker.
    let output = vow_runtime::execute(
        transaction_hex,
        snapshot
            .iter()
            .map(|(key, value)| (key.clone(), Some(value.clone())))
            .collect(),
        addresses.to_vec(),
        None,
    )?;
    if !output.result["err"].is_null() {
        return Err(format!(
            "Offline simulation failed: {}",
            output.result["err"]
        ));
    }
    Ok(ReplayResult {
        engine: "Surfpool SDK 1.7.0 · offline / signature and blockhash checks disabled".into(),
        compute_units: output.result["unitsConsumed"]
            .as_u64()
            .ok_or("Missing compute usage.")?,
        logs: serde_json::from_value(output.result["logs"].clone())
            .map_err(|_| "Invalid runtime logs.")?,
        balances: output.balances,
    })
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReproductionBundle {
    pub format: String,
    pub engine: String,
    pub runtime_fingerprint: String,
    pub target_chain: String,
    pub source: String,
    pub context_slot: u64,
    pub signature_checks: bool,
    pub blockhash_checks: bool,
    pub snapshot: BTreeMap<String, AccountSnapshot>,
    pub absent_accounts: Vec<String>,
    pub expected: ReplayResult,
    pub profile: serde_json::Value,
    pub wire_digest: String,
}
impl ReproductionBundle {
    pub fn verify(&self, wire: &str, addresses: &[String]) -> Result<ReplayResult, String> {
        use sha2::{Digest, Sha256};
        let bytes = hex::decode(wire).map_err(|_| "Invalid replay bytes.")?;
        if !matches!(
            self.expected.engine.as_str(),
            "LiteSVM 0.18.1 · offline / signature and blockhash checks disabled"
                | "Surfpool SDK 1.7.0 · offline / signature and blockhash checks disabled"
        ) || self.format != "vow.prototype.reproduction.v1"
            || !matches!(
                self.runtime_fingerprint.as_str(),
                "litesvm-0.18.1-agave-4.3.2" | "surfpool-sdk-1.7.0-agave-4.3.2"
            )
            || self.source != "synthetic_fixture"
            || self.signature_checks
            || self.blockhash_checks
            || self.wire_digest != hex::encode(Sha256::digest(&bytes))
            || self.snapshot.len() > 128
            || self.absent_accounts.len() > 32
        {
            return Err("Unsupported or mismatched reproduction context.".into());
        }
        for address in addresses {
            if !self.snapshot.contains_key(address) && !self.absent_accounts.contains(address) {
                return Err("A required account is missing from the replay fixtures.".into());
            }
        }
        if self
            .absent_accounts
            .iter()
            .any(|key| self.snapshot.contains_key(key))
        {
            return Err("An account is declared both present and absent.".into());
        }
        if serde_json::to_vec(&self.profile)
            .map_err(|_| "Cannot read profile.")?
            .len()
            > 2 * 1024 * 1024
        {
            return Err("The recorded profile is too large.".into());
        }
        let result = replay(wire, &self.snapshot, addresses)?;
        // Engine display labels changed when the legacy adapter moved to the SDK.
        // Compare the execution outputs; all older evidence remains untrusted input.
        if result.compute_units != self.expected.compute_units
            || result.logs != self.expected.logs
            || result.balances != self.expected.balances
        {
            return Err(
                "Offline replay differs from the recorded result. Approval is blocked.".into(),
            );
        }
        Ok(result)
    }
}

/// Simulation evidence is untrusted RPC-derived review context, never signing authority.
/// Validate its byte/network binding before displaying or retaining any of it.
pub fn validate_simulation(
    value: &serde_json::Value,
    wire: &str,
    chain: &str,
    genesis: &str,
) -> Result<(), String> {
    use serde_json::Value;
    use sha2::{Digest, Sha256};
    let bytes = hex::decode(wire).map_err(|_| "Invalid simulation transaction.")?;
    let encoded = serde_json::to_vec(value).map_err(|_| "Invalid simulation evidence.")?;
    if encoded.len() > 6 * 1024 * 1024
        || value["format"] != "vow.simulation.v1"
        || value["chain"] != chain
        || value["genesis_hash"] != genesis
        || value["wire_digest"] != hex::encode(Sha256::digest(&bytes))
        || !matches!(
            value["state_source"].as_str(),
            Some("rpc_snapshot_non_atomic" | "synthetic_fixture")
        )
        || value["signature_checks"] != false
        || value["blockhash_checks"] != false
        || !value["result"].is_object()
        || value["result"].get("err").is_none()
        || !value["snapshot"].is_object()
        || value["rpc_slot_start"].as_u64().is_none()
        || value["rpc_slot_end"].as_u64().is_none()
        || value["rpc_slot_end"].as_u64() < value["rpc_slot_start"].as_u64()
        || value["snapshot"]
            .as_object()
            .map_or(usize::MAX, |v| v.len())
            > 1024
    {
        return Err("Mismatched, malformed or oversized simulation evidence.".into());
    }
    for (address, account) in value["snapshot"].as_object().ok_or("Missing snapshot.")? {
        Address::from_str(address).map_err(|_| "Invalid fixture address.")?;
        if account == &Value::Null {
            continue;
        }
        let account: AccountSnapshot =
            serde_json::from_value(account.clone()).map_err(|_| "Invalid account fixture.")?;
        Address::from_str(&account.owner).map_err(|_| "Invalid fixture owner.")?;
        base64::prelude::BASE64_STANDARD
            .decode(&account.data)
            .map_err(|_| "Invalid fixture bytes.")?;
    }
    Ok(())
}

#[cfg(test)]
mod simulation_evidence_tests {
    use super::*;
    use serde_json::json;
    use sha2::{Digest, Sha256};
    #[test]
    fn generic_evidence_is_bound_to_wire_and_network_without_authorizing_execution() {
        let valid = json!({"format":"vow.simulation.v1","chain":"solana:devnet","genesis_hash":"devnet-genesis",
            "wire_digest":hex::encode(Sha256::digest([0u8])),"state_source":"rpc_snapshot_non_atomic",
            "signature_checks":false,"blockhash_checks":false,"rpc_slot_start":10,"rpc_slot_end":12,
            "result":{"err":null,"logs":[],"unitsConsumed":10},"snapshot":{}});
        validate_simulation(&valid, "00", "solana:devnet", "devnet-genesis").unwrap();
        assert!(validate_simulation(&valid, "01", "solana:devnet", "devnet-genesis").is_err());
        assert!(validate_simulation(&valid, "00", "solana:mainnet", "devnet-genesis").is_err());
        assert!(validate_simulation(&valid, "00", "solana:devnet", "wrong-genesis").is_err());
        for (field, bad) in [
            ("signature_checks", json!(true)),
            ("blockhash_checks", json!(true)),
            ("rpc_slot_end", json!(9)),
            ("snapshot", json!([])),
            ("result", json!({})),
        ] {
            let mut tampered = valid.clone();
            tampered[field] = bad;
            assert!(
                validate_simulation(&tampered, "00", "solana:devnet", "devnet-genesis").is_err()
            );
        }
        let mut failed = valid.clone();
        failed["result"]["err"] = json!({"InstructionError":[0,"Custom"]});
        validate_simulation(&failed, "00", "solana:devnet", "devnet-genesis").unwrap();
    }
}
