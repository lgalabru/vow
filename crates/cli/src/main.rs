//! The `vow` command line, shipped inside the Mac app. It prepares review
//! files; it holds no keys and cannot sign or submit a transaction.
use clap::{Parser, Subcommand};
use std::{path::PathBuf, process::ExitCode};

mod mcp;
mod new;

#[derive(Parser)]
#[command(
    name = "vow",
    version,
    about = "Prepare Solana transactions for review in Vow"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Create a .vow review file from a serialized transaction
    New {
        /// The transaction: hex, base64 or a JSON dump; a file holding one
        /// (binary too); or `-` for standard input
        bytes: String,
        /// Network the transaction is for: devnet or mainnet
        #[arg(long, short)]
        chain: String,
        /// Run it in a local fork of the chain and attach the result
        #[arg(long)]
        simulate: bool,
        /// File or directory to write to (default: ./Vow-<digest>.vow)
        #[arg(long, short)]
        output: Option<PathBuf>,
        /// Replace an existing file
        #[arg(long)]
        force: bool,
        /// Print the result as JSON
        #[arg(long)]
        json: bool,
    },
    /// Serve these commands as MCP tools over stdio
    Mcp,
}

fn text(value: &serde_json::Value) -> String {
    value
        .as_str()
        .map(str::to_string)
        .unwrap_or_else(|| value.to_string())
}

fn run(command: Command) -> Result<(), String> {
    match command {
        Command::New {
            bytes,
            chain,
            simulate,
            output,
            force,
            json,
        } => {
            let made = new::create(&new::Request {
                data: new::input(&bytes)?,
                chain,
                simulate,
                output,
                force,
            })?;
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&made).unwrap_or_default()
                );
                return Ok(());
            }
            println!("{}", text(&made["path"]));
            println!("  network       {}", text(&made["chain"]));
            println!("  digest        {}", text(&made["wire_digest"]));
            let signed = if made["signed"] == true {
                "signed"
            } else {
                "unsigned"
            };
            println!("  signatures    {} ({signed})", made["signature_count"]);
            for (index, ix) in made["instructions"]
                .as_array()
                .into_iter()
                .flatten()
                .enumerate()
            {
                let label = if index == 0 { "instructions" } else { "" };
                println!(
                    "  {label:<13} {}  {}",
                    text(&ix["title"]),
                    text(&ix["program"])
                );
            }
            if made["unresolved_lookups"] == true {
                println!("  lookups       address lookup tables are not resolved");
            }
            if simulate {
                let error = &made["simulation_result"]["err"];
                let outcome = if error.is_null() {
                    "succeeded".into()
                } else {
                    format!("failed: {error}")
                };
                println!("  simulation    {outcome}");
            }
            println!("  Review only: nothing was signed or submitted.");
            Ok(())
        }
        Command::Mcp => tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .map_err(|e| e.to_string())?
            .block_on(mcp::serve()),
    }
}

fn main() -> ExitCode {
    match run(Cli::parse().command) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("vow: {error}");
            ExitCode::FAILURE
        }
    }
}
