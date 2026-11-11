# Vow interface principles

These rules apply to the entire iPadOS and macOS app, including future screens.
The current architecture and data boundaries are in docs/DESIGN.md.

- Native SwiftUI navigation, controls, menus, focus, sharing and accessibility.
  Share content and interaction components; adapt navigation and hardware services
  at the platform edge. Do not make the iPad resemble a stretched Mac form.
- Use the Vow icon and the adaptive teal accent sampled from its cyan side.
  Accent marks selection and primary actions. Surfaces are neutral system colors.
  Green means a verified condition; red means blocked or failed. No decorative
  multicolor tiles, gradients, giant headers or overlapping fixed bars.
- One page title, one short explanation and one primary action per step.
  Name tasks directly: Members, Quorums, Review request, Authorize, Export.
  Put account paths, protocol details and administrator instructions in disclosures.
- Personal profiles belong to the person. Organization membership is a separate
  ceremony registration; projects select immutable quorum seats. Onboarding never
  asks a person to pick an organization roster entry.
- Use the same profile assistant on first launch and Add Profile. Name, method,
  hardware verification, ready. Method choices sit horizontally when space allows.
- WorkspacePage owns the content width: 860 points on Mac, 760 on iPad, with
  consistent outer margins. Assistants use a 720-point reading width. Use
  24-point grouping and 22-point card corners,
  system text styles and SF Symbols with consistent optical boxes. Follow the
  shared DesignSystem.swift primitives before introducing new values.
- Adapt to portrait, landscape, smaller windows, Dynamic Type and the keyboard.
  Focused inputs retain room; secondary chrome disappears. Keep authorization
  panels side by side where supported. Never hide a required security detail.
- Use one offline pill per signing surface. Reserve its space alongside action
  buttons. Never float a footer over readable content or place a popover anchor
  on an unrelated parent container.
- Hardware discovery is not verified identity. Request radio permissions in the
  relevant step. Show searching, no devices, connecting, on-device confirmation,
  verified and failure states. Bound searches. Let people retry explicitly.
  Backgrounding cancels pending proof state; never retry a PIN or sign automatically.
- Restore public records only after Rust verification. A damaged archive is not an
  empty store. Keys and authorization state never enter a metadata/cloud archive.
- State prototype restrictions once at the relevant decision, accurately. Exported
  rehearsal evidence must not imply an executed Solana transaction.
- Verify changes with native screenshots and interaction tests on iPad mini in
  both orientations, plus Mac builds and shared Rust invariant tests.

- PageHeading is for workspace screens; AssistantHeading is for setup steps.
  EmptyStateCard spans the same column as context cards and notices. A section may
  not pick its own width or float a narrow empty state inside a wider column.
- Keep workspace toolbar utilities at the trailing edge. Do not place overflow
  menus in the principal/center area or create sample data from an export action.

- Settings is for app-level preferences, support and reset. Put signing addresses,
  public keys and public exports under profile details. Do not recreate a legacy
  device/enrollment dashboard in Settings.
- Reset Everything requires an irreversible-action confirmation and deletes the
  local signing identity and all app data. Keychain reset intent is private and
  resumable; imported/public metadata never authorizes key deletion. External
  hardware PINs and keys are outside the reset's scope.
