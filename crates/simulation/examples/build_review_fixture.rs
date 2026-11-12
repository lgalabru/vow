//! Deterministic offline-only token transfer for native inspector UI tests.
use base64::Engine;
use serde_json::{Value, json};
use surfpool_sdk::Pubkey;
fn main() {
    let payer = Pubkey::new_from_array([9; 32]);
    let source = Pubkey::new_from_array([3; 32]);
    let destination = Pubkey::new_from_array([4; 32]);
    let mint = Pubkey::new_from_array([7; 32]);
    let token: Pubkey = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
        .parse()
        .unwrap();
    let system = "11111111111111111111111111111111";
    let mut wire = vec![1];
    wire.extend([0u8; 64]);
    wire.extend([1, 0, 1, 4]);
    for key in [payer, source, destination, token] {
        wire.extend(key.to_bytes());
    }
    wire.extend([7; 32]);
    wire.extend([1, 3, 3, 1, 2, 0, 9, 3]);
    wire.extend(1_000_000u64.to_le_bytes());
    let inspect =
        vow_core::inspection::inspect(&json!({"data":hex::encode(&wire)}), vow_core::Chain::Devnet)
            .unwrap();
    let mut mint_data = vec![0; 82];
    mint_data[36..44].copy_from_slice(&10_000_000u64.to_le_bytes());
    mint_data[44] = 6;
    mint_data[45] = 1;
    let account = |owner: &str, lamports: u64, data: &[u8]| json!({"owner":owner,"lamports":lamports,"data":base64::prelude::BASE64_STANDARD.encode(data),"executable":false,"rentEpoch":0});
    let token_data = |owner: Pubkey, amount: u64| {
        let mut data = vec![0; 165];
        data[..32].copy_from_slice(&mint.to_bytes());
        data[32..64].copy_from_slice(&owner.to_bytes());
        data[64..72].copy_from_slice(&amount.to_le_bytes());
        data[108] = 1;
        data
    };
    let snapshot = json!({payer.to_string():account(system,10_000_000_000,&[]),source.to_string():account(&token.to_string(),2_039_280,&token_data(payer,10_000_000)),destination.to_string():account(&token.to_string(),2_039_280,&token_data(Pubkey::new_from_array([10;32]),0)),mint.to_string():account(&token.to_string(),1_461_600,&mint_data),token.to_string():Value::Null});
    let fixture = json!({"format":"vow.prototype.inspection.v1","chain":"solana:devnet","genesis_hash":vow_core::Chain::Devnet.genesis_hash(),"transaction_hex":hex::encode(wire),"simulation":{"format":"vow.simulation.v1","chain":"solana:devnet","genesis_hash":vow_core::Chain::Devnet.genesis_hash(),"wire_digest":inspect["id"],"state_source":"synthetic_fixture","signature_checks":false,"blockhash_checks":false,"rpc_slot_start":0,"rpc_slot_end":0,"result":{"err":null},"snapshot":snapshot}});
    let output = std::env::args().nth(1).expect("fixture JSON path");
    std::fs::write(output, serde_json::to_vec_pretty(&fixture).unwrap()).unwrap();
}
