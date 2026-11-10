//! Bounded transaction capture and review-only files. No network or execution authority.
use crate::{Proposal, Session, digest, short_name, text, workspace_id};
use bincode::Options;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use solana_transaction::versioned::VersionedTransaction;

pub const FILE_FORMAT: &str = "vow.prototype.transaction.v1";
const SYSTEM_PROGRAM: &str = "11111111111111111111111111111111";
const SQUADS_PROGRAM: &str = "SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf";

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TransactionIntent {
    pub transaction_hex: String,
    pub source_origin: String,
    pub chain: String,
    pub require_security_key: bool,
    pub require_app_attest: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub blockhash_context: Option<crate::inspection::BlockhashContext>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reproduction: Option<vow_replay::ReproductionBundle>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub idls: Vec<crate::metadata::IdlArtifact>,
}
#[derive(Clone)]
pub(crate) struct CapturedTransaction {
    id: String,
    intent: TransactionIntent,
}
#[derive(Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct PlanStep {
    pub id: String,
    pub title: String,
    pub stage: String,
    pub state: String,
    pub detail: String,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TransactionFile {
    format: String,
    purpose: String,
    proposal: Proposal,
    action_digest: String,
    execution_plan: Vec<PlanStep>,
}
#[derive(Serialize)]
pub struct DecodedTransfer {
    pub source: String,
    pub recipient: String,
    pub lamports: u64,
    pub wire_digest: String,
    pub action_digest: String,
    pub version: String,
}

