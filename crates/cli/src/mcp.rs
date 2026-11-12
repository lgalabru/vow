//! `vow mcp`: the command line's functions as MCP tools over stdio.
use crate::new;
use rmcp::{
    ErrorData, ServerHandler, ServiceExt,
    handler::server::{router::tool::ToolRouter, wrapper::Parameters},
    model::{
        CallToolResult, ContentBlock, Implementation, ProtocolVersion, ServerCapabilities,
        ServerConfig,
    },
    schemars::{self, JsonSchema},
    tool, tool_handler, tool_router,
};
use serde::Deserialize;
use std::path::PathBuf;

const INSTRUCTIONS: &str = "Vow prepares Solana transactions for review on an offline signing \
                            device. `new` turns one serialized transaction into a .vow review \
                            file. The file is inspection-only: creating it signs nothing and \
                            submits nothing, and it carries no approval.";

#[derive(Debug, Deserialize, JsonSchema)]
pub struct NewParams {
    /// One serialized Solana transaction: hex, base64, or a JSON dump
    /// (`transaction_base64`, `transaction_hex`, or an RPC `[base64, "base64"]`).
    pub transaction: String,
    /// `devnet` or `mainnet`. Required: the network is never inferred.
    pub chain: String,
    /// Run the transaction in a local fork of the chain and attach the result
    /// as review evidence. Reads accounts from the public RPC. Mac only.
    #[serde(default)]
    pub simulate: bool,
    /// File or directory to write to. Defaults to the server's working directory.
    #[serde(default)]
    pub output: Option<PathBuf>,
}

pub struct VowMcp {
    tool_router: ToolRouter<Self>,
}

#[tool_router]
impl VowMcp {
    fn new() -> Self {
        Self {
            tool_router: Self::tool_router(),
        }
    }

    #[tool(
        name = "new",
        description = "Create a .vow review file from one serialized Solana transaction and return its path, wire digest and decoded instructions. Existing files are never overwritten. The user opens or sends the file to their signing device; nothing is signed or submitted here."
    )]
    async fn new_file(
        &self,
        Parameters(p): Parameters<NewParams>,
    ) -> Result<CallToolResult, ErrorData> {
        let request = new::Request {
            data: p.transaction.trim().to_string(),
            chain: p.chain,
            simulate: p.simulate,
            output: p.output,
            force: false,
        };
        // Simulation drives its own runtime, so keep it off this one.
        let result = tokio::task::spawn_blocking(move || new::create(&request))
            .await
            .unwrap_or_else(|_| Err("The review file could not be created.".into()));
        Ok(match result {
            Ok(value) => CallToolResult::success(vec![ContentBlock::text(
                serde_json::to_string_pretty(&value).unwrap_or_default(),
            )]),
            Err(error) => CallToolResult::error(vec![ContentBlock::text(error)]),
        })
    }
}

#[tool_handler(router = self.tool_router)]
impl ServerHandler for VowMcp {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build())
            .with_protocol_version(ProtocolVersion::V_2025_06_18)
            .with_server_info(
                Implementation::new("vow", env!("CARGO_PKG_VERSION")).with_title("Vow"),
            )
            .with_instructions(INSTRUCTIONS)
    }
}

/// Serve over stdio until the client disconnects.
pub async fn serve() -> Result<(), String> {
    let service = VowMcp::new()
        .serve((tokio::io::stdin(), tokio::io::stdout()))
        .await
        .map_err(|e| e.to_string())?;
    service
        .waiting()
        .await
        .map(|_| ())
        .map_err(|e| e.to_string())
}
