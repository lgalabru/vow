//! Replay a prepared review request locally. This example never submits to a chain.
fn main() {
    let path = std::env::args().nth(1).expect("request JSON path");
    let package = std::fs::read_to_string(path).expect("request JSON");
    let value: serde_json::Value = serde_json::from_str(&package).expect("request object");
    let result = vow_simulation::profile(
        &serde_json::json!({"mode":"offline","package":package,"chain":value["chain"]}),
    )
    .expect("offline snapshot profile");
    let out = std::env::args().nth(2).expect("output JSON path");
    std::fs::write(out, serde_json::to_vec_pretty(&result).unwrap()).unwrap();
}
