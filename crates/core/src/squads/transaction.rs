use super::{MEMBERS_MAX, discriminator, reader::Reader, transaction_address};
use serde::Serialize;

const ACTIONS_MAX: usize = 32;
const INSTRUCTIONS_MAX: usize = 128;
const KEYS_MAX: usize = 256;
#[derive(Clone, Debug, Serialize)]
pub struct Field {
    pub label: String,
    pub value: String,
}
impl Field {
    fn new(label: &str, value: impl ToString) -> Self {
        Self {
            label: label.into(),
            value: value.to_string(),
        }
    }
}
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TransactionKind {
    Configuration,
    Vault,
}
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionKind {
    AddMember,
    RemoveMember,
    ChangeThreshold,
    SetTimeLock,
    AddSpendingLimit,
    RemoveSpendingLimit,
    SetRentCollector,
}
#[derive(Clone, Debug, Serialize)]
pub struct DecodedAction {
    pub kind: ActionKind,
    pub title: String,
    pub fields: Vec<Field>,
}
#[derive(Clone, Debug, Serialize)]
pub struct InstructionAccount {
    pub address: String,
    pub signer: bool,
    pub writable: bool,
}
#[derive(Clone, Debug, Serialize)]
pub struct VaultInstruction {
    pub index: usize,
    pub program: String,
    pub accounts: Vec<InstructionAccount>,
    pub data_hex: String,
}
#[derive(Clone, Debug, Serialize)]
pub struct Lookup {
    pub address: String,
    pub writable_indexes: Vec<u8>,
    pub readonly_indexes: Vec<u8>,
}
#[derive(Clone, Debug, Serialize)]
pub struct DecodedTransaction {
    pub address: String,
    pub index: u64,
    pub creator: String,
    pub kind: TransactionKind,
    pub title: String,
    pub actions: Vec<DecodedAction>,
    pub instructions: Vec<VaultInstruction>,
    pub lookups: Vec<Lookup>,
    pub vault_index: Option<u8>,
    pub account_keys: Vec<String>,
}
pub(super) fn decode(
    address: &str,
    data: &[u8],
    multisig: &str,
    index: u64,
) -> Result<DecodedTransaction, String> {
    let mut r = Reader::new(data)?;
    let kind = r.take(8)?;
    if r.key()? != multisig {
        return Err("Transaction belongs to another multisig.".into());
    }
    let creator = r.key()?;
    if r.u64()? != index || transaction_address(multisig, index, false)? != address {
        return Err("Transaction address or index does not match the proposal.".into());
    }
    r.u8()?;
    if kind == discriminator("ConfigTransaction") {
        let count = r.count(ACTIONS_MAX)?;
        if count == 0 {
            return Err("Configuration transaction has no actions.".into());
        }
        let actions = (0..count)
            .map(|_| config_action(&mut r))
            .collect::<Result<Vec<_>, _>>()?;
        let title = if actions.len() == 1 {
            actions[0].title.clone()
        } else {
            format!("{} configuration changes", actions.len())
        };
        return Ok(DecodedTransaction {
            address: address.into(),
            index,
            creator,
            kind: TransactionKind::Configuration,
            title,
            actions,
            instructions: vec![],
            lookups: vec![],
            vault_index: None,
            account_keys: vec![],
        });
    }
    if kind != discriminator("VaultTransaction") {
        return Err(
            "This transaction type is not supported by the installed Squads decoder.".into(),
        );
    }
    vault(&mut r, address, index, creator)
}
fn config_action(r: &mut Reader<'_>) -> Result<DecodedAction, String> {
    let (kind, title, fields) = match r.u8()? {
        0 => {
            let member = r.key()?;
            let p = r.permissions()?;
            (
                ActionKind::AddMember,
                "Add member",
                vec![
                    Field::new("Member", member),
                    Field::new("Permissions", permission_names(p)),
                ],
            )
        }
        1 => (
            ActionKind::RemoveMember,
            "Remove member",
            vec![Field::new("Member", r.key()?)],
        ),
        2 => (
            ActionKind::ChangeThreshold,
            "Change approval threshold",
            vec![Field::new("Approvals required", r.u16()?)],
        ),
        3 => (
            ActionKind::SetTimeLock,
            "Change time lock",
            vec![Field::new("Time lock (seconds)", r.u32()?)],
        ),
        4 => {
            let mut fields = vec![
                Field::new("Create key", r.key()?),
                Field::new("Vault index", r.u8()?),
                Field::new("Mint", r.key()?),
                Field::new("Amount (base units)", r.u64()?),
            ];
            let period = match r.u8()? {
                0 => "One time",
                1 => "Daily",
                2 => "Weekly",
                3 => "Monthly",
                _ => return Err("Unsupported spending-limit period.".into()),
            };
            fields.push(Field::new("Period", period));
            fields.push(Field::new("Members", r.keys(MEMBERS_MAX)?.join("\n")));
            let destinations = r.keys(KEYS_MAX)?;
            fields.push(Field::new(
                "Destinations",
                if destinations.is_empty() {
                    "Any destination".into()
                } else {
                    destinations.join("\n")
                },
            ));
            (ActionKind::AddSpendingLimit, "Add spending limit", fields)
        }
        5 => (
            ActionKind::RemoveSpendingLimit,
            "Remove spending limit",
            vec![Field::new("Spending limit", r.key()?)],
        ),
        6 => (
            ActionKind::SetRentCollector,
            "Change rent collector",
            vec![Field::new(
                "Rent collector",
                r.option_key()?.unwrap_or_else(|| "Disabled".into()),
            )],
        ),
        _ => {
            return Err(
                "Unknown Squads configuration action. No partial action summary is shown.".into(),
            );
        }
    };
    Ok(DecodedAction {
        kind,
        title: title.into(),
        fields,
    })
}
fn permission_names(mask: u8) -> String {
    let names = [(1, "Initiate"), (2, "Vote"), (4, "Execute")]
        .into_iter()
        .filter_map(|(flag, name)| (mask & flag != 0).then_some(name))
        .collect::<Vec<_>>()
        .join(", ");
    if names.is_empty() {
        "None".into()
    } else {
        names
    }
}
fn vault(
    r: &mut Reader<'_>,
    address: &str,
    index: u64,
    creator: String,
) -> Result<DecodedTransaction, String> {
    let vault_index = r.u8()?;
    r.u8()?;
    r.vector(KEYS_MAX)?;
    let VaultHeader {
        signers,
        writable_signers,
        writable_non_signers,
        account_keys,
    } = read_vault_header(r)?;
    let raw = read_vault_instructions(r)?;
    let lookups = read_vault_lookups(r)?;
    let writable_dynamic = lookups
        .iter()
        .map(|l| l.writable_indexes.len())
        .sum::<usize>();
    let dynamic = lookups
        .iter()
        .map(|l| l.writable_indexes.len() + l.readonly_indexes.len())
        .sum::<usize>();
    if account_keys.len() + dynamic > KEYS_MAX {
        return Err("Vault message has too many account indices.".into());
    }
    let resolve = |i: usize| -> Result<String, String> {
        if i >= account_keys.len() + dynamic {
            return Err("Invalid vault instruction account index.".into());
        }
        Ok(account_keys
            .get(i)
            .cloned()
            .unwrap_or_else(|| format!("Unresolved lookup address #{i}")))
    };
    let mut instructions = Vec::with_capacity(raw.len());
    for (
        index,
        RawInstruction {
            program,
            indices,
            data,
        },
    ) in raw.into_iter().enumerate()
    {
        let mut accounts = Vec::with_capacity(indices.len());
        for i in indices {
            let i = usize::from(i);
            accounts.push(InstructionAccount {
                address: resolve(i)?,
                signer: i < signers,
                writable: i < writable_signers
                    || (i >= signers && i < signers + writable_non_signers)
                    || (i >= account_keys.len() && i < account_keys.len() + writable_dynamic),
            });
        }
        instructions.push(VaultInstruction {
            index,
            program: resolve(usize::from(program))?,
            accounts,
            data_hex: hex::encode(data),
        });
    }
    Ok(DecodedTransaction {
        address: address.into(),
        index,
        creator,
        kind: TransactionKind::Vault,
        title: format!("Vault {vault_index} · {} instructions", instructions.len()),
        actions: vec![],
        instructions,
        lookups,
        vault_index: Some(vault_index),
        account_keys,
    })
}

