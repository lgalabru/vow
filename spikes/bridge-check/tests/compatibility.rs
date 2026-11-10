//! Exercise the unmodified pinned bridge in LiteSVM using Apple CryptoKit output.
use borsh::to_vec;
use external_signature_program::{
    instructions::initialize_external_account::InitializeAccountArgs,
    state::{P256RawInitializationData, SignatureScheme},
    utils::{
        signatures::{reconstruct_client_data_json, AuthType, ClientDataJsonReconstructionParams},
        SmallVec, TruncatedSlot,
    },
};
use litesvm::LiteSVM;
use p256::ecdsa::{signature::Verifier, Signature, VerifyingKey};
use serde::Deserialize;
use serde_json::json;
use sha2::{Digest, Sha256};
use solana_hash::Hash;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
use solana_message::Message;
use solana_pubkey::Pubkey;
use solana_signer::Signer;
use solana_slot_hashes::SlotHashes;
use solana_transaction::Transaction;
use std::{
    io::Write,
    process::{Command, Stdio},
};

const RP: &str = "vow.invalid";
const SLOT: u64 = 500;
const SLOT_HASH: [u8; 32] = [7; 32];
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Fixture {
    name: String,
    key_source: String,
    public_key_hex: String,
    message_hex: String,
    signature_hex: String,
}
fn params() -> ClientDataJsonReconstructionParams {
    ClientDataJsonReconstructionParams::new(AuthType::Get, false, false, false, None)
}
// The upstream pure JSON reconstruction function is safe on the host. Do not
// call its host hash wrapper: the syscall implementation is Solana-only.
fn assertion_message(challenge: &[u8], flags: u8) -> Vec<u8> {
    let json = reconstruct_client_data_json(&params(), RP.as_bytes(), challenge);
    let mut message = Sha256::digest(RP.as_bytes()).to_vec();
    message.push(flags);
    message.extend_from_slice(&0u32.to_be_bytes());
    message.extend_from_slice(&Sha256::digest(json));
    message
}
fn fixtures(payer: &Pubkey) -> Vec<Fixture> {
    let challenge =
        Sha256::digest([SLOT_HASH.as_slice(), payer.as_ref(), b"initialize_passkey"].concat());
    let wrong = [9u8; 32];
    let cases = [
        ("wrapped", 5, false, &challenge[..]),
        ("bare", 5, true, &challenge[..]),
        ("no-presence", 4, false, &challenge[..]),
        ("no-verification", 1, false, &challenge[..]),
        ("wrong-challenge", 5, false, &wrong[..]),
    ]
    .into_iter()
    .map(|(name, flags, raw, hash)| {
        let message = if raw {
            hash.to_vec()
        } else {
            assertion_message(hash, flags)
        };
        json!({"name":name, "messageHex":hex::encode(message)})
    })
    .collect::<Vec<_>>();
    let binary = std::env::var("VOW_SWIFT_PROBE")
        .expect("set VOW_SWIFT_PROBE to the built Swift executable");
    let mode = std::env::var("VOW_KEY_MODE").unwrap_or_else(|_| "--software-fixture".into());
    assert!([
        "--software-fixture",
        "--secure-enclave",
        "--hardware-crypto-only"
    ]
    .contains(&mode.as_str()));
    let mut child = Command::new(binary)
        .arg(&mode)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(&serde_json::to_vec(&json!({"cases":cases})).unwrap())
        .unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(
        output.status.success(),
        "Swift probe failed; no software fallback is allowed"
    );
    let result: Vec<Fixture> = serde_json::from_slice(&output.stdout).unwrap();
    for f in &result {
        assert_eq!(f.key_source, mode.trim_start_matches("--"));
    }
    result
}
fn precompile(f: &Fixture, tamper: bool) -> Instruction {
    let key = hex::decode(&f.public_key_hex).unwrap();
    let message = hex::decode(&f.message_hex).unwrap();
    let signature = Signature::from_slice(&hex::decode(&f.signature_hex).unwrap()).unwrap();
    // Solana requires low-S; CryptoKit's rawRepresentation does not promise it.
    let signature = signature.normalize_s().unwrap_or(signature);
    VerifyingKey::from_sec1_bytes(&key)
        .unwrap()
        .verify(&message, &signature)
        .unwrap();
    let mut signature = signature.to_bytes().to_vec();
    if tamper {
        signature[0] ^= 1;
    }
    let mut data = vec![1, 0];
    // One self-contained signature: offsets start after the 16-byte header.
    for n in [
        49u16,
        u16::MAX,
        16,
        u16::MAX,
        113,
        message.len() as u16,
        u16::MAX,
    ] {
        data.extend_from_slice(&n.to_le_bytes());
    }
    data.extend(key);
    data.extend(signature);
    data.extend(message);
    Instruction {
        program_id: solana_secp256r1_program::id(),
        accounts: vec![],
        data,
    }
}
fn initialize(f: &Fixture, payer: &Pubkey) -> Instruction {
    let program = Pubkey::new_from_array(external_signature_program::ID);
    let key: [u8; 33] = hex::decode(&f.public_key_hex).unwrap().try_into().unwrap();
    let key_hash = Sha256::digest(key);
    let (account, _) = Pubkey::find_program_address(&[b"passkey", &key_hash], &program);
    let init = P256RawInitializationData {
        rp_id: SmallVec::try_from(RP.as_bytes().to_vec()).unwrap(),
        public_key: key,
        client_data_json_reconstruction_params: params(),
    };
    let args = InitializeAccountArgs {
        slothash: TruncatedSlot::new(SLOT).unwrap(),
        signature_scheme: SignatureScheme::P256Webauthn.into(),
        initialization_data: SmallVec::try_from(to_vec(&init).unwrap()).unwrap(),
        session_key: None,
    };
    let mut data = vec![0];
    data.extend(to_vec(&args).unwrap());
    Instruction {
        program_id: program,
        data,
        accounts: vec![
            AccountMeta::new(account, false),
            AccountMeta::new(*payer, true),
            AccountMeta::new_readonly(solana_sdk_ids::sysvar::instructions::id(), false),
            AccountMeta::new_readonly(solana_sdk_ids::sysvar::slot_hashes::id(), false),
            AccountMeta::new_readonly(solana_sdk_ids::system_program::id(), false),
        ],
    }
}
#[test]
fn cryptokit_output_exercises_the_actual_bridge_verifier() {
    let payer = Keypair::new();
    let fixture = fixtures(&payer.pubkey());
    let challenge = Sha256::digest(
        [
            SLOT_HASH.as_slice(),
            payer.pubkey().as_ref(),
            b"initialize_passkey",
        ]
        .concat(),
    );
    let wrapped = &fixture[0];
    assert_eq!(
        hex::decode(&wrapped.message_hex).unwrap(),
        assertion_message(&challenge, 5)
    );
    let program_file =
        std::env::var("VOW_BRIDGE_SO").expect("set VOW_BRIDGE_SO to the pinned SBF artifact");
    for (f, tamper, expected) in fixture
        .iter()
        .map(|f| {
            (
                f,
                false,
                matches!(f.name.as_str(), "wrapped" | "no-verification"),
            )
        })
        .chain(std::iter::once((wrapped, true, false)))
    {
        let mut svm = LiteSVM::new();
        svm.set_sysvar(&SlotHashes::new(&[(SLOT, Hash::new_from_array(SLOT_HASH))]));
        svm.airdrop(&payer.pubkey(), 1_000_000_000).unwrap();
        svm.add_program_from_file(
            Pubkey::new_from_array(external_signature_program::ID),
            &program_file,
        )
        .unwrap();
        let ix = [precompile(f, tamper), initialize(f, &payer.pubkey())];
        let blockhash = svm.latest_blockhash();
        let tx = Transaction::new(
            &[&payer],
            Message::new_with_blockhash(&ix, Some(&payer.pubkey()), &blockhash),
            blockhash,
        );
        let result = svm.send_transaction(tx);
        assert_eq!(
            result.is_ok(),
            expected,
            "case={},tamper={tamper}: {result:?}",
            f.name
        );
        eprintln!(
            "case={} tamper={tamper} accepted={}",
            f.name,
            result.is_ok()
        );
    }
}
