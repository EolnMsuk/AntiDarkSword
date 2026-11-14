# Changelog

## 4.9.6

- Add PreferenceLoader-only manual stable-release checking beside GitHub. Read
  the installed preferences bundle version, compare numeric version components
  (including published `vX.Y.Z-bN` tags), reject draft/prerelease or malformed
  responses, and validate direct official release links.
- Add silent asynchronous checking only on visible AntiDarkSword settings entry,
  with a durable rolling 24-hour attempt gate that includes failures, serialized
  request coalescing, manual override and weak/visible UIKit presentation. The
  gate counts device sleep; persisted continuous elapsed time protects
  the same-boot gate across Settings relaunches and wall-clock jumps. No
  periodic timer, background updater, automatic download or install is added.
- Consolidate **💸 Donate** into Venmo and Crypto. Use the exact
  `https://venmo.com/EolnMsuk/` destination through a guarded default-browser
  route. **Crypto Wallets** shows all eight exact BTC, ETH, USDT, USDC,
  RNDR / ERC-20, LTC, SOL and BNB entries with network labels, wrapping addresses,
  row-specific copy confirmation and a fixed bottom Cancel. TrollFools receives
  neither feature. Browser routing and UI layout still require device checks.
- Standardize four Debian assets as
  `com.eolnmsuk.antidarksword_<version>_{legacy,rootful,rootless,roothide}.deb` and
  retain `AntiDarkSword_<version>_TrollFools.dylib`. Share target definitions,
  isolate build/staging/reference directories, check package metadata, and derive
  firmware dependencies and staged preferences minimum OS metadata from the
  selected target. Require all five products before creating the stable release
  draft. Include these notes and an
  accurate compatibility guide in the draft; publication remains user-controlled.
- Configure the native Roothide Theos scheme with pinned official toolchain
  inputs, verified native AltList reference/dependencies, typed root-path APIs,
  native signing entitlements, and environment-specific lifecycle/launch paths.
  Vendor originals are preserved. No renamed rootless package or external
  patcher is used; actual native compilation/installation is pending user results.
- Make root `control` the only release-version authority. Synchronize/check
  preferences bundle versions, depiction version and current changelog content.
  Remove the stale runtime fallback and correct the TrollFools release baseline
  and explicit legacy Makefile selection. Legacy linking omits chained fixups.
- Serialize UI/TrollFools reloads and publish complete retained policy snapshots;
  publish daemon flags in one atomic mask. Keep rule precedence, existing gates,
  original hook chains and default master state. Reconcile asynchronously compiled
  blockers with existing content controllers and change only owned scripts/rules.
- Replace Settings' raw observer pointers with weak main-queue notification
  tokens. Run existing explicit process controls on a serial worker with bounded
  waits, error/status handling and restored controls. Keep mobile preference
  paths distinct from package paths and remove untyped root-path symbol calls.
- Validate counter CF types/ranges and saturate additions; cross-process totals
  remain approximate. Preserve original stat/lstat handling for NULL buffers.
- Retain game audio state through active render blocks and pass UI sounds through
  a bounded atomic mailbox. Remove manually freed render-state buffers and direct
  UI/render field races; add allocation/node/start/teardown guards. A full mailbox
  drops an effect instead of blocking the render thread.
- Add the Sileo Changelog tab immediately after Details, preserve other depiction
  content, and update installation/build/project/compatibility documentation with
  source-backed findings, pinned input provenance and exact user validation steps.

**Validation status:** local metadata/reference/source checks are documented in
`docs/local-validation.md`. No package/full build, signing, installation, CI run,
release publication or device compatibility test was performed in this session.
Runner builds, native paths/lifecycle, request-count/UI/browser behavior, audio,
TrollFools injection and tweak coexistence remain pending user validation in
`docs/validation.md`.