struct VaultHeader {
    signers: usize,
    writable_signers: usize,
    writable_non_signers: usize,
    account_keys: Vec<String>,
}
struct RawInstruction {
    program: u8,
    indices: Vec<u8>,
    data: Vec<u8>,
}
fn read_vault_header(r: &mut Reader<'_>) -> Result<VaultHeader, String> {
    let signers = usize::from(r.u8()?);
    let writable_signers = usize::from(r.u8()?);
    let writable_non_signers = usize::from(r.u8()?);
    let account_keys = r.keys(KEYS_MAX)?;
    if signers > account_keys.len()
        || writable_signers > signers
        || writable_non_signers > account_keys.len() - signers
    {
        return Err("Invalid vault message account header.".into());
    }
    Ok(VaultHeader {
        signers,
        writable_signers,
        writable_non_signers,
        account_keys,
    })
}
fn read_vault_instructions(r: &mut Reader<'_>) -> Result<Vec<RawInstruction>, String> {
    let count = r.count(INSTRUCTIONS_MAX)?;
    (0..count)
        .map(|_| {
            Ok(RawInstruction {
                program: r.u8()?,
                indices: r.vector(KEYS_MAX)?,
                data: r.vector(super::ACCOUNT_BYTES_MAX)?,
            })
        })
        .collect()
}
fn read_vault_lookups(r: &mut Reader<'_>) -> Result<Vec<Lookup>, String> {
    let count = r.count(KEYS_MAX)?;
    (0..count)
        .map(|_| {
            Ok(Lookup {
                address: r.key()?,
                writable_indexes: r.vector(KEYS_MAX)?,
                readonly_indexes: r.vector(KEYS_MAX)?,
            })
        })
        .collect()
}
