//! Presentation-only state transitions from one recorded SDK execution.
use base64::Engine;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};

pub fn report(raw: &Value, parsed: &Value) -> Value {
    let raw = &raw["value"];
    let parsed = &parsed["value"];
    let readonly = &raw["readonlyAccountStates"];
    let readonly_parsed = &parsed["readonlyAccountStates"];
    let transaction = transitions(
        &raw["transactionProfile"],
        &parsed["transactionProfile"],
        readonly,
        readonly_parsed,
    );
    let instructions: Vec<Value> = raw["instructionProfiles"]
        .as_array()
        .into_iter()
        .flatten()
        .enumerate()
        .map(|(index, profile)| {
            transitions(
                profile,
                &parsed["instructionProfiles"][index],
                readonly,
                readonly_parsed,
            )
        })
        .collect();
    json!({"transaction":transaction,"instructions":instructions})
}
fn transitions(raw: &Value, parsed: &Value, readonly: &Value, readonly_parsed: &Value) -> Value {
    let Some(states) = raw["accountStates"].as_object() else {
        return json!([]);
    };
    let mut output = Vec::with_capacity(states.len());
    for (address, state) in states {
        let kind = state["accountChange"]["type"]
            .as_str()
            .unwrap_or("readonly");
        let (before, after) = pair(state, &readonly[address]);
        let (parsed_before, parsed_after) =
            pair(&parsed["accountStates"][address], &readonly_parsed[address]);
        let before_bytes = raw_bytes(before);
        let after_bytes = raw_bytes(after);
        let data_changed = before_bytes != after_bytes;
        let before_lamports = before.and_then(|v| v["lamports"].as_u64()).unwrap_or(0);
        let after_lamports = after.and_then(|v| v["lamports"].as_u64()).unwrap_or(0);
        let lamports_delta = (i128::from(after_lamports) - i128::from(before_lamports)).to_string();
        let before = normalize(before, parsed_before);
        let after = normalize(after, parsed_after);
        let mut old = BTreeMap::new();
        let mut new = BTreeMap::new();
        if let Some(before) = &before {
            flatten("", before, &mut old);
        }
        if let Some(after) = &after {
            flatten("", after, &mut new);
        }
        let paths: BTreeSet<_> = old.keys().chain(new.keys()).collect();
        let mut paths: Vec<_> = paths.into_iter().collect();
        paths.sort_by_key(|path| {
            (
                match path.as_str() {
                    "lamports" => 0,
                    "owner" => 1,
                    "executable" => 2,
                    "rentEpoch" => 3,
                    "space" => 4,
                    _ => 5,
                },
                *path,
            )
        });
        let fields: Vec<Value> = paths.into_iter().map(|path| json!({"path":path,"before":old.get(path),"after":new.get(path),"changed":old.get(path)!=new.get(path)})).collect();
        let changed = before != after || data_changed;
        output.push(json!({"id":address,"kind":kind,"data_changed":data_changed,"lamports_delta":lamports_delta,"writable":state["type"]=="writable","changed":changed,"fields":fields,
            "before_state":before.map(|v|serde_json::to_string_pretty(&v).expect("JSON value")),"after_state":after.map(|v|serde_json::to_string_pretty(&v).expect("JSON value"))}));
    }
    output.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    Value::Array(output)
}
fn pair<'a>(state: &'a Value, readonly: &'a Value) -> (Option<&'a Value>, Option<&'a Value>) {
    let data = &state["accountChange"]["data"];
    match state["accountChange"]["type"].as_str() {
        Some("create") => (None, (!data.is_null()).then_some(data)),
        Some("delete") => ((!data.is_null()).then_some(data), None),
        Some("update") => (data.get(0), data.get(1)),
        Some("unchanged") => {
            let data = (!data.is_null()).then_some(data);
            (data, data)
        }
        _ => {
            let data = (!readonly.is_null()).then_some(readonly);
            (data, data)
        }
    }
}
fn raw_bytes(account: Option<&Value>) -> Vec<u8> {
    account
        .and_then(|v| v["data"].as_array())
        .filter(|v| v.len() == 2 && v[1] == "base64")
        .and_then(|v| v[0].as_str())
        .and_then(|v| base64::prelude::BASE64_STANDARD.decode(v).ok())
        .unwrap_or_default()
}
fn normalize(raw: Option<&Value>, parsed: Option<&Value>) -> Option<Value> {
    let raw = raw?;
    // Parsed account data is a view of the same SDK account. Never substitute
    // mismatching metadata from another account or profile.
    let matching = parsed.filter(|parsed| {
        ["lamports", "owner", "executable", "rentEpoch", "space"]
            .iter()
            .all(|key| raw[*key] == parsed[*key])
    });
    let mut value = matching.unwrap_or(raw).clone();
    if let Some(data) = raw["data"]
        .as_array()
        .filter(|data| data.len() == 2 && data[1] == "base64")
    {
        let bytes = base64::prelude::BASE64_STANDARD
            .decode(data[0].as_str().unwrap_or(""))
            .unwrap_or_default();
        if !value["data"].is_object() {
            value["data"] =
                json!({"length":bytes.len(),"sha256":hex::encode(Sha256::digest(&bytes))});
        }
    }
    Some(value)
}
fn flatten(path: &str, value: &Value, output: &mut BTreeMap<String, String>) {
    if path == "data.sha256" {
        return;
    } // Raw changes are displayed as byte diffs, not hash-only rows.
    match value {
        Value::Object(values) if !values.is_empty() => {
            let sorted: BTreeMap<_, _> = values.iter().collect();
            for (key, value) in sorted {
                flatten(
                    &if path.is_empty() {
                        key.to_string()
                    } else {
                        format!("{path}.{key}")
                    },
                    value,
                    output,
                );
            }
        }
        Value::Array(values) if !values.is_empty() => {
            for (index, value) in values.iter().enumerate() {
                flatten(&format!("{path}[{index}]"), value, output);
            }
        }
        _ => {
            output.insert(path.into(), value.to_string());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn account(lamports: u64) -> Value {
        json!({"lamports":lamports,"owner":"owner","executable":false,"rentEpoch":u64::MAX,"space":0,"data":["","base64"]})
    }
    #[test]
    fn field_diffs_preserve_full_u64_precision_and_missing_sides() {
        let before = account(u64::MAX);
        let after = account(u64::MAX - 1);
        let profile = json!({"value":{"transactionProfile":{"accountStates":{
            "updated":{"type":"writable","accountChange":{"type":"update","data":[before,after]}},
            "created":{"type":"writable","accountChange":{"type":"create","data":after}},
            "deleted":{"type":"writable","accountChange":{"type":"delete","data":before}}
        }}}});
        let rows = report(&profile, &Value::Null);
        let updated = rows["transaction"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["id"] == "updated")
            .unwrap();
        let lamports = updated["fields"]
            .as_array()
            .unwrap()
            .iter()
            .find(|f| f["path"] == "lamports")
            .unwrap();
        assert_eq!(lamports["before"], u64::MAX.to_string());
        assert_eq!(lamports["after"], (u64::MAX - 1).to_string());
        assert_eq!(lamports["changed"], true);
        assert!(rows["transaction"][0]["before_state"].is_null());
        assert!(rows["transaction"][1]["after_state"].is_null());
    }
    #[test]
    fn raw_byte_changes_remain_visible_when_parsed_fields_are_equal() {
        let mut before = account(100);
        before["data"] = json!(["AA==", "base64"]);
        let mut after = before.clone();
        after["data"] = json!(["AQ==", "base64"]);
        let raw = json!({"value":{"transactionProfile":{"accountStates":{"token":{"type":"writable","accountChange":{"type":"update","data":[before,after]}}}}}});
        let mut parsed = raw.clone();
        for index in 0..2 {
            parsed["value"]["transactionProfile"]["accountStates"]["token"]["accountChange"]["data"]
                [index]["data"] = json!({"parsed":{"info":{"amount":"1000"}}});
        }
        let result = report(&raw, &parsed);
        assert_eq!(result["transaction"][0]["changed"], true);
        assert_eq!(result["transaction"][0]["data_changed"], true);
    }
    #[test]
    fn parsed_fields_are_diffed_only_for_matching_account_metadata() {
        let raw = json!({"value":{"transactionProfile":{"accountStates":{"token":{"type":"writable","accountChange":{"type":"update","data":[account(100),account(100)]}}}}}});
        let mut parsed = raw.clone();
        parsed["value"]["transactionProfile"]["accountStates"]["token"]["accountChange"]["data"]
            [0]["data"] = json!({"parsed":{"info":{"amount":"1000"}}});
        parsed["value"]["transactionProfile"]["accountStates"]["token"]["accountChange"]["data"]
            [1]["data"] = json!({"parsed":{"info":{"amount":"900"}}});
        let result = report(&raw, &parsed);
        assert!(
            result["transaction"][0]["fields"]
                .as_array()
                .unwrap()
                .iter()
                .any(|v| v["path"] == "data.parsed.info.amount" && v["changed"] == true)
        );
        parsed["value"]["transactionProfile"]["accountStates"]["token"]["accountChange"]["data"]
            [1]["owner"] = json!("other-owner");
        let result = report(&raw, &parsed);
        assert!(
            !result["transaction"][0]["after_state"]
                .as_str()
                .unwrap()
                .contains("900")
        );
    }
}
