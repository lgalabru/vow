//! Read-only Squads v4 account decoding. RPC state is context, never signing authority.
//! Layouts: Squads-Protocol/v4 @ 3a39735d0c56249bf2ce4b16b3229d7be87ad55f.
mod inspection;
mod reader;
mod transaction;
pub use inspection::describe_approval;
use reader::Reader;
use serde::Serialize;
use sha2::{Digest, Sha256};
use solana_pubkey::Pubkey;
use std::str::FromStr;
pub use transaction::{DecodedAction, DecodedTransaction, Field, TransactionKind};

pub const PROGRAM: &str = "SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf";
// Product bounds keep untrusted account parsing, RPC batches and UI work finite.
pub const ACCOUNT_BYTES_MAX: usize = 65_536;
pub const MEMBERS_MAX: usize = 256;
pub const PAGE_SIZE: u64 = 32;

#[derive(Clone, Debug, Serialize)]
pub struct Member {
    pub address: String,
    pub permissions: u8,
    pub direct_signing: bool,
}
#[derive(Clone, Debug, Serialize)]
pub struct Multisig {
    pub address: String,
    pub threshold: u16,
    pub time_lock_seconds: u32,
    pub transaction_index: u64,
    pub stale_transaction_index: u64,
    pub config_authority: Option<String>,
    pub members: Vec<Member>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ProposalStatus {
    Draft,
    Active,
    Rejected,
    Approved,
    Executing,
    Executed,
    Cancelled,
}
#[derive(Clone, Debug, Serialize)]
pub struct Proposal {
    pub address: String,
    pub index: u64,
    pub status: ProposalStatus,
    pub timestamp_unix_seconds: Option<i64>,
    pub approved: Vec<String>,
    pub rejected: Vec<String>,
    pub cancelled: Vec<String>,
    pub stale: bool,
}

pub fn key(address: &str) -> Result<Pubkey, String> {
    Pubkey::from_str(address).map_err(|_| "Enter a valid Solana address.".into())
}
pub fn discriminator(name: &str) -> [u8; 8] {
    Sha256::digest(format!("account:{name}").as_bytes())[..8]
        .try_into()
        .expect("eight-byte discriminator")
}
pub fn transaction_address(multisig: &str, index: u64, proposal: bool) -> Result<String, String> {
    let multisig = key(multisig)?;
    let index = index.to_le_bytes();
    let mut seeds: Vec<&[u8]> = vec![b"multisig", multisig.as_ref(), b"transaction", &index];
    if proposal {
        seeds.push(b"proposal");
    }
    Ok(Pubkey::find_program_address(&seeds, &key(PROGRAM)?)
        .0
        .to_string())
}
pub fn resolve_multisig(address: &str, owner: &str, data: &[u8]) -> Result<String, String> {
    require_owner(owner)?;
    let mut r = Reader::new(data)?;
    let kind = r.take(8)?;
    if kind == discriminator("Multisig") {
        return Ok(decode_multisig(address, owner, data)?.address);
    }
    let multisig = r.key()?;
    let is_proposal = kind == discriminator("Proposal");
    let index = if is_proposal {
        r.u64()?
    } else if kind == discriminator("ConfigTransaction")
        || kind == discriminator("VaultTransaction")
    {
        r.take(32)?;
        r.u64()?
    } else {
        return Err("This address is not a supported Squads v4 account.".into());
    };
    if transaction_address(&multisig, index, is_proposal)? != address {
        return Err("The account does not match its Squads derivation.".into());
    }
    Ok(multisig)
}
pub fn require_owner(owner: &str) -> Result<(), String> {
    if owner != PROGRAM {
        return Err("This account is not owned by Squads v4.".into());
    }
    Ok(())
}
pub fn decode_multisig(address: &str, owner: &str, data: &[u8]) -> Result<Multisig, String> {
    require_owner(owner)?;
    let mut r = Reader::account(data, "Multisig")?;
    let create_key = key(&r.key()?)?;
    let expected = Pubkey::find_program_address(
        &[b"multisig", b"multisig", create_key.as_ref()],
        &key(PROGRAM)?,
    )
    .0;
    if expected.to_string() != address {
        return Err("Invalid Squads multisig derivation.".into());
    }
    let authority = r.key()?;
    let threshold = r.u16()?;
    let time_lock_seconds = r.u32()?;
    let transaction_index = r.u64()?;
    let stale_transaction_index = r.u64()?;
    r.option_key()?;
    r.u8()?;
    let count = r.count(MEMBERS_MAX)?;
    let mut members = Vec::with_capacity(count);
    let mut seen = std::collections::BTreeSet::new();
    for _ in 0..count {
        let address = r.key()?;
        let permissions = r.permissions()?;
        if !seen.insert(address.clone()) {
            return Err("Duplicate Squads member.".into());
        }
        let direct_signing = key(&address)?.is_on_curve();
        members.push(Member {
            address,
            permissions,
            direct_signing,
        });
    }
    if threshold == 0
        || usize::from(threshold) > members.iter().filter(|m| m.permissions & 2 != 0).count()
        || stale_transaction_index > transaction_index
    {
        return Err("Invalid Squads threshold or transaction indices.".into());
    }
    Ok(Multisig {
        address: address.into(),
        threshold,
        time_lock_seconds,
        transaction_index,
        stale_transaction_index,
        config_authority: (authority != Pubkey::default().to_string()).then_some(authority),
        members,
    })
}
pub fn decode_proposal(
    address: &str,
    owner: &str,
    data: &[u8],
    multisig: &Multisig,
    index: u64,
) -> Result<Proposal, String> {
    require_owner(owner)?;
    let mut r = Reader::account(data, "Proposal")?;
    if r.key()? != multisig.address
        || r.u64()? != index
        || transaction_address(&multisig.address, index, true)? != address
    {
        return Err("Proposal address or index does not match the multisig.".into());
    }
    let status = match r.u8()? {
        0 => ProposalStatus::Draft,
        1 => ProposalStatus::Active,
        2 => ProposalStatus::Rejected,
        3 => ProposalStatus::Approved,
        4 => ProposalStatus::Executing,
        5 => ProposalStatus::Executed,
        6 => ProposalStatus::Cancelled,
        _ => return Err("Unsupported Squads proposal status.".into()),
    };
    let timestamp_unix_seconds = if status == ProposalStatus::Executing {
        None
    } else {
        Some(r.i64()?)
    };
    r.u8()?;
    let approved = r.keys(MEMBERS_MAX)?;
    let rejected = r.keys(MEMBERS_MAX)?;
    let cancelled = r.keys(MEMBERS_MAX)?;
    Ok(Proposal {
        address: address.into(),
        index,
        status,
        timestamp_unix_seconds,
        approved,
        rejected,
        cancelled,
        stale: index <= multisig.stale_transaction_index,
    })
}
pub fn decode_transaction(
    address: &str,
    owner: &str,
    data: &[u8],
    multisig: &str,
    index: u64,
) -> Result<DecodedTransaction, String> {
    require_owner(owner)?;
    transaction::decode(address, data, multisig, index)
}

#[cfg(test)]
mod tests;

pub const APPROVE_DISCRIMINATOR: [u8; 8] = [144, 37, 164, 136, 188, 216, 42, 248];
/// Prepare the native Squads vote, never a Vow receipt or signature.
pub fn approval_wire(
    multisig: &Multisig,
    proposal: &Proposal,
    member: &str,
    blockhash: &str,
) -> Result<Vec<u8>, String> {
    let voter = multisig
        .members
        .iter()
        .find(|m| m.address == member && m.permissions & 2 != 0)
        .ok_or("Choose an existing multisig member with voting permission.")?;
    if !key(member)?.is_on_curve() {
        return Err("This off-curve member must approve through its controlling program, not a direct transaction signature.".into());
    }
    if proposal.status != ProposalStatus::Active
        || proposal.stale
        || proposal.index <= multisig.stale_transaction_index
        || proposal.approved.contains(&voter.address)
    {
        return Err(
            "This proposal is not active, is stale, or already has this member's approval.".into(),
        );
    }
    if transaction_address(&multisig.address, proposal.index, true)? != proposal.address {
        return Err("Proposal derivation changed.".into());
    }
    let mut wire = vec![1];
    wire.extend([0; 64]);
    wire.extend([1, 0, 2, 4]);
    for address in [member, &proposal.address, &multisig.address, PROGRAM] {
        wire.extend(key(address)?.to_bytes());
    }
    wire.extend(key(blockhash)?.to_bytes());
    wire.extend([1, 3, 3, 2, 0, 1, 9]);
    wire.extend(APPROVE_DISCRIMINATOR);
    wire.push(0);
    let transaction = crate::inspection::transaction(&wire)?;
    debug_assert_eq!(transaction.signatures.len(), 1);
    debug_assert_eq!(transaction.message.instructions().len(), 1);
    Ok(wire)
}
