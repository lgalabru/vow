use super::{
    ACCOUNT_BYTES_MAX, Field, decode_multisig, decode_proposal, decode_transaction,
    transaction_address,
};
use base64::Engine;
use serde_json::Value;

/// These are decoded snapshot facts, not authenticated chain state or permission to sign.
pub fn describe_approval(
    multisig: &str,
    member: &str,
    proposal: &str,
    snapshot: &Value,
) -> Result<Vec<Field>, String> {
    let (owner, data) = account(snapshot, multisig)?;
    let multisig = decode_multisig(multisig, &owner, &data)?;
    let (owner, data) = account(snapshot, proposal)?;
    let index = u64::from_le_bytes(
        data.get(40..48)
            .ok_or("Proposal state is truncated.")?
            .try_into()
            .expect("eight bytes"),
    );
    let proposal = decode_proposal(proposal, &owner, &data, &multisig, index)?;
    let address = transaction_address(&multisig.address, index, false)?;
    let (owner, data) = account(snapshot, &address)?;
    let transaction = decode_transaction(&address, &owner, &data, &multisig.address, index)?;
    let mut fields = vec![
        Field {
            label: "Proposal number".into(),
            value: index.to_string(),
        },
        Field {
            label: "Proposal status".into(),
            value: format!("{:?}", proposal.status),
        },
        Field {
            label: "Stored transaction".into(),
            value: address,
        },
        Field {
            label: "Stored action".into(),
            value: transaction.title,
        },
    ];
    if !multisig
        .members
        .iter()
        .any(|m| m.address == member && m.permissions & 2 != 0)
    {
        return Err("The requested signer is not an eligible voting member.".into());
    }
    for (index, action) in transaction.actions.into_iter().enumerate() {
        fields.push(Field {
            label: format!("Action {}", index + 1),
            value: action.title,
        });
        for field in action.fields {
            fields.push(Field {
                label: format!("Action {} · {}", index + 1, field.label),
                value: field.value,
            });
        }
    }
    for instruction in transaction.instructions {
        fields.push(Field {
            label: format!("Vault instruction {} · Program", instruction.index + 1),
            value: instruction.program,
        });
        fields.push(Field {
            label: format!("Vault instruction {} · Accounts", instruction.index + 1),
            value: instruction
                .accounts
                .iter()
                .map(|a| {
                    format!(
                        "{}{}{}",
                        a.address,
                        if a.signer { " · signer" } else { "" },
                        if a.writable {
                            " · writable"
                        } else {
                            " · read-only"
                        }
                    )
                })
                .collect::<Vec<_>>()
                .join("\n"),
        });
        fields.push(Field {
            label: format!("Vault instruction {} · Data (hex)", instruction.index + 1),
            value: instruction.data_hex,
        });
    }
    if !transaction.lookups.is_empty() {
        return Err("The stored transaction has unresolved lookup addresses.".into());
    }
    Ok(fields)
}
fn account(snapshot: &Value, address: &str) -> Result<(String, Vec<u8>), String> {
    let value = &snapshot[address];
    let owner = value["owner"].as_str().ok_or(
        "The underlying Squads action is not attached. Retrieve it from Multisigs on the Mac.",
    )?;
    let encoded = value["data"]
        .as_str()
        .filter(|v| v.len() <= ACCOUNT_BYTES_MAX.div_ceil(3) * 4)
        .ok_or("Unsupported Squads snapshot encoding or size.")?;
    let bytes = base64::prelude::BASE64_STANDARD
        .decode(encoded)
        .map_err(|_| "Invalid Squads snapshot data.")?;
    Ok((owner.into(), bytes))
}
