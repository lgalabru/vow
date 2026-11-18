//! Run a bounded, read-only preparation request through the same API as the apps.
use std::io::Read;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().take(4).collect();
    if args.len() != 3 {
        return Err("Usage: profile_request INPUT.json OUTPUT.json".into());
    }
    let mut input = Vec::new();
    std::fs::File::open(&args[1])?
        .take(9 * 1024 * 1024 + 1)
        .read_to_end(&mut input)?;
    if input.len() > 9 * 1024 * 1024 {
        return Err("Input exceeds 9 MB.".into());
    }
    let result = vow_simulation::profile(&serde_json::from_slice(&input)?)?;
    std::fs::write(&args[2], serde_json::to_vec_pretty(&result)?)?;
    Ok(())
}
