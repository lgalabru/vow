//! Build an unsigned USDtest channel review using live devnet accounts.
//! All execution happens in the local Surfnet fork; nothing is broadcast.
#[cfg(target_os = "macos")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    mac::run()
}
#[cfg(not(target_os = "macos"))]
fn main() {
    eprintln!("Channel preparation and native document packaging require macOS.");
    std::process::exit(1);
}
#[cfg(target_os = "macos")]
mod mac {
    use base64::Engine;
    use serde_json::json;
    use solana_rpc_client_api::request::RpcRequest;
    use std::{
        str::FromStr,
        time::{SystemTime, UNIX_EPOCH},
    };
    use surfpool_sdk::{Pubkey, RpcClient};

    const GENESIS: &str = "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG";
    const PROGRAM: &str = "CHNLxYvVA28MJP9PrFuDXccuoGXAx7jBacfLEkahyGsX";
    const MINT: &str = "6MJyWHwFpPsaTEuYarEz49ngtsSKPYn6yHqtJUW2a9St";
    const TOKEN: &str = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb";
    const ATA: &str = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";

    pub fn run() -> Result<(), Box<dyn std::error::Error>> {
        let args: Vec<_> = std::env::args().skip(1).collect();
        if args.len() != 4 {
            return Err(
                "Usage: build_devnet_channel OUTPUT.vow PAYER PAYEE DEPOSIT_BASE_UNITS".into(),
            );
        }
        let payer = Pubkey::from_str(&args[1])?;
        let payee = Pubkey::from_str(&args[2])?;
        let deposit: u64 = args[3].parse()?;
        if payer == payee || !payer.is_on_curve() || !payee.is_on_curve() || deposit == 0 {
            return Err(
                "Use distinct on-curve payer/payee addresses and a positive deposit.".into(),
            );
        }
        let rpc = RpcClient::new("https://api.devnet.solana.com".to_string());
        if rpc.get_genesis_hash()?.to_string() != GENESIS {
            return Err("Unexpected devnet genesis.".into());
        }
        let mint = Pubkey::from_str(MINT)?;
        let token = Pubkey::from_str(TOKEN)?;
        let program = Pubkey::from_str(PROGRAM)?;
        let associated = Pubkey::from_str(ATA)?;
        let mint_account = rpc.get_account(&mint)?;
        if mint_account.owner != token || mint_account.data.get(44) != Some(&6) {
            return Err("USDtest mint owner or decimals changed.".into());
        }
        let payer_ata = Pubkey::find_program_address(
            &[payer.as_ref(), token.as_ref(), mint.as_ref()],
            &associated,
        )
        .0;
        let source = rpc.get_account(&payer_ata)?;
        if source.owner != token
            || source.data.get(..32) != Some(mint.as_ref())
            || source.data.get(32..64) != Some(payer.as_ref())
            || source.data.len() < 72
            || u64::from_le_bytes(source.data[64..72].try_into()?) < deposit
        {
            return Err("The payer's canonical USDtest account cannot fund this deposit.".into());
        }
        // Use a finalized action slot so the fork's finalized source clock cannot
        // place open_slot in the future. The outer hash can use confirmed state.
        let open_slot = rpc.get_slot()?;
        let latest: serde_json::Value = rpc.send(
            RpcRequest::GetLatestBlockhash,
            json!([{"commitment":"confirmed"}]),
        )?;
        let hash = latest["value"]["blockhash"]
            .as_str()
            .ok_or("Missing blockhash")?;
        let height: u64 = rpc.send(
            RpcRequest::GetBlockHeight,
            json!([{"commitment":"confirmed"}]),
        )?;
        let last = latest["value"]["lastValidBlockHeight"]
            .as_u64()
            .ok_or("Missing hash lifetime")?;
        let remaining = last
            .checked_sub(height)
            .filter(|n| *n > 0 && *n <= 300)
            .ok_or("Invalid hash lifetime")?;
        let now = SystemTime::now().duration_since(UNIX_EPOCH)?;
        let observed = now.as_millis() as u64;
        let salt = now.as_nanos() as u64;
        let channel = Pubkey::find_program_address(
            &[
                b"channel",
                payer.as_ref(),
                payee.as_ref(),
                mint.as_ref(),
                payer.as_ref(),
                &salt.to_le_bytes(),
                &open_slot.to_le_bytes(),
            ],
            &program,
        )
        .0;
        let escrow = Pubkey::find_program_address(
            &[channel.as_ref(), token.as_ref(), mint.as_ref()],
            &associated,
        )
        .0;
        let event = Pubkey::find_program_address(&[b"event_authority"], &program).0;
        let keys = [
            payer,
            channel,
            payer_ata,
            escrow,
            payee,
            mint,
            token,
            Pubkey::default(),
            Pubkey::from_str("SysvarRent111111111111111111111111111111111")?,
            associated,
            event,
            program,
        ];
        // One writable signer, three writable unsigned accounts, eight readonly.
        // The 14 open metas intentionally repeat payer for rent and voucher roles.
        let mut wire = vec![1];
        wire.extend_from_slice(&[0; 64]);
        wire.extend_from_slice(&[1, 0, 8, 12]);
        for key in keys {
            wire.extend_from_slice(key.as_ref());
        }
        wire.extend_from_slice(Pubkey::from_str(hash)?.as_ref());
        let mut data = vec![1];
        data.extend_from_slice(&salt.to_le_bytes());
        data.extend_from_slice(&deposit.to_le_bytes());
        data.extend_from_slice(&900u32.to_le_bytes());
        data.extend_from_slice(&open_slot.to_le_bytes());
        data.extend_from_slice(&0u32.to_le_bytes()); // Payee receives the implicit 100% remainder.
        wire.extend_from_slice(&[1, 11, 14, 0, 0, 4, 5, 0, 1, 2, 3, 6, 7, 8, 9, 10, 11]);
        wire.push(data.len() as u8);
        wire.extend_from_slice(&data);
        let envelope = json!({"chain":"solana:devnet","genesis_hash":GENESIS,
        "transaction_base64":base64::prelude::BASE64_STANDARD.encode(&wire),
        "blockhash_context":{"blockhash":hash,"chain":"solana:devnet","genesis_hash":GENESIS,
            "observed_at_unix_ms":observed,"context_slot":latest["context"]["slot"],
            "observed_block_height":height,"last_valid_block_height":last,
            "estimated_expires_at_unix_ms":observed+(remaining*400).min(60_000)}});
        let request =
            json!({"mode":"clipboard","chain":"solana:devnet","data":envelope.to_string()});
        let prepared = vow_simulation::profile(&request)?;
        if !prepared["simulation"]["result"]["err"].is_null() {
            return Err(format!(
                "Open simulation failed: {}",
                prepared["simulation"]["result"]["err"]
            )
            .into());
        }
        let result = &prepared["simulation"]["result"];
        let account_data = |index: usize| -> Result<Vec<u8>, Box<dyn std::error::Error>> {
            Ok(base64::prelude::BASE64_STANDARD.decode(
                result["accounts"][index]["data"][0]
                    .as_str()
                    .ok_or("Missing simulated account state")?,
            )?)
        };
        let channel_data = account_data(1)?;
        let source_data = account_data(2)?;
        let escrow_data = account_data(3)?;
        let before = u64::from_le_bytes(source.data[64..72].try_into()?);
        if result["accounts"][1]["owner"] != PROGRAM
            || channel_data.len() != 256
            || channel_data[3] != 0
            || u64::from_le_bytes(channel_data[12..20].try_into()?) != deposit
            || source_data.len() < 72
            || escrow_data.len() < 72
            || escrow_data[..32] != mint.to_bytes()
            || escrow_data[32..64] != channel.to_bytes()
            || u64::from_le_bytes(escrow_data[64..72].try_into()?) != deposit
            || u64::from_le_bytes(source_data[64..72].try_into()?) != before - deposit
        {
            return Err(
                "Simulation did not produce the requested channel and exact deposit.".into(),
            );
        }
        let package = prepared["package"]
            .as_str()
            .ok_or("Missing review bundle")?;
        let inspected =
            vow_core::inspection::inspect(&json!({"data":package}), vow_core::Chain::Devnet)?;
        if inspected["instructions"][0]["title"] != "Open payment channel"
            || inspected["signed"] != false
            || inspected["signature_count"] != 1
        {
            return Err("Installed decoder did not recognize the channel open.".into());
        }
        let temporary =
            std::env::temp_dir().join(format!("vow-document-{}-{}", std::process::id(), salt));
        std::fs::create_dir(&temporary)?;
        let source = temporary.join("Request.json");
        std::fs::write(&source, package)?;
        let script =
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../scripts/package-vow.sh");
        let status = std::process::Command::new(script)
            .arg(&source)
            .arg(&args[0])
            .status();
        let _ = std::fs::remove_dir_all(&temporary);
        if !status?.success() {
            return Err("Apple document packaging failed.".into());
        }
        println!(
            "{}",
            json!({"file":args[0],"payer":payer.to_string(),"payee":payee.to_string(),
        "deposit_base_units":deposit,"mint":MINT,"channel":channel.to_string(),"open_slot":open_slot,
        "blockhash_observed_at_unix_ms":observed,"blockhash_expires_at_unix_ms":envelope["blockhash_context"]["estimated_expires_at_unix_ms"],
        "simulation_error":prepared["simulation"]["result"]["err"],
        "compute_units":prepared["simulation"]["result"]["unitsConsumed"],"execution_ready":false})
        );
        Ok(())
    }
}
