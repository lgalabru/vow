//! Installed wire inspector. Inspection never grants signing or execution authority.
use crate::{Chain, digest, text};
use base64::Engine;
use bincode::Options;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use solana_pubkey::Pubkey;
use solana_transaction::versioned::VersionedTransaction;
use std::str::FromStr;

// Solana transactions, including their signature section, fit one network packet.
const MAX_TRANSACTION_BYTES: usize = 1232;
const CHANNEL: &str = "CHNLxYvVA28MJP9PrFuDXccuoGXAx7jBacfLEkahyGsX";
const TOKEN: &str = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
const ATA: &str = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BlockhashContext {
    pub blockhash: String,
    pub chain: String,
    pub genesis_hash: String,
    pub observed_at_unix_ms: u64,
    pub context_slot: u64,
    pub observed_block_height: u64,
    pub last_valid_block_height: u64,
    pub estimated_expires_at_unix_ms: u64,
}
impl BlockhashContext {
    pub fn require_local_window(&self) -> Result<(), String> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|_| "Check the device clock.")?
            .as_millis();
        if u128::from(self.observed_at_unix_ms) > now + 30_000
            || now >= u128::from(self.estimated_expires_at_unix_ms)
        {
            return Err("The local signing window elapsed or the device clock is inconsistent. Refresh the transaction context on the Mac.".into());
        }
        Ok(())
    }
    pub fn validate(&self, hash: &str, chain: Chain) -> Result<(), String> {
        let remaining = self
            .last_valid_block_height
            .checked_sub(self.observed_block_height)
            .filter(|n| *n > 0 && *n <= 300)
            .ok_or("Invalid block-height lifetime.")?;
        let deadline = self
            .observed_at_unix_ms
            .checked_add((remaining * 400).min(60_000))
            .ok_or("Invalid blockhash observation time.")?;
        if self.blockhash != hash
            || self.chain != chain.wallet_id()
            || self.genesis_hash != chain.genesis_hash()
            || deadline != self.estimated_expires_at_unix_ms
        {
            return Err(
                "Blockhash context does not match the transaction and project network.".into(),
            );
        }
        Ok(())
    }
}
pub fn transaction(bytes: &[u8]) -> Result<VersionedTransaction, String> {
    if bytes.is_empty() || bytes.len() > MAX_TRANSACTION_BYTES {
        return Err("Choose a serialized Solana transaction up to 1232 bytes.".into());
    }
    let tx: VersionedTransaction = bincode::DefaultOptions::new()
        .with_fixint_encoding()
        .with_limit(MAX_TRANSACTION_BYTES as u64)
        .reject_trailing_bytes()
        .deserialize(bytes)
        .map_err(|_| "Malformed Solana transaction dump.")?;
    tx.sanitize()
        .map_err(|_| "Invalid transaction account or instruction indices.")?;
    if bincode::serialize(&tx).map_err(|_| "Cannot encode transaction.")? != bytes {
        return Err("Noncanonical transaction encoding.".into());
    }
    Ok(tx)
}
// Bare messages omit the short-vector signature section. Add only empty slots;
// the message bytes remain the exact bytes the signer will eventually authorize.
fn review_wire(bytes: Vec<u8>, transaction_declared: bool) -> Result<Vec<u8>, String> {
    let transaction_error = match transaction(&bytes) {
        Ok(_) => return Ok(bytes),
        Err(error) => error,
    };
    if transaction_declared || bytes.is_empty() || bytes.len() > MAX_TRANSACTION_BYTES {
        return Err(transaction_error);
    }
    let mut tx = VersionedTransaction {
        signatures: Vec::new(),
        message: bincode::DefaultOptions::new()
            .with_fixint_encoding()
            .with_limit(MAX_TRANSACTION_BYTES as u64)
            .reject_trailing_bytes()
            .deserialize(&bytes)
            .map_err(|_| "Paste a complete serialized Solana transaction or unsigned message.")?,
    };
    tx.message
        .sanitize()
        .map_err(|_| "Invalid message account or instruction indices.")?;
    if bincode::serialize(&tx.message).map_err(|_| "Cannot encode message.")? != bytes {
        return Err("Noncanonical Solana message encoding.".into());
    }
    tx.signatures.resize(
        usize::from(tx.message.header().num_required_signatures),
        Default::default(),
    );
    let wire = bincode::serialize(&tx).map_err(|_| "Cannot encode unsigned transaction.")?;
    transaction(&wire)?;
    debug_assert_eq!(tx.message.serialize(), bytes);
    debug_assert!(
        tx.signatures
            .iter()
            .all(|signature| signature.as_ref().iter().all(|byte| *byte == 0))
    );
    Ok(wire)
}
// Accept raw binary via hex at FFI, a base64/hex text dump, RPC [base64,"base64"],
// a bare legacy/v0 message, or a small JSON envelope. Explicit transaction
// envelopes remain strict. No missing network is inferred from wire bytes.
pub fn inspect(request: &Value, chain: Chain) -> Result<Value, String> {
    let raw = text(request, "data")?;
    if raw.len() > 8 * 1024 * 1024 {
        return Err("Transaction review file exceeds the inspection limit.".into());
    }
    let value = serde_json::from_str::<Value>(raw).unwrap_or(Value::Null);
    if raw.len() > 64 * 1024 && value["format"] != "vow.prototype.inspection.v1" {
        return Err("Transaction dump exceeds the inspection limit.".into());
    }
    if let Some(id) = value.get("chain")
        && id.as_str() != Some(chain.wallet_id())
    {
        return Err("The dump targets another project network.".into());
    }
    if let Some(genesis) = value.get("genesis_hash")
        && genesis.as_str() != Some(chain.genesis_hash())
    {
        return Err("The dump genesis hash does not match this project.".into());
    }
    let hex = value.get("transaction_hex").and_then(Value::as_str);
    let tuple = value
        .get("transaction")
        .and_then(Value::as_array)
        .or_else(|| {
            value
                .get("result")
                .and_then(|r| r.get("transaction"))
                .and_then(Value::as_array)
        })
        .or_else(|| value.as_array());
    if let Some(tuple) = tuple
        && (tuple.len() != 2 || tuple[1] != "base64" || tuple[0].as_str().is_none())
    {
        return Err("Paste one serialized transaction. Encoded RPC tuples must be [transaction, base64]; transaction batches are not silently truncated.".into());
    }
    let b64 = value
        .get("transaction_base64")
        .and_then(Value::as_str)
        .or_else(|| value.get("transaction").and_then(Value::as_str))
        .or_else(|| tuple.and_then(|items| items[0].as_str()));
    let bytes = if let Some(hex) = hex {
        hex::decode(hex).map_err(|_| "Invalid transaction hex.")?
    } else if let Some(b64) = b64 {
        base64::prelude::BASE64_STANDARD
            .decode(b64)
            .map_err(|_| "Invalid transaction base64.")?
    } else {
        let raw = value.as_str().unwrap_or(raw).trim();
        hex::decode(raw)
            .or_else(|_| base64::prelude::BASE64_STANDARD.decode(raw))
            .map_err(|_| "Choose binary, base64, hex, or a transaction JSON dump.")?
    };
    let bytes = review_wire(bytes, hex.is_some() || b64.is_some() || tuple.is_some())?;
    let tx = transaction(&bytes)?;
    let validity: Option<BlockhashContext> = value
        .get("blockhash_context")
        .filter(|v| !v.is_null())
        .map(|v| serde_json::from_value(v.clone()).map_err(|_| "Invalid blockhash context."))
        .transpose()?;
    let hash = tx.message.recent_blockhash().to_string();
    if let Some(context) = &validity {
        context.validate(&hash, chain)?;
    }
    let keys = tx.message.static_account_keys();
    let unresolved = tx
        .message
        .address_table_lookups()
        .is_some_and(|v| !v.is_empty());
    let mut instructions = vec![];
    let mut channel_open_deadline_slot = None;
    for (index, ix) in tx.message.instructions().iter().enumerate() {
        let program = keys
            .get(ix.program_id_index as usize)
            .map(ToString::to_string)
            .unwrap_or_else(|| "Unresolved lookup address".into());
        let accounts=ix.accounts.iter().enumerate().map(|(position,i)|json!({"position":position,"address":keys.get(*i as usize).map(ToString::to_string).unwrap_or_else(||"Unresolved lookup address".into()),"signer":(*i as usize)<usize::from(tx.message.header().num_required_signatures),"writable":tx.message.is_maybe_writable(*i as usize,None)})).collect::<Vec<_>>();
        let mut title = "Unknown instruction — signing blocked".to_string();
        let mut fields = vec![];
        let mut warnings = vec![];
        if program == CHANNEL && !unresolved {
            match ix.data.first().copied() {
                Some(1) if ix.data.len() >= 33 && ix.accounts.len() == 14 => {
                    let count = u32::from_le_bytes(
                        ix.data[29..33]
                            .try_into()
                            .map_err(|_| "Invalid distribution count.")?,
                    ) as usize;
                    if count > 32 || ix.data.len() != 33 + count * 34 {
                        return Err("Invalid open-channel arguments.".into());
                    }
                    title = "Open payment channel".into();
                    let open_slot = u64::from_le_bytes(
                        ix.data[21..29]
                            .try_into()
                            .map_err(|_| "Invalid open slot.")?,
                    );
                    channel_open_deadline_slot = open_slot.checked_add(1500);
                    warnings.push("The pinned channel program accepts open_slot only within 1,500 slots. A new outer blockhash does not extend this action deadline. Changing open_slot changes the channel PDA and requires a new review.".to_string());
                    let names = [
                        "Payer",
                        "Rent payer",
                        "Payee",
                        "Mint",
                        "Voucher signer",
                        "Channel",
                        "Payer token account",
                        "Escrow token account",
                        "Token program",
                        "System program",
                        "Rent sysvar",
                        "Associated token program",
                        "Event authority",
                        "Payment Channels program",
                    ];
                    for (position, name) in names.iter().enumerate() {
                        fields.push(json!({"label":name,"value":accounts[position]["address"]}));
                    }
                    fields.push(json!({"label":"Deposit · raw token units","value":u64::from_le_bytes(ix.data[9..17].try_into().map_err(|_|"Invalid deposit.")?).to_string()}));
                    fields.push(json!({"label":"Close grace period · seconds","value":u32::from_le_bytes(ix.data[17..21].try_into().map_err(|_|"Invalid grace period.")?).to_string()}));
                    fields.push(json!({"label":"Open slot","value":u64::from_le_bytes(ix.data[21..29].try_into().map_err(|_|"Invalid open slot.")?).to_string()}));
                    let mut sum = 0u32;
                    let mut recipients = std::collections::HashSet::new();
                    for entry in ix.data[33..].as_chunks::<34>().0 {
                        let recipient = Pubkey::new_from_array(
                            entry[..32].try_into().map_err(|_| "Invalid recipient.")?,
                        )
                        .to_string();
                        let bps = u16::from_le_bytes([entry[32], entry[33]]);
                        if bps == 0 || !recipients.insert(recipient.clone()) {
                            return Err("Invalid distribution recipients.".into());
                        }
                        sum += u32::from(bps);
                        fields
                            .push(json!({"label":format!("Split · {bps} bps"),"value":recipient}));
                    }
                    if sum > 10000 {
                        return Err("Distribution shares exceed 100%.".into());
                    }
                    fields.push(
                        json!({"label":"Payee remainder · bps","value":(10000-sum).to_string()}),
                    );
                    warnings.push("Opening transfers the deposit into escrow and delegates voucher signing to the listed key. Token decimals, balances, mint authorities, PDA derivations, and program deployment require account-state verification.".to_string());
                }
                Some(7) if ix.data.len() >= 5 && ix.accounts.len() >= 11 => {
                    let count = u32::from_le_bytes(
                        ix.data[1..5]
                            .try_into()
                            .map_err(|_| "Invalid distribution count.")?,
                    ) as usize;
                    if count > 32
                        || ix.data.len() != 5 + count * 34
                        || ix.accounts.len() != 11 + count
                    {
                        return Err("Invalid distribute instruction shape.".into());
                    }
                    title = "Distribute channel proceeds".into();
                    fields.push(json!({"label":"Channel","value":accounts[0]["address"]}));
                    fields.push(json!({"label":"Mint","value":accounts[7]["address"]}));
                    for entry in ix.data[5..].as_chunks::<34>().0 {
                        let address = Pubkey::new_from_array(
                            entry[..32]
                                .try_into()
                                .map_err(|_| "Invalid distribution recipient.")?,
                        );
                        let bps = u16::from_le_bytes([entry[32], entry[33]]);
                        fields.push(json!({"label":format!("Recipient share · {bps} bps"),"value":address.to_string()}));
                    }
                    warnings.push("Permissionless distribution. Amounts depend on channel state, cumulative settled and payout watermarks, and escrow/token accounts. No payout amount can be inferred from these instruction bytes alone. Unusable canonical payout accounts may redirect payment to treasury.".to_string());
                }
                _ => warnings
                    .push("Unsupported Payment Channels instruction or account shape.".into()),
            }
        } else if program == "11111111111111111111111111111111"
            && ix.data.len() == 12
            && ix.data[..4] == 2u32.to_le_bytes()
            && ix.accounts.len() == 2
        {
            title = "Transfer SOL".into();
            fields.push(json!({"label":"Lamports","value":u64::from_le_bytes(ix.data[4..12].try_into().map_err(|_|"Invalid transfer.")?).to_string()}));
        }
        instructions.push(json!({"id":index,"title":title,"program":program,"fields":fields,"accounts":accounts,"data_hex":hex::encode(&ix.data),"warnings":warnings}));
    }
    if let Some(simulation) = value.get("simulation").filter(|v| !v.is_null()) {
        vow_replay::validate_simulation(
            simulation,
            &hex::encode(&bytes),
            chain.wallet_id(),
            chain.genesis_hash(),
        )?;
    }
    let envelope = json!({"simulation":value.get("simulation"),"format":"vow.prototype.inspection.v1","chain":chain.wallet_id(),"genesis_hash":chain.genesis_hash(),"transaction_base64":base64::prelude::BASE64_STANDARD.encode(&bytes),"blockhash_context":validity});
    let package =
        serde_json::to_string_pretty(&envelope).map_err(|_| "Cannot encode inspection file.")?;
    Ok(
        json!({"review_context_digest":digest(package.as_bytes()),"simulation":value.get("simulation"),"id":digest(&bytes),"chain":chain.snapshot(),"network_explicit":value.get("chain").is_some(),"blockhash":hash,"blockhash_context":validity,"channel_open_deadline_slot":channel_open_deadline_slot,"instructions":instructions,"unresolved_lookups":unresolved,"signature_count":tx.signatures.len(),"signed":tx.signatures.iter().any(|s|s.as_ref().iter().any(|b|*b!=0)),"transaction_hex":hex::encode(&bytes),"package":package,"execution_ready":false}),
    )
}
fn key(s: &str) -> Result<Pubkey, String> {
    Pubkey::from_str(s).map_err(|_| "Invalid fixture address.".into())
}
fn ata(owner: &Pubkey, mint: &Pubkey) -> Result<Pubkey, String> {
    Ok(Pubkey::find_program_address(
        &[owner.as_ref(), key(TOKEN)?.as_ref(), mint.as_ref()],
        &key(ATA)?,
    )
    .0)
}
/// Real program ABI and canonical PDAs; unsigned, unfunded example, never submitted.
pub fn channel_fixture(chain: Chain, hash: Option<&str>, open_slot: u64) -> Result<Value, String> {
    let payer = (1..=255)
        .map(|n| Pubkey::new_from_array([n; 32]))
        .find(Pubkey::is_on_curve)
        .ok_or("No fixture key.")?;
    let payee = key("GgBaCs3NCBuZN12kCJgAW63ydqohFkHEdfdEXjLB8F7T")?;
    let signer = payer;
    let mint = key(match chain {
        Chain::Devnet => "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU",
        Chain::Mainnet => "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
    })?;
    let program = key(CHANNEL)?;
    let salt = 42u64;
    let channel = Pubkey::find_program_address(
        &[
            b"channel",
            payer.as_ref(),
            payee.as_ref(),
            mint.as_ref(),
            signer.as_ref(),
            &salt.to_le_bytes(),
            &open_slot.to_le_bytes(),
        ],
        &program,
    )
    .0;
    let event = Pubkey::find_program_address(&[b"event_authority"], &program).0;
    // Legacy message: payer then writable unsigned, then readonly unsigned.
    let keys = vec![
        payer,
        channel,
        ata(&payer, &mint)?,
        ata(&channel, &mint)?,
        payee,
        mint,
        key(TOKEN)?,
        Pubkey::default(),
        key("SysvarRent111111111111111111111111111111111")?,
        key(ATA)?,
        event,
        program,
    ];
    let mut data = vec![1];
    data.extend_from_slice(&salt.to_le_bytes());
    data.extend_from_slice(&1_000_000u64.to_le_bytes());
    data.extend_from_slice(&3600u32.to_le_bytes());
    data.extend_from_slice(&open_slot.to_le_bytes());
    data.extend_from_slice(&1u32.to_le_bytes());
    data.extend_from_slice(payee.as_ref());
    data.extend_from_slice(&2500u16.to_le_bytes());
    let blockhash = hash
        .map(key)
        .transpose()?
        .unwrap_or(Pubkey::new_from_array([4; 32]));
    let mut wire = vec![1];
    wire.extend_from_slice(&[0; 64]);
    wire.extend_from_slice(&[1, 0, 8, 12]);
    for key in keys {
        wire.extend_from_slice(key.as_ref());
    }
    wire.extend_from_slice(blockhash.as_ref());
    wire.extend_from_slice(&[1, 11, 14, 0, 0, 4, 5, 0, 1, 2, 3, 6, 7, 8, 9, 10, 11]);
    wire.push(data.len() as u8);
    wire.extend_from_slice(&data);
    transaction(&wire)?;
    Ok(
        json!({"transaction_hex":hex::encode(wire),"chain":chain.wallet_id(),"genesis_hash":chain.genesis_hash()}),
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    const SQUADS_MESSAGE: &str = "AQACBBBrTyU5asVf4l//YsNtPxAJMABL9f05JdFExaNKZiIUi+Hqj4jRPBdgjD3FhdC3qMjiPwcMcp7ELYM0ahnURQf1K8iPz5bul+MJr7RdiQFRHRQEUHL248GW10srwBrezgaBxM5H4iNouLFVXsiHrwku/H77tmyj9S+/aNSsnLeoYcXmr9MVbB3SA+MoROabY6I+AyacXpMazoTiWQGtGWMBAwMCAAEJkCWkiLzYKvgA";
    #[test]
    fn bare_squads_message_adds_only_empty_signature_slots() {
        let message = base64::prelude::BASE64_STANDARD
            .decode(SQUADS_MESSAGE)
            .unwrap();
        assert_eq!(message.len(), 180);
        assert!(transaction(&message).is_err());
        for raw in [
            SQUADS_MESSAGE.to_string(),
            hex::encode(&message),
            json!(SQUADS_MESSAGE).to_string(),
        ] {
            let inspected = inspect(&json!({"data":raw}), Chain::Devnet).unwrap();
            let wire = hex::decode(inspected["transaction_hex"].as_str().unwrap()).unwrap();
            assert_eq!(wire.len(), message.len() + 65);
            assert_eq!(&wire[..65], &[vec![1], vec![0; 64]].concat());
            assert_eq!(&wire[65..], message);
            assert_eq!(inspected["signed"], false);
            assert_eq!(inspected["signature_count"], 1);
            assert_eq!(
                inspected["instructions"][0]["program"],
                "SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf"
            );
            assert_eq!(inspected["execution_ready"], false);
            let reimported = inspect(&json!({"data":inspected["package"]}), Chain::Devnet).unwrap();
            assert_eq!(reimported["id"], inspected["id"]);
            assert_eq!(reimported["transaction_hex"], inspected["transaction_hex"]);
        }
    }
    #[test]
    fn unsigned_messages_are_canonical_bounded_and_never_replace_declared_transactions() {
        let message = base64::prelude::BASE64_STANDARD
            .decode(SQUADS_MESSAGE)
            .unwrap();
        for value in [
            json!({"transaction_base64":SQUADS_MESSAGE}),
            json!([SQUADS_MESSAGE, "base64"]),
            json!({"transaction_hex":hex::encode(&message)}),
        ] {
            assert!(inspect(&json!({"data":value.to_string()}), Chain::Devnet).is_err());
        }
        for bytes in [message[..179].to_vec(), [message.clone(), vec![0]].concat()] {
            assert!(review_wire(bytes, false).is_err());
        }
        for (position, value) in [(0, 5), (2, 5), (165, 4)] {
            let mut invalid = message.clone();
            invalid[position] = value;
            assert!(review_wire(invalid, false).is_err());
        }
        let mut signed = crate::transaction::fixture_transaction();
        signed[1..65].fill(7);
        assert_eq!(review_wire(signed.clone(), false).unwrap(), signed);
        let mut too_large = message[..170].to_vec();
        too_large.extend_from_slice(&[0xa4, 0x08]); // 1,060 instruction bytes.
        too_large.resize(1232, 0);
        assert!(review_wire(too_large, false).is_err()); // Signature slots must also fit.
        let mut two_signers = message.clone();
        two_signers[0] = 2;
        let wire = review_wire(two_signers.clone(), false).unwrap();
        assert_eq!(wire[0], 2);
        assert_eq!(&wire[1..129], &[0; 128]);
        assert_eq!(&wire[129..], two_signers);
        let mut version_zero = vec![0x80];
        version_zero.extend_from_slice(&message);
        version_zero.push(0); // No address lookup tables.
        let wire = review_wire(version_zero.clone(), false).unwrap();
        assert_eq!(&wire[65..], version_zero);
        assert_eq!(review_wire(wire.clone(), false).unwrap(), wire);
    }
    #[test]
    fn blockhash_context_binds_hash_chain_and_deadline() {
        let fixture = channel_fixture(Chain::Devnet, None, 1).unwrap();
        let wire = hex::decode(fixture["transaction_hex"].as_str().unwrap()).unwrap();
        let hash = transaction(&wire)
            .unwrap()
            .message
            .recent_blockhash()
            .to_string();
        let mut context = BlockhashContext {
            blockhash: hash.clone(),
            chain: Chain::Devnet.wallet_id().into(),
            genesis_hash: Chain::Devnet.genesis_hash().into(),
            observed_at_unix_ms: 1,
            context_slot: 1,
            observed_block_height: 100,
            last_valid_block_height: 250,
            estimated_expires_at_unix_ms: 60_001,
        };
        context.validate(&hash, Chain::Devnet).unwrap();
        assert!(context.validate(&hash, Chain::Mainnet).is_err());
        assert!(context.validate("wrong", Chain::Devnet).is_err());
        assert!(context.require_local_window().is_err());
        context.estimated_expires_at_unix_ms += 1;
        assert!(context.validate(&hash, Chain::Devnet).is_err());
    }
    #[test]
    fn real_channel_wire_and_plain_dump_are_inspected_without_granting_approval() {
        for chain in [Chain::Devnet, Chain::Mainnet] {
            let fixture = channel_fixture(chain, None, 1).unwrap();
            let out = inspect(&json!({"data":fixture.to_string()}), chain).unwrap();
            assert_eq!(out["instructions"][0]["title"], "Open payment channel");
            assert_eq!(out["instructions"][0]["fields"][14]["value"], "1000000");
            assert_eq!(out["execution_ready"], false);
            let raw = inspect(&json!({"data":fixture["transaction_hex"]}), chain).unwrap();
            assert_eq!(raw["network_explicit"], false);
            let other = if chain == Chain::Devnet {
                Chain::Mainnet
            } else {
                Chain::Devnet
            };
            assert!(inspect(&json!({"data":fixture.to_string()}), other).is_err());
        }
    }
}
