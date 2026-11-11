//! Versioned local profile registry. Organization authorization remains prototype-only.
use crate::{Member, canonical_bytes, digest, identity, member, short_name, text, workspace_id};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use solana_pubkey::Pubkey;
use std::{collections::HashSet, str::FromStr};
pub const CEREMONY_FORMAT: &str = "vow.prototype.ceremony.v5";
pub const PROPOSAL_FORMAT: &str = "vow.prototype.proposal.v5";
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Profile {
    pub id: String,
    pub version: u64,
    pub name: String,
    pub organization_id: String,
    pub member_id: u64,
    pub kind: String,
    pub public_key: String,
    pub address: String,
    pub derivation_path: Option<String>,
    pub policy: Value,
    pub proof: Value,
    pub revoked: bool,
}
impl Profile {
    pub fn digest(&self) -> String {
        digest(&canonical_bytes(
            &json!({"domain":"vow.profile.v1","id":self.id,"version":self.version,
          "organization_id":self.organization_id,"member_id":self.member_id,"kind":self.kind,
          "public_key":self.public_key,"address":self.address,"derivation_path":self.derivation_path,
          "policy":self.policy,"proof":self.proof}),
        ))
    }
    pub fn summary(&self) -> Value {
        let mut v = serde_json::to_value(self).expect("profile");
        v["digest"] = json!(self.digest());
        v["registration_status"] = json!("local_prototype_only");
        v["hardware_attestation"] = json!("not_verified");
        v
    }
    pub fn verify(&self) -> Result<(), String> {
        short_name(&self.id)?;
        short_name(&self.name)?;
        short_name(&self.organization_id)?;
        if self.version == 2 {
            let identity: crate::personal_identity::PersonalIdentity =
                serde_json::from_value(self.proof["identity"].clone())
                    .map_err(|_| "Missing personal identity proof.")?;
            identity.verify()?;
            if self.kind != identity.kind
                || self.public_key != identity.public_key
                || self.address != identity.address
                || self.derivation_path != identity.derivation_path
                || self.policy != policy_for_identity(&identity)?
            {
                return Err(
                    "Organization registration does not match the personal signing identity."
                        .into(),
                );
            }
            return Ok(());
        }
        if self.version != 1 {
            return Err("Unsupported profile version.".into());
        }
        match self.kind.as_str() {
            "ledger" => {
                let message = text(&self.proof, "message")?;
                let body: Value = serde_json::from_str(message)
                    .map_err(|_| "Invalid Ledger profile challenge.")?;
                if canonical_bytes(&body) != message.as_bytes()
                    || body["domain"] != "vow.profile.enrollment.v1"
                    || body["profile_id"] != self.id
                    || body["version"] != self.version
                    || body["organization_id"] != self.organization_id
                    || body["member_id"] != self.member_id
                    || body["address"] != self.address
                    || body["derivation_path"] != json!(self.derivation_path)
                    || body["nonce"]
                        .as_str()
                        .is_none_or(|n| n.len() != 64 || hex::decode(n).is_err())
                    || self.public_key != self.address
                    || self.policy != ledger_policy()
                {
                    return Err("Ledger profile identity or policy changed.".into());
                }
                validate_path(
                    self.derivation_path
                        .as_deref()
                        .ok_or("Missing Ledger account path.")?,
                )?;
                let envelope = ledger_envelope(&self.public_key, message.as_bytes())?;
                verify_ed25519(
                    &self.public_key,
                    &envelope,
                    text(&self.proof, "signature_hex")?,
                )?;
            }
            "ipad_security_key" => {
                let _ = identity::verify(&self.proof)?;
                let bytes = hex::decode(text(&self.proof, "message_hex")?)
                    .map_err(|_| "Invalid enrollment.")?;
                let body: Value =
                    serde_json::from_slice(&bytes).map_err(|_| "Invalid enrollment.")?;
                let derived = member::derive(&json!({"public_key":body["device_public_key"]}))?;
                if body["device_public_key"] != self.public_key
                    || derived["address"] != self.address
                    || self.derivation_path.is_some()
                    || self.policy != ipad_policy(&body)
                {
                    return Err("The profile does not match its device enrollment.".into());
                }
            }
            _ => return Err("Unsupported signing profile.".into()),
        }
        Ok(())
    }
}
pub fn policy_for_identity(
    identity: &crate::personal_identity::PersonalIdentity,
) -> Result<Value, String> {
    identity.verify()?;
    if identity.kind == "ledger" {
        return Ok(ledger_policy());
    }
    let body: Value = serde_json::from_slice(
        &hex::decode(text(&identity.proof, "message_hex")?)
            .map_err(|_| "Invalid identity proof.")?,
    )
    .map_err(|_| "Invalid identity proof.")?;
    Ok(ipad_policy(&body))
}
fn ledger_policy() -> Value {
    json!({"algorithm":"ed25519","device_confirmation":true,"signature_scheme":"solana_transaction","local_evidence_scheme":"ledger_offchain_v0","software_fallback":false})
}
fn ipad_policy(body: &Value) -> Value {
    json!({"algorithm":"p256","consent":true,"device_biometrics":true,
  "security_key_public_key":body["security_key_public_key"],"security_key_kind":body["security_key_kind"],
  "credential_id":body["credential_id"],"rp_id":body["rp_id"],"key_source":body["key_source"],
  "bridge_execution_scheme":"external_account"})
}
pub fn validate_path(path: &str) -> Result<(), String> {
    let parts: Vec<_> = path.split('/').collect();
    if parts.iter().skip(3).any(|part| {
        part.strip_suffix("'").is_none_or(|digits| {
            digits.is_empty()
                || !digits.bytes().all(|c| c.is_ascii_digit())
                || (digits.len() > 1 && digits.starts_with('0'))
        })
    }) {
        return Err("Use a canonical hardened Solana account path.".into());
    }
    if !(4..=5).contains(&parts.len())
        || parts[..3] != ["m", "44'", "501'"]
        || parts[3..].iter().any(|p| {
            p.strip_suffix('\'')
                .and_then(|p| p.parse::<u32>().ok())
                .is_none_or(|n| n >= 0x8000_0000)
        })
    {
        return Err("Use a hardened Solana account path.".into());
    }
    Ok(())
}
pub fn ledger_envelope(address: &str, payload: &[u8]) -> Result<Vec<u8>, String> {
    let key = Pubkey::from_str(address).map_err(|_| "Invalid Ledger address.")?;
    let _ = std::str::from_utf8(payload).map_err(|_| "Ledger enrollment requires UTF-8.")?;
    if payload.is_empty() || payload.len() > 1130 {
        return Err("Ledger enrollment payload exceeds its device limit.".into());
    }
    let mut bytes = b"\xffsolana offchain".to_vec();
    bytes.push(0);
    bytes.extend([0; 32]);
    bytes.push(if payload.iter().all(|b| (0x20..=0x7e).contains(b)) {
        0
    } else {
        1
    });
    bytes.push(1);
    bytes.extend(key.to_bytes());
    bytes.extend((payload.len() as u16).to_le_bytes());
    bytes.extend(payload);
    Ok(bytes)
}
pub fn verify_ed25519(address: &str, bytes: &[u8], signature: &str) -> Result<(), String> {
    let public = Pubkey::from_str(address).map_err(|_| "Invalid signer address.")?;
    use curve25519_dalek::{edwards::CompressedEdwardsY, traits::IsIdentity};
    let point = CompressedEdwardsY(public.to_bytes())
        .decompress()
        .ok_or("Invalid Ed25519 point.")?;
    if !point.is_torsion_free() || point.is_identity() {
        return Err("Use a nonidentity prime-order Ed25519 public key.".into());
    }
    let key = ed25519_zebra::VerificationKey::try_from(public.to_bytes())
        .map_err(|_| "Invalid Ed25519 key.")?;
    let sig: [u8; 64] = hex::decode(signature)
        .map_err(|_| "Invalid signature.")?
        .try_into()
        .map_err(|_| "Invalid signature size.")?;
    key.verify(&ed25519_zebra::Signature::from(sig), bytes)
        .map_err(|_| "The signature does not match the profile and exact signed bytes.".into())
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Seat {
    pub member_id: u64,
    pub profile_id: String,
    pub profile_version: u64,
    pub profile_digest: String,
    pub signer_address: String,
}
pub fn validate_seats(
    seats: &[Seat],
    members: &[Member],
    profiles: &[Profile],
    org: &str,
) -> Result<(), String> {
    let mut people = HashSet::new();
    let mut keys = HashSet::new();
    for seat in seats {
        let p = profiles
            .iter()
            .find(|p| p.id == seat.profile_id)
            .ok_or("Profile not found.")?;
        if !people.insert(seat.member_id)
            || !keys.insert(&p.address)
            || p.revoked
            || p.organization_id != org
            || p.member_id != seat.member_id
            || p.version != seat.profile_version
            || p.digest() != seat.profile_digest
            || p.address != seat.signer_address
            || !members.iter().any(|m| m.id == seat.member_id && m.ready)
        {
            return Err(
                "Choose distinct enrolled members and their exact active profile versions.".into(),
            );
        }
        p.verify()?;
    }
    Ok(())
}
#[derive(Default)]
pub struct Catalog {
    pub profiles: Vec<Profile>,
    pending: Option<(Value, u64)>,
}
impl Catalog {
    pub fn cancel(&mut self) {
        self.pending = None;
    }
    pub fn action(
        &mut self,
        r: &Value,
        org: &str,
        members: &[Member],
    ) -> Result<Option<Value>, String> {
        let action = r["action"].as_str().unwrap_or("");
        if ![
            "begin_ledger_profile",
            "finish_ledger_profile",
            "create_ipad_profile",
            "revoke_profile",
            "restore_profile_catalog",
            "cancel_profile_enrollment",
            "import_signing_profile",
        ]
        .contains(&action)
        {
            return Ok(None);
        }
        if action == "cancel_profile_enrollment" {
            self.cancel();
            return Ok(Some(Value::Null));
        }
        if action == "restore_profile_catalog" {
            let profiles: Vec<Profile> = serde_json::from_value(r["profiles"].clone())
                .map_err(|_| "Invalid profile catalog.")?;
            if profiles.len() > 128 {
                return Err("Too many profiles.".into());
            }
            let mut ids = HashSet::new();
            for p in &profiles {
                p.verify()?;
                if !ids.insert(&p.id) {
                    return Err("Duplicate profile identity.".into());
                }
            }
            self.profiles = profiles;
            self.pending = None;
            return Ok(Some(Value::Null));
        }
        if action == "import_signing_profile" {
            let profile: Profile = serde_json::from_value(r["profile"].clone())
                .map_err(|_| "Invalid signing profile record.")?;
            profile.verify()?;
            if profile.organization_id != org
                || !members.iter().any(|m| m.id == profile.member_id && m.ready)
            {
                return Err("Import this profile into its enrolled member's organization.".into());
            }
            if let Some(existing) = self.profiles.iter().find(|p| p.id == profile.id) {
                if existing.digest() != profile.digest() || existing.revoked {
                    return Err(
                        "This profile changed or was revoked. Register a new version.".into(),
                    );
                }
            } else {
                if self.profiles.len() >= 128 {
                    return Err("Too many signing profiles.".into());
                }
                self.profiles.push(profile);
            }
            return Ok(Some(Value::Null));
        }
        if action == "revoke_profile" {
            let p = self
                .profiles
                .iter_mut()
                .find(|p| p.id == r["id"] && p.organization_id == org)
                .ok_or("Profile not found in this organization.")?;
            p.revoked = true;
            self.pending = None;
            return Ok(Some(Value::Null));
        }
        if self.profiles.len() >= 128 {
            return Err("Too many signing profiles.".into());
        }
        if action == "finish_ledger_profile" {
            let (body, deadline) = self
                .pending
                .take()
                .ok_or("Start Ledger enrollment again.")?;
            if now()? > deadline || body["organization_id"] != org {
                return Err("Ledger enrollment expired or the organization changed.".into());
            }
            let p = Profile {
                id: text(&body, "profile_id")?.into(),
                version: 1,
                name: text(&body, "name")?.into(),
                organization_id: org.into(),
                member_id: body["member_id"].as_u64().ok_or("Invalid member.")?,
                kind: "ledger".into(),
                public_key: text(&body, "address")?.into(),
                address: text(&body, "address")?.into(),
                derivation_path: Some(text(&body, "derivation_path")?.into()),
                policy: ledger_policy(),
                proof: json!({"message":String::from_utf8(canonical_bytes(&body)).map_err(|_|"Invalid challenge.")?,"signature_hex":text(r,"signature_hex")?}),
                revoked: false,
            };
            p.verify()?;
            if !members.iter().any(|m| m.id == p.member_id && m.ready) {
                return Err("Physical member enrollment is required.".into());
            }
            self.profiles.push(p);
            return Ok(Some(Value::Null));
        }
        let member_id = r["member_id"].as_u64().ok_or("Choose a member.")?;
        if !members.iter().any(|m| m.id == member_id && m.ready) {
            return Err("Physical member enrollment is required.".into());
        }
        let name = short_name(text(r, "name")?)?;
        let id = workspace_id("profile")?;
        if action == "begin_ledger_profile" {
            let path = text(r, "derivation_path")?;
            validate_path(path)?;
            let address = text(r, "address")?;
            Pubkey::from_str(address).map_err(|_| "Invalid Ledger address.")?;
            let body = json!({"domain":"vow.profile.enrollment.v1","profile_id":id,"version":1,"name":name,"organization_id":org,
              "member_id":member_id,"address":address,"derivation_path":path,"nonce":workspace_id("nonce")?.trim_start_matches("nonce-").to_owned()+&workspace_id("nonce")?[6..]});
            let message =
                String::from_utf8(canonical_bytes(&body)).map_err(|_| "Invalid challenge.")?;
            let _ = ledger_envelope(address, message.as_bytes())?;
            self.pending = Some((body, now()? + 300));
            return Ok(Some(json!({"message":message})));
        }
        let proof = r["enrollment"].clone();
        let _ = identity::verify(&proof)?;
        let body: Value = serde_json::from_slice(
            &hex::decode(text(&proof, "message_hex")?).map_err(|_| "Invalid enrollment.")?,
        )
        .map_err(|_| "Invalid enrollment.")?;
        let public_key = text(&body, "device_public_key")?.to_owned();
        let derived = member::derive(&json!({"public_key":public_key}))?;
        let p = Profile {
            id,
            version: 1,
            name,
            organization_id: org.into(),
            member_id,
            kind: "ipad_security_key".into(),
            public_key,
            address: text(&derived, "address")?.into(),
            derivation_path: None,
            policy: ipad_policy(&body),
            proof,
            revoked: false,
        };
        p.verify()?;
        self.profiles.push(p);
        Ok(Some(Value::Null))
    }
}
pub(crate) fn now() -> Result<u64, String> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .map_err(|_| "Cannot read the clock.".into())
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use ed25519_zebra::{SigningKey, VerificationKeyBytes};
    pub fn fixture(member: u64, seed: u8) -> Profile {
        let key = SigningKey::from([seed; 32]);
        let address = Pubkey::new_from_array(VerificationKeyBytes::from(&key).into()).to_string();
        let members = vec![Member {
            id: member,
            name: "Owner".into(),
            role: "Signer".into(),
            ready: true,
        }];
        let mut catalog = Catalog::default();
        let response=catalog.action(&json!({"action":"begin_ledger_profile","member_id":member,"name":"Treasury Ledger","address":address,"derivation_path":"m/44'/501'/0'"}),"org",&members).unwrap().unwrap();
        let message = response["message"].as_str().unwrap();
        let sig = key.sign(&ledger_envelope(&address, message.as_bytes()).unwrap());
        catalog.action(&json!({"action":"finish_ledger_profile","signature_hex":hex::encode(sig.to_bytes())}),"org",&members).unwrap();
        catalog.profiles.remove(0)
    }
    fn seat(p: &Profile) -> Seat {
        Seat {
            member_id: p.member_id,
            profile_id: p.id.clone(),
            profile_version: p.version,
            profile_digest: p.digest(),
            signer_address: p.address.clone(),
        }
    }
    #[test]
    fn ledger_enrollment_verifies_envelope_and_consumes_its_challenge() {
        let p = fixture(1, 7);
        p.verify().unwrap();
        let msg = text(&p.proof, "message").unwrap();
        assert!(
            verify_ed25519(
                &p.address,
                msg.as_bytes(),
                text(&p.proof, "signature_hex").unwrap()
            )
            .is_err()
        );
        let mut bad = p.clone();
        bad.proof["signature_hex"] = json!("00".repeat(64));
        assert!(bad.verify().is_err());
        let mut bad = p.clone();
        bad.derivation_path = Some("m/44'/501'/1'".into());
        assert!(bad.verify().is_err());
        let mut bad = p.clone();
        bad.member_id = 2;
        assert!(bad.verify().is_err());
        let mut bad = p.clone();
        bad.organization_id = "elsewhere".into();
        assert!(bad.verify().is_err());
        let mut bad = p.clone();
        bad.policy["software_fallback"] = json!(true);
        assert!(bad.verify().is_err());
        let mut bad = p.clone();
        bad.public_key = fixture(1, 8).address;
        assert!(bad.verify().is_err());
        let mut bad = p.clone();
        bad.version = 2;
        assert!(bad.verify().is_err());
        let mut renamed = p.clone();
        renamed.name = "Travel Ledger".into();
        assert_eq!(p.digest(), renamed.digest());
        renamed.verify().unwrap();
        assert!(Catalog::default().action(&json!({"action":"finish_ledger_profile","signature_hex":p.proof["signature_hex"]}),"org",&[]).is_err());
    }
    #[test]
    fn quorum_seats_reject_wrong_owner_duplicate_person_key_revocation_and_versions() {
        let first = fixture(1, 7);
        let second = fixture(2, 8);
        let members = vec![
            Member {
                id: 1,
                name: "A".into(),
                role: "Signer".into(),
                ready: true,
            },
            Member {
                id: 2,
                name: "B".into(),
                role: "Signer".into(),
                ready: true,
            },
        ];
        let profiles = vec![first.clone(), second.clone()];
        let seats = vec![seat(&first), seat(&second)];
        validate_seats(&seats, &members, &profiles, "org").unwrap();
        for mode in [
            "duplicate",
            "owner",
            "version",
            "digest",
            "address",
            "missing",
        ] {
            let mut bad = seats.clone();
            match mode {
                "duplicate" => bad.push(seat(&first)),
                "owner" => bad[0].member_id = 2,
                "version" => bad[0].profile_version += 1,
                "digest" => bad[0].profile_digest = "changed".into(),
                "address" => bad[0].signer_address = second.address.clone(),
                _ => bad[0].profile_id = "missing".into(),
            }
            assert!(
                validate_seats(&bad, &members, &profiles, "org").is_err(),
                "{mode}"
            );
        }
        assert!(validate_seats(&seats, &members, &profiles, "other").is_err());
        let mut revoked = profiles.clone();
        revoked[0].revoked = true;
        assert!(validate_seats(&seats, &members, &revoked, "org").is_err());
        let same = fixture(2, 7);
        assert!(
            validate_seats(
                &[seat(&first), seat(&same)],
                &members,
                &[first, same],
                "org"
            )
            .is_err()
        );
    }
    #[test]
    fn envelope_boundaries_and_wrong_signature_domains_fail_closed() {
        let p = fixture(1, 7);
        let address = &p.address;
        let envelope = ledger_envelope(address, b"Vow enrollment").unwrap();
        assert_eq!(&envelope[..16], b"\xffsolana offchain");
        assert_eq!(envelope.len(), 85 + 14);
        assert_eq!(envelope[49], 0);
        assert_eq!(ledger_envelope(address, b"line\nbreak").unwrap()[49], 1);
        assert!(ledger_envelope(address, &vec![b'a'; 1130]).is_ok());
        assert!(ledger_envelope(address, &vec![b'a'; 1131]).is_err());
        assert!(ledger_envelope(address, b"").is_err());
        assert!(ledger_envelope(address, &[0xff]).is_err());
        let identity = Pubkey::new_from_array([0; 32]).to_string();
        assert!(verify_ed25519(&identity, b"anything", &"00".repeat(64)).is_err());
        for path in ["m/44'/501'/0'", "m/44'/501'/0'/0'"] {
            validate_path(path).unwrap();
        }
        for path in [
            "m/44'/0'/0'",
            "m/44'/501'/0",
            "m/44'/501'/2147483648'",
            "m/44'/501'/0'/0'/0'",
        ] {
            assert!(validate_path(path).is_err());
        }
    }
    pub fn ipad_fixture(member_id: u64) -> Profile {
        use p256::ecdsa::{SigningKey, signature::Signer};
        let device = SigningKey::from_slice(&[3; 32]).unwrap();
        let security = SigningKey::from_slice(&[4; 32]).unwrap();
        let public = hex::encode(device.verifying_key().to_encoded_point(true));
        let prepared=identity::prepare(&json!({"device_public_key":public,"security_key_public_key":hex::encode(security.verifying_key().to_encoded_point(true)),"key_source":"simulator_software"})).unwrap();
        let message = hex::decode(prepared["message_hex"].as_str().unwrap()).unwrap();
        let ds: p256::ecdsa::Signature = device.sign(&message);
        let ss: p256::ecdsa::Signature = security.sign(&message);
        let proof = json!({"message_hex":prepared["message_hex"],"device_signature":hex::encode(ds.to_bytes()),"security_key_signature":hex::encode(ss.to_bytes())});
        let mut catalog = Catalog::default();
        catalog.action(&json!({"action":"create_ipad_profile","name":"iPad protected","member_id":member_id,"enrollment":proof}),"org",&[Member{id:member_id,name:"Owner".into(),role:"Signer".into(),ready:true}]).unwrap();
        catalog.profiles.remove(0)
    }
    #[test]
    fn imported_profiles_are_scope_checked_and_cannot_resurrect_revoked_records() {
        let p = fixture(1, 7);
        let members = [Member {
            id: 1,
            name: "Owner".into(),
            role: "Signer".into(),
            ready: true,
        }];
        let mut catalog = Catalog::default();
        let import = json!({"action":"import_signing_profile","profile":p});
        assert!(catalog.action(&import, "other", &members).is_err());
        catalog.action(&import, "org", &members).unwrap();
        assert_eq!(catalog.profiles.len(), 1);
        catalog.action(&import, "org", &members).unwrap();
        assert_eq!(catalog.profiles.len(), 1);
        let mut bad = import.clone();
        bad["profile"]["member_id"] = json!(2);
        assert!(catalog.action(&bad, "org", &members).is_err());
        catalog
            .action(
                &json!({"action":"revoke_profile","id":p.id}),
                "org",
                &members,
            )
            .unwrap();
        assert!(catalog.action(&import, "org", &members).is_err());
        assert!(catalog.profiles[0].revoked);
        let ipad = ipad_fixture(1);
        ipad.verify().unwrap();
        let mut changed = ipad.clone();
        changed.policy["consent"] = json!(false);
        assert!(changed.verify().is_err());
        let mut changed = ipad.clone();
        changed.public_key = p.address;
        assert!(changed.verify().is_err());
        let mut changed = ipad;
        changed.proof["security_key_signature"] = json!("00".repeat(64));
        assert!(changed.verify().is_err());
    }
    #[test]
    fn expired_or_replaced_enrollment_challenges_cannot_complete_and_failure_consumes_them() {
        let p = fixture(1, 7);
        let members = [Member {
            id: 1,
            name: "Owner".into(),
            role: "Signer".into(),
            ready: true,
        }];
        let mut catalog = Catalog::default();
        let begin = json!({"action":"begin_ledger_profile","name":"Ledger","member_id":1,"address":p.address,"derivation_path":p.derivation_path});
        catalog.action(&begin, "org", &members).unwrap();
        catalog.pending.as_mut().unwrap().1 = 0;
        let complete =
            json!({"action":"finish_ledger_profile","signature_hex":p.proof["signature_hex"]});
        assert!(catalog.action(&complete, "org", &members).is_err());
        assert!(catalog.pending.is_none());
        catalog.action(&begin, "org", &members).unwrap();
        assert!(catalog.action(&complete, "org", &members).is_err());
        assert!(catalog.profiles.is_empty());
        assert!(catalog.pending.is_none());
    }
}
