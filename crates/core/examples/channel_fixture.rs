fn main() -> Result<(), String> {
    let fixture = vow_core::inspection::channel_fixture(vow_core::Chain::Devnet, None, 1)?;
    println!(
        "{}",
        serde_json::to_string_pretty(&fixture).map_err(|e| e.to_string())?
    );
    Ok(())
}
