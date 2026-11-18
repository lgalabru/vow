use super::*;
fn fixture() -> (Multisig, Vec<u8>) {
    let create = Pubkey::new_from_array([7; 32]);
    let address = Pubkey::find_program_address(
        &[b"multisig", b"multisig", create.as_ref()],
        &key(PROGRAM).unwrap(),
    )
    .0
    .to_string();
    let mut bytes = discriminator("Multisig").to_vec();
    bytes.extend(create.to_bytes());
    bytes.extend([0; 32]);
    bytes.extend(1u16.to_le_bytes());
    bytes.extend(0u32.to_le_bytes());
    bytes.extend(5u64.to_le_bytes());
    bytes.extend(4u64.to_le_bytes());
    bytes.extend([0, 255]);
    bytes.extend(2u32.to_le_bytes());
    for key in [[1; 32], [2; 32]] {
        bytes.extend(key);
        bytes.push(7);
    }
    (decode_multisig(&address, PROGRAM, &bytes).unwrap(), bytes)
}
fn proposal(multisig: &Multisig, index: u64, status: u8) -> (String, Vec<u8>) {
    let mut bytes = discriminator("Proposal").to_vec();
    bytes.extend(key(&multisig.address).unwrap().to_bytes());
    bytes.extend(index.to_le_bytes());
    bytes.push(status);
    if status != 4 {
        bytes.extend(123i64.to_le_bytes());
    }
    bytes.push(255);
    bytes.extend([0; 12]);
    (
        transaction_address(&multisig.address, index, true).unwrap(),
        bytes,
    )
}
#[test]
fn account_types_derivations_and_bounds_are_checked() {
    let (m, bytes) = fixture();
    assert_eq!(m.threshold, 1);
    assert_eq!(m.members.len(), 2);
    assert!(m.config_authority.is_none());
    assert_eq!(
        resolve_multisig(&m.address, PROGRAM, &bytes).unwrap(),
        m.address
    );
    assert!(decode_multisig(&Pubkey::default().to_string(), PROGRAM, &bytes).is_err());
    assert!(decode_multisig(&m.address, "11111111111111111111111111111111", &bytes).is_err());
    for length in 0..bytes.len() {
        assert!(decode_multisig(&m.address, PROGRAM, &bytes[..length]).is_err());
    }
    let mut huge = bytes.clone();
    huge[96..100].copy_from_slice(&u32::MAX.to_le_bytes());
    assert!(decode_multisig(&m.address, PROGRAM, &huge).is_err());
    let mut bad = bytes;
    bad[72..74].copy_from_slice(&0u16.to_le_bytes());
    assert!(decode_multisig(&m.address, PROGRAM, &bad).is_err());
}
#[test]
fn proposal_status_and_multisig_binding_are_explicit() {
    let (m, _) = fixture();
    for status in 0..=6 {
        let (address, bytes) = proposal(&m, 5, status);
        let p = decode_proposal(&address, PROGRAM, &bytes, &m, 5).unwrap();
        assert!(!p.stale);
        assert_eq!(p.timestamp_unix_seconds.is_none(), status == 4);
        assert_eq!(
            resolve_multisig(&address, PROGRAM, &bytes).unwrap(),
            m.address
        );
        assert!(decode_proposal(&address, PROGRAM, &bytes, &m, 4).is_err());
        for length in 0..bytes.len() {
            assert!(decode_proposal(&address, PROGRAM, &bytes[..length], &m, 5).is_err());
        }
    }
    let (address, bytes) = proposal(&m, 4, 5);
    assert!(
        decode_proposal(&address, PROGRAM, &bytes, &m, 4)
            .unwrap()
            .stale
    );
    let (address, bytes) = proposal(&m, 5, 7);
    assert!(decode_proposal(&address, PROGRAM, &bytes, &m, 5).is_err());
}
fn config(multisig: &Multisig) -> (String, Vec<u8>) {
    let mut bytes = discriminator("ConfigTransaction").to_vec();
    bytes.extend(key(&multisig.address).unwrap().to_bytes());
    bytes.extend([1; 32]);
    bytes.extend(5u64.to_le_bytes());
    bytes.push(255);
    bytes.extend(1u32.to_le_bytes());
    bytes.push(0);
    bytes.extend([3; 32]);
    bytes.push(7);
    (
        transaction_address(&multisig.address, 5, false).unwrap(),
        bytes,
    )
}
#[test]
fn configuration_actions_do_not_hide_unknown_or_truncated_operations() {
    let (m, _) = fixture();
    let (address, bytes) = config(&m);
    let t = decode_transaction(&address, PROGRAM, &bytes, &m.address, 5).unwrap();
    assert_eq!(t.title, "Add member");
    assert_eq!(t.actions[0].fields[1].value, "Initiate, Vote, Execute");
    assert_eq!(
        resolve_multisig(&address, PROGRAM, &bytes).unwrap(),
        m.address
    );
    for length in 0..bytes.len() {
        assert!(decode_transaction(&address, PROGRAM, &bytes[..length], &m.address, 5).is_err());
    }
    let mut unknown = bytes.clone();
    unknown[85] = 255;
    assert!(decode_transaction(&address, PROGRAM, &unknown, &m.address, 5).is_err());
    let mut other = bytes;
    other[8] ^= 1;
    assert!(decode_transaction(&address, PROGRAM, &other, &m.address, 5).is_err());
}
#[test]
fn vault_message_exposes_raw_instructions_and_rejects_bad_indices() {
    let (m, _) = fixture();
    let (address, mut b) = config(&m);
    b.truncate(81);
    b[..8].copy_from_slice(&discriminator("VaultTransaction"));
    b.extend([0, 255]);
    b.extend(0u32.to_le_bytes());
    b.extend([1, 1, 0]);
    b.extend(2u32.to_le_bytes());
    b.extend([1; 32]);
    b.extend([0; 32]);
    b.extend(1u32.to_le_bytes());
    b.push(1);
    b.extend(1u32.to_le_bytes());
    b.push(0);
    b.extend(4u32.to_le_bytes());
    b.extend([2, 0, 0, 0]);
    b.extend(0u32.to_le_bytes());
    let t = decode_transaction(&address, PROGRAM, &b, &m.address, 5).unwrap();
    assert_eq!(t.instructions.len(), 1);
    assert!(t.instructions[0].accounts[0].signer);
    assert!(t.instructions[0].accounts[0].writable);
    assert_eq!(t.instructions[0].data_hex, "02000000");
    b[162] = 255;
    assert!(decode_transaction(&address, PROGRAM, &b, &m.address, 5).is_err());
}
#[test]
fn approval_preparation_requires_an_active_bound_proposal_and_eligible_voter() {
    let (m, _) = fixture();
    let (address, data) = proposal(&m, 5, 1);
    let mut p = decode_proposal(&address, PROGRAM, &data, &m, 5).unwrap();
    let member = &m.members[0].address;
    let hash = Pubkey::new_from_array([9; 32]).to_string();
    let wire = approval_wire(&m, &p, member, &hash).unwrap();
    let tx = crate::inspection::transaction(&wire).unwrap();
    assert_eq!(wire.len(), 245);
    assert_eq!(tx.message.static_account_keys()[0].to_string(), *member);
    assert_eq!(
        &tx.message.instructions()[0].data[..8],
        &Sha256::digest(b"global:proposal_approve")[..8]
    );
    assert!(approval_wire(&m, &p, &Pubkey::new_from_array([3; 32]).to_string(), &hash).is_err());
    p.approved.push(member.clone());
    assert!(approval_wire(&m, &p, member, &hash).is_err());
    p.approved.clear();
    p.status = ProposalStatus::Executed;
    assert!(approval_wire(&m, &p, member, &hash).is_err());
}
#[test]
fn stored_action_description_is_bound_to_snapshot_owners_and_pdas() {
    use base64::Engine;
    let (m, root) = fixture();
    let (p, pdata) = proposal(&m, 5, 1);
    let (t, tdata) = config(&m);
    let mut snapshot = serde_json::json!({});
    for (key, data) in [(&m.address, root), (&p, pdata), (&t, tdata)] {
        snapshot[key] = serde_json::json!({"owner":PROGRAM,"data":base64::prelude::BASE64_STANDARD.encode(data)});
    }
    let fields = describe_approval(&m.address, &m.members[0].address, &p, &snapshot).unwrap();
    assert!(fields.iter().any(|f| f.value == "Add member"));
    assert!(fields.iter().any(|f| f.value == "Initiate, Vote, Execute"));
    snapshot[&t]["owner"] = serde_json::json!("11111111111111111111111111111111");
    assert!(describe_approval(&m.address, &m.members[0].address, &p, &snapshot).is_err());
}
#[test]
fn program_members_cannot_be_prepared_as_direct_keypair_signers() {
    let (mut m, _) = fixture();
    let (address, data) = proposal(&m, 5, 1);
    let p = decode_proposal(&address, PROGRAM, &data, &m, 5).unwrap();
    let program_member = m.address.clone();
    assert!(!key(&program_member).unwrap().is_on_curve());
    m.members.push(Member {
        address: program_member.clone(),
        permissions: 7,
        direct_signing: false,
    });
    assert!(
        approval_wire(
            &m,
            &p,
            &program_member,
            &Pubkey::new_from_array([9; 32]).to_string()
        )
        .is_err()
    );
}
