# AntiDarkSword source compatibility review

The current release version comes from `control`. This review describes source
changes and inspected build references, not reproduced device results. No local
package/full build, signing, injection or installation was performed. All
runner/device acceptance checks in [docs/validation.md](docs/validation.md) are
pending user results. Earlier blanket hardware, "tested", "all hooks functional"
and conflict-free claims are not supported by this Windows snapshot.

## Build targets and dependency evidence

| Target | SDK / minimum deployment | Mach-O intent | Debian architecture |
|---|---|---|---|
| legacy | 14.5 / iOS 13.0; intended iOS 13–14 rootful | arm64 | iphoneos-arm |
| rootful | 16.5 / iOS 15.0; intended iOS 15–17 rootful | arm64, arm64e | iphoneos-arm |
| rootless | 16.5 / iOS 15.0; intended iOS 15–17 rootless | arm64, arm64e | iphoneos-arm64 |
| roothide | 16.5 / iOS 15.0; supported native environments in the requested range | arm64, arm64e | iphoneos-arm64e |
| TrollFools | 16.5 / iOS 15.0; per-app standalone dylib | arm64, arm64e | not a Debian package |

These values come from `config/targets.json`. Deployment target, Mach-O CPU/ABI,
package architecture, jailbreak availability and actual device validation are
different questions. No "all models" or iOS 13/14 TrollFools support is claimed.
Legacy omits chained-fixup linker flags; actual SDK 14.5/API/link behavior remains
a runner check. Modern arm64e ABI and signing remain runner/device checks.

The supplied old AltList has an arm64/iOS 7 slice and a rootful absolute install
ID. The supplied modern AltList has arm64/current arm64e slices, iOS 15 minimum
and an `@rpath` ID; its `/var/jb` rpaths are not evidence of native Roothide
support. The separately downloaded official native AltList has iOS 15 minimum,
both modern slices, and a native `@loader_path/.jbroot` ID. Vendor originals are
preserved; build references are copied into isolated target directories and are
not installed by AntiDarkSword. Dependencies must be supplied by the matching
environment. Pinned toolchain sources, package checksum, typed API ownership,
bootstrap semantics and entitlements are documented in
[docs/building.md](docs/building.md) and [vendor/README.md](vendor/README.md).

## Focused safety findings and changes

| Area | Confirmed source issue | Implemented treatment / remaining check |
|---|---|---|
| UI/TF preference publication | CAS marked preferences loaded before all flags/strings were written; notification reloads could overlap | Serial reload queues build local values and publish complete retained snapshots. Each reading helper/hook retains a snapshot. A short pointer lock never spans CFPreferences, WebKit or original calls. Original rule precedence and default OFF master state are preserved. Stress concurrent callbacks on device. |
| Daemon publication | Separate flag atomics exposed intermediate combinations during reload | Serial reload computation publishes one atomic bitmask. Low-level hooks only load integer state; original functions/TLS recursion handling remain intact. |
| UA state | UI generation increment raced; TF used a permanent boolean injection marker | Generation belongs to each serialized snapshot in both variants. Main-queue UCC bookkeeping uses weak registrations and tracks only owned scripts/rules. Individual-script removal is selector-guarded; no all-script/all-rule clearing is introduced. |
| Content-rule compilation | Existing views could miss the asynchronous compilation result; reads assumed main without enforcing ownership | Compiled pointer publication is synchronized; main-queue reconciliation reaches already registered controllers and removes/replaces only the ADS rule list. Actual WebKit lifecycle/coexistence behavior remains a device check. |
| Settings observer lifetime | Raw Darwin observer pointers could be bridged during controller teardown | Main-queue libnotify tokens capture controllers weakly and are cancelled during deallocation. In-flight blocks acquire a live strong controller before accessing UI. |
| Settings process control | Multiple `posix_spawn` actions synchronously waited on the UI thread | Existing explicit actions enqueue on one worker. Waits handle errors/EINTR/status, use bounded monotonic deadlines, terminate only their own timed-out child and arrange nonblocking reaping. Pending controls are restored and visible errors reported. No process control is called from updater/donation code. |
| Probe counters | CFNumber conversion lacked a type check and addition could overflow | Validate type/conversion/nonnegative range; saturate at NSIntegerMax. Async persistence and debounce remain. Cross-process increments and resets still yield approximate diagnostic totals; no exact aggregation claim. |
| POSIX stat NULL arguments | A synthetic rootless result could return success for NULL output buffers | NULL buffers follow the original stat/lstat chain. Other spoof values, filters, size/errno handling and original-call paths are preserved. |
| Paths/API ownership | Directory-existence guessing and an untyped `jbroot` cast differed across components | Build-selected environment mapping and native typed API replace guessed package paths. Mobile preferences retain the original domain/any-host scope and canonical path, with legacy file fallback. Native bootstrap arguments use the documented `rootfs` conversion. Verify propagation and migration per environment. |
| Audio lifetime/data sharing | Render blocks captured manually freed state also written by scene UI | A render-captured owner holds audio-only synth state. UI sounds cross a bounded atomic mailbox; BGM is atomic. The render thread takes no producer lock and allocates nothing. Stop/detach releases scene references; active blocks retain their owner. Allocation/node/start failure paths leave games usable. A full mailbox drops an effect. Device teardown/audio stress remains pending. |
| New asynchronous helpers | Completion/copy callbacks can outlive their presenter/cell | Updater uses weak presenters and task identity checks. Wallet confirmations use row-specific tokens and weak controllers, never retained cells. All UI access occurs on main. |

