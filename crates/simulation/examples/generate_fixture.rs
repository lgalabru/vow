//! Generate a public, synthetic review fixture. Never submits to a public RPC.
use serde_json::json;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args()
        .nth(1)
        .ok_or("Supply an output .vow path")?;
    let mut session = vow_core::Session::default();
    let fixture = session.dispatch(&json!({"action":"browser_fixture"}))?;
    let intent = json!({"transaction_hex":fixture["transaction_hex"],"source_origin":"vow-demo://playground","chain":fixture["chain"],"require_security_key":false,"require_app_attest":false});
    let reproduction = vow_simulation::profile(&json!({"intent":intent}))?;
    let captured = session.dispatch(&json!({"action":"capture_transaction","transaction_hex":fixture["transaction_hex"],"source_origin":"vow-demo://playground","chain":fixture["chain"]}))?;
    let file = session.dispatch(&json!({"action":"prepare_transaction_file","id":captured["id"],"require_security_key":false,"require_app_attest":false,"reproduction":reproduction}))?;
    std::fs::write(path, file["package"].as_str().ok_or("Missing package")?)?;
    Ok(())
}
