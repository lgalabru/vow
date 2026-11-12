//! `vow new`: a review file from a serialized transaction. Shared by the
//! command line and the MCP tool. Nothing here signs or submits.
use serde_json::{Value, json};
use std::{
    io::{Read, Write},
    path::{Path, PathBuf},
};

/// The largest input the inspector takes for a container with fixtures.
const MAX_INPUT: u64 = 8 * 1024 * 1024;

pub struct Request {
    /// Hex, base64 or a JSON transaction dump.
    pub data: String,
    /// `devnet` or `mainnet`; never inferred from the bytes.
    pub chain: String,
    /// Run the transaction in a local fork of the chain and attach the result.
    pub simulate: bool,
    /// File or directory to write to. Defaults to the working directory.
    pub output: Option<PathBuf>,
    pub force: bool,
}

/// Read `<bytes>` from the command line: `-` is stdin, an existing path is
/// that file, anything else is the transaction text itself.
pub fn input(argument: &str) -> Result<String, String> {
    let bytes = if argument == "-" {
        let mut bytes = vec![];
        std::io::stdin()
            .take(MAX_INPUT + 1)
            .read_to_end(&mut bytes)
            .map_err(|e| format!("Cannot read standard input: {e}"))?;
        bytes
    } else if Path::new(argument).is_file() {
        let size = std::fs::metadata(argument).map(|m| m.len()).unwrap_or(0);
        if size > MAX_INPUT {
            return Err(format!("{argument} exceeds the 8 MB review-file limit."));
        }
        std::fs::read(argument).map_err(|e| format!("Cannot read {argument}: {e}"))?
    } else {
        argument.as_bytes().to_vec()
    };
    if bytes.len() as u64 > MAX_INPUT {
        return Err("The input exceeds the 8 MB review-file limit.".into());
    }
    // A binary dump becomes hex, as it does when the apps import one.
    Ok(match String::from_utf8(bytes) {
        Ok(text) => text.trim().to_string(),
        Err(binary) => hex::encode(binary.as_bytes()),
    })
}

fn chain_id(chain: &str) -> Result<&'static str, String> {
    match chain {
        "devnet" | "solana:devnet" => Ok("solana:devnet"),
        "mainnet" | "mainnet-beta" | "solana:mainnet" => Ok("solana:mainnet"),
        _ => Err("Choose a network: devnet or mainnet.".into()),
    }
}

fn simulate(request: &Value) -> Result<Value, String> {
    #[cfg(target_os = "macos")]
    {
        vow_simulation::clipboard::profile(request)
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = request;
        Err("Simulation is available on Mac only.".into())
    }
}

/// Inspect the transaction, write its `.vow` file and describe what was
/// written. The file is inspection-only: it carries no approval.
pub fn create(request: &Request) -> Result<Value, String> {
    let input = json!({"chain": chain_id(&request.chain)?, "data": request.data});
    let (_, inspected) = vow_simulation::clipboard::inspect_request(&input)?;
    let digest = inspected["id"].as_str().ok_or("Missing digest.")?;
    let (package, simulation) = if request.simulate {
        let profiled = simulate(&input)?;
        let package = profiled["package"].as_str().map(str::to_string);
        (package, profiled["simulation"]["result"].clone())
    } else {
        (
            inspected["package"].as_str().map(str::to_string),
            Value::Null,
        )
    };
    let package = package.ok_or("Missing review container.")?;

    let name = format!("Vow-{}.vow", &digest[..12]);
    let path = match &request.output {
        Some(path) if path.is_dir() => path.join(name),
        Some(path) => path.clone(),
        None => PathBuf::from(name),
    };
    let mut options = std::fs::OpenOptions::new();
    options.write(true);
    if request.force {
        options.create(true).truncate(true);
    } else {
        options.create_new(true);
    }
    let mut file = options.open(&path).map_err(|e| match e.kind() {
        std::io::ErrorKind::AlreadyExists => {
            format!("{} already exists; nothing was written.", path.display())
        }
        _ => format!("Cannot write {}: {e}", path.display()),
    })?;
    file.write_all(package.as_bytes())
        .map_err(|e| format!("Cannot write {}: {e}", path.display()))?;
    let path = std::fs::canonicalize(&path).unwrap_or(path);

    let instructions = inspected["instructions"]
        .as_array()
        .map(|all| {
            all.iter()
                .map(|ix| json!({"title": ix["title"], "program": ix["program"]}))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Ok(json!({
        "path": path,
        "wire_digest": digest,
        "chain": inspected["chain"]["id"],
        "blockhash": inspected["blockhash"],
        "signature_count": inspected["signature_count"],
        "signed": inspected["signed"],
        "unresolved_lookups": inspected["unresolved_lookups"],
        "instructions": instructions,
        "simulated": request.simulate,
        "simulation_result": simulation,
        "execution_ready": false,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(dir: &Path, data: String) -> Request {
        Request {
            data,
            chain: "devnet".into(),
            simulate: false,
            output: Some(dir.to_path_buf()),
            force: false,
        }
    }

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("vow-cli-{name}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn writes_a_file_the_inspector_reads_back() {
        let dir = scratch("roundtrip");
        let wire = hex::encode(vow_core::transaction::fixture_transaction());
        let made = create(&request(&dir, wire.clone())).unwrap();
        let path = PathBuf::from(made["path"].as_str().unwrap());
        assert_eq!(path.extension().unwrap(), "vow");
        assert_eq!(made["execution_ready"], false);

        // The written container is itself a valid input, for the same bytes.
        let again = input(path.to_str().unwrap()).unwrap();
        let (_, inspected) = vow_simulation::clipboard::inspect_request(
            &json!({"chain": "solana:devnet", "data": again}),
        )
        .unwrap();
        assert_eq!(inspected["transaction_hex"], wire);
        assert_eq!(inspected["id"], made["wire_digest"]);

        // Never replaced silently, and never accepted for another network.
        assert!(create(&request(&dir, wire.clone())).is_err());
        let mut other = request(&dir, again);
        other.chain = "mainnet".into();
        assert!(create(&other).is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn binary_dumps_and_bad_input() {
        let dir = scratch("binary");
        let file = dir.join("tx.bin");
        let wire = vow_core::transaction::fixture_transaction();
        std::fs::write(&file, &wire).unwrap();
        assert_eq!(input(file.to_str().unwrap()).unwrap(), hex::encode(&wire));
        assert!(create(&request(&dir, "not a transaction".into())).is_err());
        let mut unknown = request(&dir, hex::encode(&wire));
        unknown.chain = "testnet".into();
        assert!(create(&unknown).is_err());
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 1);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