The source audit is limited to these findings. It does not establish exploit
coverage or eliminate every possible conflict. Preference propagation, CF host
scope/migration behavior and cross-user daemon counters need the user checks.

## Scope and coexistence preserved

The update checker and donation menu are linked only into PreferenceLoader.
Automatic networking originates only from the visible AntiDarkSword root pane,
with persistent attempt bookkeeping independent of protection resets. There is
no timer, service, arbitrary-app launch callback or TrollFools updater.

UI injection retains its broad UIKit filter and existing process/extension
gates, including ignored Settings-related processes, allowed services,
per-plugin/parent fallback and filesystem/dyld Gecko checks. Browser-specific
JIT handling, global overrides, preset ordering, private-selector guards and
original hook chaining are preserved. The daemon executable filter remains
limited to its existing four processes. No Foundation/network work was added to
low-level POSIX hooks. TrollFools retains internal Logos, authentication and its
existing overlay; its changes are build consistency, path fallback and lifetime/
synchronization fixes.

Existing pages may require navigation/recreation after changing UA preferences;
removing a future document-start script cannot undo JavaScript already executed
in the current document. If `_removeUserScript:` is unavailable, older ADS
scripts require content-controller recreation; app/other-tweak scripts are never
cleared wholesale. Background-thread WebKit construction is not claimed to be a
supported UIKit usage pattern. The guarded private browser route must be checked
with each supported OS/default-browser/Venmo-installation combination. Failures
produce feedback without substituting a different URL or opening a wallet app.

## User validation matrix

| Surface | Required user evidence |
|---|---|
| Legacy/modern rootful, rootless, native Roothide | Build/install/upgrade/remove, signing, dependency IDs, path relocation, decoy lifecycle, preference propagation |
| Settings/SpringBoard services and disabled/non-target apps | Responsive UI, no unintended hooks/networking, intact original calls |
| Safari/WKWebView, Mail, Messages/NSEs | Expected rules, async blocker arrival, script/rule coexistence and per-extension inheritance |
| Chrome/Brave/Firefox/Gecko | Existing browser-specific behavior and Gecko gates preserved |
| Messengers, finance apps, Sileo/Zebra, Filza | Protected/unprotected regression checks, app features and original chains |
| Hook loaders, WebKit/UA tweaks, hiding tweaks, VPN/DNS, Lockdown Mode | Compare clean injection with actual installed combinations; record versions and logs |
| TrollFools | Standalone dependency inspection, injection, authentication/settings gesture, no new updater/donation UI |
| Credits/games | Scene transitions, rapid sounds/music, rotation/dismissal and audio shutdown |
| Updater/donation/Sileo | Full acceptance tables and rendering in [docs/validation.md](docs/validation.md) |

Local source checks and their concrete limitations are recorded in
[docs/local-validation.md](docs/local-validation.md). Build/device results must
be added only after the user supplies them.
