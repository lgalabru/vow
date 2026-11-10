//! Offline SVM replay. No RPC client, HTTP fallback, or dynamic program loader.
use base64::Engine;
use litesvm::LiteSVM;
use serde::{Deserialize, Serialize};
use solana_account::Account;
use solana_address::Address;
use solana_transaction_replay::versioned::VersionedTransaction;
use std::{collections::BTreeMap, str::FromStr};

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
    let mut svm = LiteSVM::new()
        .with_sigverify(false)
        .with_blockhash_check(false);
    let mut total = 0usize;
    for (address, entry) in snapshot {
        total = total
            .checked_add(entry.data.len())
            .ok_or("Snapshot is too large.")?;
        if total > 8 * 1024 * 1024 {
            return Err("Snapshot is too large.".into());
        }
        let address = Address::from_str(address).map_err(|_| "Invalid snapshot address.")?;
        let owner = Address::from_str(&entry.owner).map_err(|_| "Invalid snapshot owner.")?;
        let data = base64::prelude::BASE64_STANDARD
            .decode(&entry.data)
            .map_err(|_| "Invalid snapshot data.")?;
        // Executable blobs need an explicit approved program-loading policy before
        // the offline signer may accept them. The initial transfer replay uses builtins.
        if entry.executable {
            return Err(
                "Downloaded executable programs are not enabled in this replay profile.".into(),
            );
        }
        svm.set_account(
            address,
            Account {
                lamports: entry.lamports,
                data,
                owner,
                executable: false,
                rent_epoch: entry.rent_epoch,
            },
        )
        .map_err(|_| "Cannot load replay account.")?;
    }
    let result = svm
        .send_transaction(tx)
        .map_err(|err| format!("Offline replay failed: {:?}", err.err))?;
    let mut balances = BTreeMap::new();
    for address in addresses {
        let key = Address::from_str(address).map_err(|_| "Invalid result account.")?;
        balances.insert(
            address.clone(),
            svm.get_account(&key)
                .map(|account| account.lamports)
                .unwrap_or(0),
        );
    }
    Ok(ReplayResult {
        engine: "LiteSVM 0.18.1 · offline / signature and blockhash checks disabled".into(),
        compute_units: result.compute_units_consumed,
        logs: result.logs,
        balances,
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
        if self.format != "vow.prototype.reproduction.v1"
            || self.runtime_fingerprint != "litesvm-0.18.1-agave-4.3.2"
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
        if result != self.expected {
            return Err(
                "Offline replay differs from the recorded result. Approval is blocked.".into(),
            );
        }
        Ok(result)
    }
}