// Construct a canonical, unsigned legacy transaction for the bundled playground.
// This key is public demo data, not a provisioned wallet or treasury authority.
pub fn fixture_transaction() -> Vec<u8> {
    let mut bytes = vec![1];
    bytes.extend_from_slice(&[0; 64]);
    bytes.extend_from_slice(&[1, 0, 1, 3]);
    bytes.extend_from_slice(&[9; 32]);
    bytes.extend_from_slice(&[7; 32]);
    bytes.extend_from_slice(&[0; 32]);
    bytes.extend_from_slice(&[4; 32]);
    bytes.extend_from_slice(&[1, 2, 2, 0, 1, 12]);
    bytes.extend_from_slice(&2u32.to_le_bytes());
    bytes.extend_from_slice(&250_000_000u64.to_le_bytes());
    bytes
}
pub fn decode(intent: &TransactionIntent) -> Result<DecodedTransfer, String> {
    if !["solana:devnet", "solana:mainnet"].contains(&intent.chain.as_str())
        || intent.transaction_hex.len() > 2464
        || intent.source_origin.len() > 256
        || intent.source_origin.chars().any(char::is_control)
        || !(intent.source_origin.starts_with("https://")
            || intent.source_origin == "vow-demo://playground")
    {
        return Err(
            "Choose a supported transaction on the project network, from an HTTPS page or the Vow playground."
                .into(),
        );
    }
    let bytes =
        hex::decode(&intent.transaction_hex).map_err(|_| "Cannot read transaction bytes.")?;
    let tx: VersionedTransaction = bincode::DefaultOptions::new()
        .with_fixint_encoding()
        .with_limit(1232)
        .reject_trailing_bytes()
        .deserialize(&bytes)
        .map_err(|_| "Unsupported or malformed Solana transaction.")?;
    tx.sanitize()
        .map_err(|_| "The transaction has invalid account or instruction indices.")?;
    if bincode::serialize(&tx).map_err(|_| "Cannot encode transaction.")? != bytes {
        return Err("The transaction encoding is not canonical.".into());
    }
    let header = tx.message.header();
    let keys = tx.message.static_account_keys();
    if tx.signatures.len() != 1
        || tx
            .signatures
            .iter()
            .any(|s| s.as_ref().iter().any(|b| *b != 0))
        || header.num_required_signatures != 1
        || header.num_readonly_signed_accounts != 0
        || header.num_readonly_unsigned_accounts != 1
        || keys.len() != 3
        || tx
            .message
            .address_table_lookups()
            .is_some_and(|tables| !tables.is_empty())
    {
        return Err(
            "This preview accepts one unsigned transfer without extra signers or address lookups."
                .into(),
        );
    }
    if keys[0].as_ref() != [9; 32]
        || keys[0] == keys[1]
        || keys[1] == keys[2]
        || keys[2].to_string() != SYSTEM_PROGRAM
    {
        return Err(
            "The transaction does not use Vow’s preview account and the System Program.".into(),
        );
    }
    let instructions = tx.message.instructions();
    if instructions.len() != 1 {
        return Err("Only a single System Program transfer is supported in this preview. No instructions were ignored.".into());
    }
    let ix = &instructions[0];
    if ix.program_id_index != 2
        || ix.accounts != [0, 1]
        || ix.data.len() != 12
        || ix.data[..4] != 2u32.to_le_bytes()
    {
        return Err("This instruction is not a supported SOL transfer.".into());
    }
    let lamports = u64::from_le_bytes(
        ix.data[4..12]
            .try_into()
            .map_err(|_| "Invalid transfer amount.")?,
    );
    if lamports == 0 || lamports > 100_000_000_000 {
        return Err("Choose a preview transfer between 1 lamport and 100 SOL.".into());
    }
    let action = json!({"domain":"vow.prototype.sol-transfer.v1","chain":intent.chain,
        "program":SYSTEM_PROGRAM,"source":keys[0].to_string(),"recipient":keys[1].to_string(),"lamports":lamports});
    Ok(DecodedTransfer {
        source: keys[0].to_string(),
        recipient: keys[1].to_string(),
        lamports,
        wire_digest: digest(&bytes),
        action_digest: digest(&crate::canonical_bytes(&action)),
        version: if tx.message.address_table_lookups().is_some() {
            "v0"
        } else {
            "legacy"
        }
        .into(),
    })
}
pub fn plan(intent: &TransactionIntent) -> Vec<PlanStep> {
    let mut steps = vec![
        PlanStep {id:"member_signatures".into(), title:"Verify member signatures".into(),stage:"Outer transaction".into(),state:"planned".into(),
            detail:"P-256 verification instructions are assembled after offline approvals arrive. Precompiles cannot run as Squads vault CPI instructions.".into()},
        PlanStep {id:"attestation_guard".into(),title:"Enforce quorum and attestation policy".into(),stage:"Execution guard".into(),state:"not_installed".into(),
            detail:"Bind organization, project, action digest, member keys, policy epoch and one-use nonce. The guard must be an unavoidable execution authority.".into()},
    ];
    if intent.require_security_key {
        steps.push(PlanStep {id:"security_key".into(),title:"Verify security-key evidence".into(),stage:"Execution guard".into(),state:"not_implemented".into(),
            detail:"A registered key must authenticate the same approval. This prototype cannot produce or verify that evidence.".into()});
    }
    if intent.require_app_attest {
        steps.push(PlanStep {id:"app_attest".into(),title:"Verify app provenance evidence".into(),stage:"Enrollment / assertion verifier".into(),state:"not_implemented".into(),
            detail:"App Attest needs authenticated enrollment and assertion validation. A transaction flag or App Store signature is not a substitute.".into()});
    }
    steps.push(PlanStep {id:"squads_execute".into(),title:"Execute the approved Squads proposal".into(),stage:"Squads CPI".into(),state:"not_submitted".into(),
        detail:format!("Target program {SQUADS_PROGRAM}. No multisig/vault binding or guard deployment has been configured in this preview.")});
    steps
}
impl TransactionIntent {
    pub(crate) fn validate_proposal(&self, proposal: &Proposal) -> Result<(), String> {
        let decoded = decode(self)?;
        if let Some(context) = &self.blockhash_context {
            let bytes = hex::decode(&self.transaction_hex).map_err(|_| "Invalid wire bytes.")?;
            context.validate(
                &crate::inspection::transaction(&bytes)?
                    .message
                    .recent_blockhash()
                    .to_string(),
                proposal.chain,
            )?;
        }
        if self.idls.len() > 8 {
            return Err("Too many program IDLs.".into());
        }
        let mut programs = std::collections::HashSet::new();
        for idl in &self.idls {
            if !programs.insert(&idl.program) {
                return Err("Duplicate program IDL artifact.".into());
            }
            idl.validate(proposal.chain)?;
        }
        if let Some(bundle) = &self.reproduction {
            if bundle.target_chain != self.chain {
                return Err("The replay target does not match the project network.".into());
            }
            bundle.verify(
                &self.transaction_hex,
                &[decoded.source.clone(), decoded.recipient.clone()],
            )?;
        }
        if self.chain != proposal.chain.wallet_id()
            || proposal.asset != "SOL"
            || proposal.amount != decoded.lamports
            || proposal.recipient != decoded.recipient
        {
            return Err(
                "The displayed transfer does not match the captured transaction bytes.".into(),
            );
        }
        Ok(())
    }
}
impl TransactionFile {
    pub(crate) fn into_proposal(self) -> Result<Proposal, String> {
        let intent = self
            .proposal
            .transaction_intent
            .as_ref()
            .ok_or("Missing captured transaction.")?;
        let decoded = decode(intent)?;
        if self.format != FILE_FORMAT
            || self.purpose != "rehearsal_only"
            || self.action_digest != decoded.action_digest
            || self.execution_plan != plan(intent)
        {
            return Err(
                "The transaction file has a mismatched action or verification plan.".into(),
            );
        }
        intent.validate_proposal(&self.proposal)?;
        Ok(self.proposal)
    }
}
impl Session {
    pub(crate) fn browser_fixture(&self) -> Result<Value, String> {
        let intent = TransactionIntent {
            transaction_hex: hex::encode(fixture_transaction()),
            source_origin: "vow-demo://playground".into(),
            chain: self.active_chain()?.wallet_id().into(),
            require_security_key: false,
            require_app_attest: false,
            blockhash_context: None,
            reproduction: None,
            idls: vec![],
        };
        let decoded = decode(&intent)?;
        Ok(
            json!({"transaction_hex":intent.transaction_hex,"account":decoded.source,"account_hex":hex::encode([9;32]),"chain":intent.chain,
            "organization_id":self.organization_id,"project_id":self.project_id,"quorum_digest":self.active_quorum()?.digest(&self.organization_id)}),
        )
    }
    pub(crate) fn capture_transaction(&mut self, request: &Value) -> Result<Value, String> {
        self.active_quorum()?;
        let intent = TransactionIntent {
            transaction_hex: text(request, "transaction_hex")?.into(),
            source_origin: text(request, "source_origin")?.into(),
            chain: text(request, "chain")?.into(),
            require_security_key: false,
            require_app_attest: false,
            blockhash_context: None,
            reproduction: None,
            idls: vec![],
        };
        if intent.chain != self.active_chain()?.wallet_id() {
            return Err("The dapp network does not match this project.".into());
        }
        let decoded = decode(&intent)?;
        let id = workspace_id("draft")?;
        self.changed();
        self.captured_transaction = Some(CapturedTransaction {
            id: id.clone(),
            intent: intent.clone(),
        });
        Ok(
            json!({"id":id,"transaction_hex":intent.transaction_hex,"transfer":decoded,"source_origin":intent.source_origin,"chain":intent.chain,
            "organization_id":self.organization_id,"project_id":self.project_id,"quorum_digest":self.active_quorum()?.digest(&self.organization_id)}),
        )
    }
    pub(crate) fn refresh_transaction_blockhash(
        &mut self,
        request: &Value,
    ) -> Result<Value, String> {
        let captured = self
            .captured_transaction
            .as_ref()
            .ok_or("Capture a transaction again.")?
            .clone();
        if text(request, "id")? != captured.id {
            return Err("The transaction changed. Review it again.".into());
        }
        let context: crate::inspection::BlockhashContext =
            serde_json::from_value(request["blockhash_context"].clone())
                .map_err(|_| "Invalid blockhash context.")?;
        context.validate(&context.blockhash, self.active_chain()?)?;
        context.require_local_window()?;
        decode(&captured.intent)?;
        let bytes = hex::decode(&captured.intent.transaction_hex)
            .map_err(|_| "Invalid transaction bytes.")?;
        let mut tx = crate::inspection::transaction(&bytes)?;
        let hash = context
            .blockhash
            .parse()
            .map_err(|_| "Invalid recent blockhash.")?;
        tx.message.set_recent_blockhash(hash);
        let wire = bincode::serialize(&tx).map_err(|_| "Cannot encode refreshed transaction.")?;
        let mut result=self.capture_transaction(&json!({"transaction_hex":hex::encode(wire),"source_origin":captured.intent.source_origin,"chain":captured.intent.chain}))?;
        result["blockhash_context"] =
            serde_json::to_value(&context).map_err(|_| "Cannot encode blockhash context.")?;
        self.captured_transaction
            .as_mut()
            .ok_or("Capture changed.")?
            .intent
            .blockhash_context = Some(context);
        Ok(result)
    }
    pub(crate) fn prepare_transaction_file(&self, request: &Value) -> Result<Value, String> {
        let captured = self
            .captured_transaction
            .as_ref()
            .ok_or("Capture a transaction again.")?;
        if text(request, "id")? != captured.id {
            return Err("This preparation session changed. Capture the transaction again.".into());
        }
        let mut intent = captured.intent.clone();
        intent.require_security_key = request["require_security_key"]
            .as_bool()
            .ok_or("Choose the security-key policy.")?;
        intent.idls = if request["idls"].is_null() {
            vec![]
        } else {
            serde_json::from_value(request["idls"].clone()).map_err(|_| "Invalid IDL artifacts.")?
        };
        intent.reproduction = if request["reproduction"].is_null() {
            None
        } else {
            Some(
                serde_json::from_value(request["reproduction"].clone())
                    .map_err(|_| "Invalid reproduction bundle.")?,
            )
        };
        if !request["blockhash_context"].is_null() {
            intent.blockhash_context = Some(
                serde_json::from_value(request["blockhash_context"].clone())
                    .map_err(|_| "Invalid blockhash observation.")?,
            );
        }
        intent.require_app_attest = request["require_app_attest"]
            .as_bool()
            .ok_or("Choose the provenance policy.")?;
        let decoded = decode(&intent)?;
        let quorum = self.active_quorum()?;
        let proposal = Proposal {
            format: crate::PROPOSAL_FORMAT.into(),
            id: captured.id.clone(),
            organization: self.organization.clone(),
            organization_id: self.organization_id.clone(),
            project_id: self.project_id.clone(),
            chain: self.active_chain()?,
            genesis_hash: self.active_chain()?.genesis_hash().into(),
            quorum_id: quorum.id.clone(),
            quorum_digest: quorum.digest(&self.organization_id),
            title: "SOL transfer".into(),
            amount: decoded.lamports,
            asset: "SOL".into(),
            recipient_name: "Unverified destination".into(),
            recipient: decoded.recipient.clone(),
            network: "Local demonstration".into(),
            note: "Captured transaction for offline rehearsal. No transaction has been submitted."
                .into(),
            transaction_intent: Some(intent.clone()),
            demo_expires_at_unix_ms: None,
        };
        proposal.validate(
            &self.organization,
            &self.organization_id,
            &self.project_id,
            self.active_quorum()?,
            self.active_chain()?,
        )?;
        let proposal_digest = proposal.digest();
        let execution_plan = plan(&intent);
        let file = TransactionFile {
            format: FILE_FORMAT.into(),
            purpose: "rehearsal_only".into(),
            proposal,
            action_digest: decoded.action_digest.clone(),
            execution_plan: execution_plan.clone(),
        };
        let package =
            serde_json::to_string_pretty(&file).map_err(|_| "Cannot encode transaction file.")?;
        if package.len() > 8 * 1024 * 1024 {
            return Err("The prepared file exceeds the 8 MB import limit.".into());
        }
        let project = self
            .projects
            .iter()
            .find(|p| p.id == self.project_id)
            .ok_or("Select a project.")?;
        short_name(&project.name)?;
        Ok(
            json!({"id":captured.id,"filename":format!("Vow-{}.vow",&proposal_digest[..12]),"package":package,
            "proposal_digest":proposal_digest,"transfer":decoded,"execution_plan":execution_plan,
            "execution_ready":false,"organization":self.organization,"project":project.name,"quorum":quorum}),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn intent() -> TransactionIntent {
        TransactionIntent {
            transaction_hex: hex::encode(fixture_transaction()),
            source_origin: "vow-demo://playground".into(),
            chain: "solana:devnet".into(),
            require_security_key: false,
            require_app_attest: false,
            blockhash_context: None,
            reproduction: None,
            idls: vec![],
        }
    }
    #[test]
    fn decodes_canonical_unsigned_transfer_and_rejects_trailing_signed_or_changed_instructions() {
        let i = intent();
        assert_eq!(decode(&i).unwrap().lamports, 250_000_000);
        for offset in [1, 69, 205] {
            let mut bytes = fixture_transaction();
            if offset < bytes.len() {
                bytes[offset] ^= 1;
            }
            let mut altered = i.clone();
            altered.transaction_hex = hex::encode(bytes);
            assert!(decode(&altered).is_err());
        }
        let mut extra = i.clone();
        extra.transaction_hex.push_str("00");
        assert!(decode(&extra).is_err());
    }
    #[test]
    fn captures_and_imports_are_bound_to_project_chain_and_genesis() {
        let mut s = Session::default();
        let i = intent();
        s.dispatch(&json!({"action":"select_project","id":"project-operations"}))
            .unwrap();
        assert_eq!(
            s.dispatch(&json!({"action":"browser_fixture"})).unwrap()["chain"],
            "solana:mainnet"
        );
        assert!(s.capture_transaction(&json!({"transaction_hex":i.transaction_hex,"source_origin":i.source_origin,"chain":"solana:devnet"})).is_err());
        let cap = s.capture_transaction(&json!({"transaction_hex":i.transaction_hex,"source_origin":i.source_origin,"chain":"solana:mainnet"})).unwrap();
        let file = s
            .prepare_transaction_file(
                &json!({"id":cap["id"],"require_security_key":false,"require_app_attest":false}),
            )
            .unwrap();
        s.dispatch(&json!({"action":"import","data":file["package"]}))
            .unwrap();
        let mut bad: Value = serde_json::from_str(file["package"].as_str().unwrap()).unwrap();
        bad["proposal"]["genesis_hash"] = json!(crate::Chain::Devnet.genesis_hash());
        assert!(
            s.dispatch(&json!({"action":"import","data":bad.to_string()}))
                .is_err()
        );
        s.dispatch(&json!({"action":"select_project","id":"project-grants"}))
            .unwrap();
        assert!(
            s.dispatch(&json!({"action":"import","data":file["package"]}))
                .is_err()
        );
    }
    #[test]
    fn refreshing_blockhash_preserves_action_but_invalidates_old_capture_and_binds_context() {
        let mut session = Session::default();
        let input = intent();
        let captured=session.capture_transaction(&json!({"transaction_hex":input.transaction_hex,"source_origin":input.source_origin,"chain":input.chain})).unwrap();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;
        let hash = solana_pubkey::Pubkey::new_from_array([5; 32]).to_string();
        let context = json!({"blockhash":hash,"chain":"solana:devnet","genesis_hash":crate::Chain::Devnet.genesis_hash(),"observed_at_unix_ms":now,"context_slot":1,"observed_block_height":100,"last_valid_block_height":250,"estimated_expires_at_unix_ms":now+60_000});
        let refreshed = session
            .refresh_transaction_blockhash(
                &json!({"id":captured["id"],"blockhash_context":context}),
            )
            .unwrap();
        assert_ne!(refreshed["transaction_hex"], captured["transaction_hex"]);
        assert_eq!(
            refreshed["transfer"]["action_digest"],
            captured["transfer"]["action_digest"]
        );
        assert!(session.prepare_transaction_file(&json!({"id":captured["id"],"require_security_key":false,"require_app_attest":false})).is_err());
        let file=session.prepare_transaction_file(&json!({"id":refreshed["id"],"require_security_key":false,"require_app_attest":false})).unwrap();
        let parsed: Value = serde_json::from_str(file["package"].as_str().unwrap()).unwrap();
        assert_eq!(
            parsed["proposal"]["transaction_intent"]["blockhash_context"],
            context
        );
        let mut wrong = context.clone();
        wrong["chain"] = json!("solana:mainnet");
        assert!(
            session
                .refresh_transaction_blockhash(
                    &json!({"id":refreshed["id"],"blockhash_context":wrong})
                )
                .is_err()
        );
    }
    #[test]
    fn file_roundtrip_redecodes_bytes_and_binds_requirements() {
        let mut s = Session::default();
        let i = intent();
        let cap=s.capture_transaction(&json!({"transaction_hex":i.transaction_hex,"source_origin":i.source_origin,"chain":i.chain})).unwrap();
        let file = s
            .prepare_transaction_file(
                &json!({"id":cap["id"],"require_security_key":true,"require_app_attest":false}),
            )
            .unwrap();
        let p: TransactionFile = serde_json::from_str(file["package"].as_str().unwrap()).unwrap();
        let p = p.into_proposal().unwrap();
        assert!(p.transaction_intent.unwrap().require_security_key);
        let mut bad: Value = serde_json::from_str(file["package"].as_str().unwrap()).unwrap();
        bad["proposal"]["amount"] = json!(1);
        assert!(
            serde_json::from_value::<TransactionFile>(bad)
                .unwrap()
                .into_proposal()
                .is_err()
        );
        let mut bad: Value = serde_json::from_str(file["package"].as_str().unwrap()).unwrap();
        bad["execution_plan"][1]["state"] = json!("verified");
        assert!(
            serde_json::from_value::<TransactionFile>(bad)
                .unwrap()
                .into_proposal()
                .is_err()
        );
    }
}
