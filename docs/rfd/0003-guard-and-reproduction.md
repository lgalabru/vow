# RFD 0003: Unavoidable attestation enforcement and reproducible review

State: discussion
Authors: Vow contributors · Started: 2026-11-09

## Problem

A coordinator can add an attestation instruction and then omit it from another
transaction. A valid simulation can also use invented account state. We need to
specify what the chain enforces, what an offline replay establishes, and what
expires while members review a persistent multisig action.

## Sketch

Make an audited guard PDA the sole Squads Execute authority. The coordinator has
Initiate only. A separate reviewed bridge maps enrolled P-256 keys to voting
identities. The outer transaction verifies cryptographic evidence, invokes the
guard, and the guard atomically invokes Squads execution with its PDA signature.
Precompiles belong in the outer transaction because Squads invokes stored vault
instructions through CPI. Merely putting an optional check before execution is
insufficient.

The guard must derive the actual stored vault action and bind the deployment,
network/genesis domain, organization, project, multisig/vault, quorum policy epoch,
member keys, action digest and one-use nonce. Check current policy at execution,
not only when a vote was recorded. Required provenance and hardware-factor
assertions need real registered-key verifiers. A boolean flag is not evidence.
Ordinary Execute members, spending limits, config authority, recovery, upgrades
and batch execution must not offer an alternate unguarded path. Configuration
maintenance also needs an authorized path so exclusive guard execution does not
make the multisig impossible to maintain.

Different project thresholds cannot be display tags over one Squads account's
global threshold. Specify separate multisigs/vaults and authority relationships,
or a reviewed policy mechanism that genuinely enforces those differences.

The Mac can package a profile, complete pre-state dependencies and IDLs. The iPad
independently decodes the wire bytes and reruns an approved runtime. Matching
results establish only equivalence relative to those inputs. They do not prove
that those inputs were current chain state or guarantee future results. Real
program support requires program/program-data bytes, sysvars, time, feature set,
lookup resolution, account absence and dependency closure to be defined and pinned.
A downloaded executable needs an explicit trust and resource policy.

The first implemented reproduction profile is a synthetic SOL transfer. The
embedded SDK's `sendTransaction` disables signature verification and blockhash
checking in an isolated offline fork. Its default instruction profiling records
an executed transaction, permitting `surfnet_exportSnapshot` with `preTransaction`.
`surfnet_profileTransaction` returns a UUID and explicitly checks signatures, so
it cannot directly profile the unsigned draft used here. SDK result balances are
compared with an independent LiteSVM execution. No public submission occurs.

Payment Channels `open` is an authority grant and token deposit. `distribute` is
permissionless and calculates cumulative deltas from channel state. State must
supply settled and payout watermarks, status, escrow and token-account details.
Unusable canonical payout accounts may redirect amounts to treasury. An IDL or
instruction dump alone cannot establish precise payouts. The implemented native
inspector displays these limits and cannot sign channel transactions.

## Blockhash lifetime

A recent blockhash expires by block height. RPC `getLatestBlockhash` returns
`lastValidBlockHeight`; it does not return the blockhash's creation timestamp.
Capture observation time, context slot and observed height, check the RPC genesis,
and bind these fields to the exact wire hash. Offline time can display an estimate,
not establish validity. The UI estimates 400 ms per remaining block and caps the
local window at 60 seconds. It labels missing context, expired estimates and clock
anomalies rather than inventing freshness. Coordinator timestamps remain claims.

A persistent Squads vault action does not inherit the original dapp transaction's
recent blockhash expiry. Votes and final execution need fresh outer transactions.
Durable nonce transactions need a separate decoder and nonce-state policy. P-256
bridge authorization may have its own recent-slot-hash deadline. Show these
separately. Never promise an offline approval remains usable solely because a
countdown is green.

## Open questions

- Which exact bridge route supports delayed P-256 votes? Prove registration,
  vote, threshold, timelock and guarded execution together on a local validator.
- Can the guard inspect and bind every supported Squads vault/batch message without
  ambiguity? Build adversarial fixtures against the pinned program.
- How will policy updates invalidate earlier approvals and allow safe maintenance?
  Test stale proposals, guard replacement, membership changes and recovery.
- How is snapshot state authenticated and dated? Define the trust model before
  using replay as a policy gate for real funds.
- Which channel actions are initially supported? Replay open and distribute against
  the actual pinned SBF binary and verified token/account fixtures, including
  redirection and token-extension cases.
- Can provenance assertions be generated offline and verified under the selected
  on-chain/off-chain trust boundary? Test Apple enrollment and assertion behavior
  on physical devices before claiming it.

## Risks

Exclusive execution authority can deadlock maintenance if the config path is not
specified. Upgradeable programs can change enforcement. State exports can omit
important dependencies or invent balances. Arbitrary SBF execution increases the
offline signer's attack surface. A plausible timer or native dialog can create
false confidence if it hides the distinction between a raw transaction, a stored
multisig action, an approval and an actual executed transaction.

## What we learned

2026-11-09: Squads intentionally allows execution of already approved stale
proposals. Its separate `spending_limit_use` path does not require proposal voting.
Therefore execution-time epoch checks and authority-graph review are mandatory.
The client kits help with wrapping and account resolution, but do not implement
Vow policy or prove P-256 end-to-end compatibility. Source revisions and links are
in [RESEARCH.md](../RESEARCH.md).

2026-11-09: The prototype now executes the synthetic transfer through the embedded
SDK, exports pre-state, reproduces independently and imports/replays the package.
Actual Payment Channels ABI inspection and canonical-address fixture construction
are implemented separately. No Vow guard program has been created, deployed or
represented by a fake instruction in a channel transaction.

Payment Channels also imposes an action-specific lifetime: `open_slot` must be at
most 1,500 slots old and cannot be in the future. It is a channel PDA seed. A
long-running multisig ceremony can therefore invalidate an opening even after
refreshing the outer blockhash. Refreshing `open_slot` changes the channel address
and action and requires renewed approval. This is distinct from recent-blockhash
expiry and must be reviewed before selecting a delayed multisig workflow.
