//! Personal signing identities are independent from ceremony membership.
use crate::{canonical_bytes, digest, identity, member, profiles, short_name, text, workspace_id};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PersonalIdentity {
    pub id: String,
    pub version: u64,
    pub name: String,
    pub kind: String,
    pub address: String,
    pub public_key: String,
    pub derivation_path: Option<String>,
    pub proof: Value,
}
impl PersonalIdentity {
    pub fn verify(&self) -> Result<(), String> {
        short_name(&self.id)?;
        short_name(&self.name)?;
        if self.version != 1 {
            return Err("Unsupported personal identity version.".into());
        }
        match self.kind.as_str() {
            "ledger" => {
                let message = text(&self.proof, "message")?;
                let body: Value =
                    serde_json::from_str(message).map_err(|_| "Invalid identity proof.")?;
                if canonical_bytes(&body) != message.as_bytes()
                    || body["domain"] != "vow.identity.enrollment.v1"
                    || body["identity_id"] != self.id
                    || body["version"] != self.version
                    || body["address"] != self.address
                    || self.public_key != self.address
                    || body["derivation_path"] != json!(self.derivation_path)
                    || body["nonce"]
                        .as_str()
                        .is_none_or(|n| n.len() != 64 || hex::decode(n).is_err())
                {
                    return Err(
                        "Personal identity proof does not match its signing account.".into(),
                    );
                }
                profiles::validate_path(
                    self.derivation_path
                        .as_deref()
                        .ok_or("Missing account path.")?,
                )?;
                profiles::verify_ed25519(
                    &self.address,
                    &profiles::ledger_envelope(&self.address, message.as_bytes())?,
                    text(&self.proof, "signature_hex")?,
                )?;
            }
            "ipad_security_key" => {
                identity::verify(&self.proof)?;
                let body: Value = serde_json::from_slice(
                    &hex::decode(text(&self.proof, "message_hex")?)
                        .map_err(|_| "Invalid identity proof.")?,
                )
                .map_err(|_| "Invalid identity proof.")?;
                let derived = member::derive(&json!({"public_key":body["device_public_key"]}))?;
                if body["device_public_key"] != self.public_key
                    || derived["address"] != self.address
                    || self.derivation_path.is_some()
                {
                    return Err("Personal identity does not match its device enrollment.".into());
                }
            }
            _ => return Err("Unsupported personal signing method.".into()),
        }
        Ok(())
    }
    pub fn digest(&self) -> String {
        digest(&canonical_bytes(
            &json!({"domain":"vow.personal-identity.v1","id":self.id,"version":self.version,"kind":self.kind,"address":self.address,"public_key":self.public_key,"derivation_path":self.derivation_path,"proof":self.proof}),
        ))
    }
}
#[derive(Default)]
pub struct IdentityCatalog {
    pub identities: Vec<PersonalIdentity>,
    pending: Option<(Value, u64)>,
}
impl IdentityCatalog {
    pub fn cancel(&mut self) {
        self.pending = None;
    }
    pub fn action(&mut self, r: &Value) -> Result<Option<Value>, String> {
        let action = r["action"].as_str().unwrap_or("");
        if ![
            "begin_personal_ledger",
            "finish_personal_ledger",
            "create_personal_ipad",
            "restore_personal_identities",
            "import_personal_identity",
            "cancel_personal_identity",
        ]
        .contains(&action)
        {
            return Ok(None);
        }
        if action == "cancel_personal_identity" {
            self.cancel();
            return Ok(Some(Value::Null));
        }
        if action == "import_personal_identity" {
            let identity: PersonalIdentity = serde_json::from_value(r["identity"].clone())
                .map_err(|_| "Invalid personal profile.")?;
            identity.verify()?;
            if let Some(existing) = self.identities.iter().find(|i| i.id == identity.id) {
                if existing.digest() != identity.digest() {
                    return Err("Personal identity changed. Import rejected.".into());
                }
            } else {
                if self.identities.len() >= 128 {
                    return Err("Too many personal identities.".into());
                }
                self.identities.push(identity);
            }
            return Ok(Some(Value::Null));
        }
        if action == "restore_personal_identities" {
            let all: Vec<PersonalIdentity> = serde_json::from_value(r["identities"].clone())
                .map_err(|_| "Invalid saved identities.")?;
            if all.len() > 128 {
                return Err("Too many personal identities.".into());
            }
            let mut ids = std::collections::HashSet::new();
            for identity in &all {
                identity.verify()?;
                if !ids.insert(&identity.id) {
                    return Err("Duplicate personal identity.".into());
                }
            }
            self.identities = all;
            self.cancel();
            return Ok(Some(Value::Null));
        }
        if self.identities.len() >= 128 {
            return Err("Too many personal identities.".into());
        }
        if action == "finish_personal_ledger" {
            let (body, deadline) = self.pending.take().ok_or("Start Ledger setup again.")?;
            if profiles::now()? > deadline {
                return Err("Ledger setup expired. Verify the account again.".into());
            }
            let identity = PersonalIdentity {
                id: text(&body, "identity_id")?.into(),
                version: 1,
                name: text(&body, "name")?.into(),
                kind: "ledger".into(),
                address: text(&body, "address")?.into(),
                public_key: text(&body, "address")?.into(),
                derivation_path: Some(text(&body, "derivation_path")?.into()),
                proof: json!({"message":String::from_utf8(canonical_bytes(&body)).map_err(|_|"Invalid identity message.")?,"signature_hex":text(r,"signature_hex")?}),
            };
            identity.verify()?;
            self.identities.push(identity);
            return Ok(Some(Value::Null));
        }
        let name = short_name(text(r, "name")?)?;
        let id = workspace_id("identity")?;
        if action == "begin_personal_ledger" {
            let path = text(r, "derivation_path")?;
            profiles::validate_path(path)?;
            let address = text(r, "address")?;
            let body = json!({"domain":"vow.identity.enrollment.v1","identity_id":id,"version":1,"name":name,"address":address,"derivation_path":path,"nonce":workspace_id("nonce")?.trim_start_matches("nonce-").to_owned()+&workspace_id("nonce")?[6..]});
            let message = String::from_utf8(canonical_bytes(&body))
                .map_err(|_| "Invalid identity message.")?;
            profiles::ledger_envelope(address, message.as_bytes())?;
            self.pending = Some((body, profiles::now()? + 300));
            return Ok(Some(json!({"message":message})));
        }
        let proof = r["enrollment"].clone();
        identity::verify(&proof)?;
        let body: Value = serde_json::from_slice(
            &hex::decode(text(&proof, "message_hex")?).map_err(|_| "Invalid enrollment.")?,
        )
        .map_err(|_| "Invalid enrollment.")?;
        let public_key = text(&body, "device_public_key")?.to_owned();
        let derived = member::derive(&json!({"public_key":public_key}))?;
        let identity = PersonalIdentity {
            id,
            version: 1,
            name,
            kind: "ipad_security_key".into(),
            address: text(&derived, "address")?.into(),
            public_key,
            derivation_path: None,
            proof,
        };
        identity.verify()?;
        self.identities.push(identity);
        Ok(Some(Value::Null))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_zebra::{SigningKey, VerificationKeyBytes};
    fn complete(catalog: &mut IdentityCatalog) -> PersonalIdentity {
        let key = SigningKey::from([31; 32]);
        let address =
            solana_pubkey::Pubkey::new_from_array(VerificationKeyBytes::from(&key).into())
                .to_string();
        let challenge = catalog.action(&json!({"action":"begin_personal_ledger","name":"Ludo","address":address,"derivation_path":"m/44'/501'/0'"})).unwrap().unwrap();
        let message = challenge["message"].as_str().unwrap();
        assert!(!message.contains("organization"));
        let sig = key.sign(&profiles::ledger_envelope(&address, message.as_bytes()).unwrap());
        catalog.action(&json!({"action":"finish_personal_ledger","signature_hex":hex::encode(sig.to_bytes())})).unwrap();
        catalog.identities[0].clone()
    }
    #[test]
    fn personal_enrollment_is_independent_and_tamper_evident() {
        let mut catalog = IdentityCatalog::default();
        let identity = complete(&mut catalog);
        identity.verify().unwrap();
        let mut changed = identity.clone();
        changed.address = "11111111111111111111111111111111".into();
        assert!(changed.verify().is_err());
        let mut changed = identity.clone();
        changed.id = "other-identity".into();
        assert!(changed.verify().is_err());
        assert!(catalog.action(&json!({"action":"finish_personal_ledger","signature_hex":identity.proof["signature_hex"]})).is_err());
        let mut restored = IdentityCatalog::default();
        restored
            .action(
                &json!({"action":"restore_personal_identities","identities":[identity.clone()]}),
            )
            .unwrap();
        assert_eq!(restored.identities[0].digest(), identity.digest());
        assert!(restored.action(&json!({"action":"restore_personal_identities","identities":[identity.clone(),identity]})).is_err());
        assert_eq!(restored.identities.len(), 1);
    }
    #[test]
    fn device_identity_reuses_verified_enrollment_and_cancel_consumes_challenge() {
        let profile = profiles::tests::ipad_fixture(1);
        let mut catalog = IdentityCatalog::default();
        catalog
            .action(
                &json!({"action":"create_personal_ipad","name":"Ludo","enrollment":profile.proof}),
            )
            .unwrap();
        assert_eq!(catalog.identities[0].public_key, profile.public_key);
        let mut bad = catalog.identities[0].clone();
        bad.proof["device_signature"] = json!("00".repeat(64));
        assert!(bad.verify().is_err());
        let key = SigningKey::from([31; 32]);
        let address =
            solana_pubkey::Pubkey::new_from_array(VerificationKeyBytes::from(&key).into())
                .to_string();
        catalog.action(&json!({"action":"begin_personal_ledger","name":"Ludo","address":address,"derivation_path":"m/44'/501'/0'"})).unwrap();
        catalog.cancel();
        assert!(
            catalog
                .action(&json!({"action":"finish_personal_ledger","signature_hex":"00".repeat(64)}))
                .is_err()
        );
    }
}
