# AntiDarkSwordDaemon

The daemon-layer tweak of [AntiDarkSword](../README.md). It injects directly into the system's iMessage background daemons to block zero-click attachment processing before content ever reaches an app UI, and to plant the Corellium Honeypot signal visible to exploit payloads running at the system level.

---

## Where it injects

The injection filter (`AntiDarkSwordDaemon.plist`) uses an `Executables` filter — targeting four specific system daemon processes by process name rather than by framework:

- **`imagent`** — the primary iMessage agent; routes all incoming messages and attachment events
- **`IMDPersistenceAgent`** — persists iMessage data to disk; a common zero-click delivery path
- **`apsd`** — Apple Push Service daemon; delivers remote push notifications including iMessage triggers
- **`identityservicesd`** — manages Apple ID identity and IDS routing; included in tier 3 for Corellium spoofing coverage

All four run as root, outside any app sandbox. The `Executables` filter ensures the tweak only loads into these specific processes — not into UIKit apps, which are handled separately by `AntiDarkSwordUI`.

---

## What it protects

### iMessage Zero-Click Blocking

Hooks `IMFileTransfer` (from IMCore) at the daemon level, before any attachment surfaces to the iMessage UI:

- `IMFileTransfer.isAutoDownloadable` → returns `NO`
- `IMFileTransfer.canAutoDownload` → returns `NO`

These hooks run in `imagent` and `IMDPersistenceAgent` — the processes that receive and stage incoming attachments. Blocking at this layer means a crafted attachment is stopped before it is decoded, written to disk, or passed to any parsing library. This is the primary zero-click mitigation path.

`apsd` and `identityservicesd` also load the tweak (for the Corellium spoofing hooks), but IMCore is not guaranteed to be present in those processes, so the `IMFileTransfer` hooks simply don't fire there — this is safe by design.

The `AntiDarkSwordUI` tweak hooks the same `IMFileTransfer` methods inside the iMessage UI processes as a second layer. If this daemon layer is bypassed or disabled, the UI layer still provides a fallback.

### Corellium Honeypot — File-Path Spoofing

On a rootless jailbreak, the Corellium decoy binary lives at `/var/jb/usr/libexec/corelliumd`, not at the rootful path `/usr/libexec/corelliumd` that spyware payloads actually check. This tweak closes that gap by hooking four existence-check entry points in the daemon processes and making them return "yes, it's there" for the rootful path:

| Hook | What it intercepts |
|---|---|
| `access("/usr/libexec/corelliumd", ...)` | Returns `0` (file exists) |
| `stat("/usr/libexec/corelliumd", ...)` | Returns `0`, fills a plausible `stat` buffer (regular file, mode `755`, ~34 KB, `uid=0`, `gid=0`, plausible inode) |
| `lstat("/usr/libexec/corelliumd", ...)` | Same as `stat` |
| `NSFileManager -fileExistsAtPath:` | Returns `YES` |
| `NSFileManager -fileExistsAtPath:isDirectory:` | Returns `YES`, sets `*isDirectory = NO` |

The `stat` and `lstat` hooks fill the buffer with `uid=0`, `gid=0`, `nlink=1` — consistent with a real root-owned system binary.

On a rootful install these hooks are also installed, but their bodies are gated by `isRootlessJB`. If the device is rootful, the binary is already at `/usr/libexec/corelliumd` for real, so the hooks pass straight through to the original syscall with no overhead.

The POSIX hooks (`access`, `stat`, `lstat`) use `MSHookFunction` from CydiaSubstrate/ElleKit — C-function interposition, not ObjC method swizzling — because these are C library calls, not Objective-C methods. The `NSFileManager` hooks use the standard `%hook` mechanism.

### Corellium Probe Counter

Every time a Corellium-path probe is intercepted (across all four hook types), a debounced counter increments the `corelliumProbeCount` key in CFPreferences. This counter is displayed in the Settings.app preferences panel so spyware probe attempts are visible to the user.

**Debouncing:** A 2-second atomic compare-and-swap window collapses the rapid `access`+`stat`+`lstat` burst that a single probe event generates into one count increment.

**Async dispatch:** The CFPreferences write is dispatched asynchronously on a dedicated serial queue (`com.eolnmsuk.ads.counter`). This is required because `apsd` calls cfprefsd synchronously for APNs configuration — a synchronous CFPreferences write from inside a hooked POSIX call would cause `apsd` to wait on cfprefsd while cfprefsd waits on `apsd`, resulting in a deadlock that breaks push notification delivery. The queue is created in `%ctor` before any POSIX hooks are installed.

After writing, the counter posts a separate Darwin notification (`com.eolnmsuk.antidarkswordprefs/counter`) so Settings.app can refresh the counter cell without triggering a full prefs reload in all other injected tweak instances.

**Rootful vs rootless:** On a rootful install the binary exists at `/usr/libexec/corelliumd`; `hook_stat` and `hook_lstat` pass through to the real syscall without fabricating a `struct stat`. `hook_access` and `NSFileManager -fileExistsAtPath:` still intercept explicit checks on that path and increment the counter — a payload specifically probing for the binary is suspicious regardless of environment. On rootless the canonical path does not exist; all four hooks (`hook_access`, `hook_stat`, `hook_lstat`, `NSFileManager`) both fabricate a plausible result and increment the counter.

### Corellium Honeypot — sysctl Spoofing

File-path checks are not the only environment probe a payload may use. Hardware queries via `sysctl` and `sysctlbyname` return real device identifiers — model name, machine string, CPU subtype, and boot time — that distinguish a real physical device from a Corellium-virtualized instance. Both C functions are hooked via `MSHookFunction`:

| Key | Spoofed value |
|---|---|
| `hw.model` / `hw.machine` | `"iPhone15,2"` |
| `hw.cpusubtype` | `2` (`CPU_SUBTYPE_ARM64E`) |
| `kern.boottime` | `now − 10800 − (getpid() % 3600)` — stable PID-seeded uptime of 3–4 hours |
| `kern.osversion` | `"21C62"` (iOS 17.2 build for iPhone15,2) |

The `ads_spoof_bytes` helper implements the correct POSIX two-pass sysctl contract: a first call with `oldp == NULL` writes the required size to `*oldlenp` and returns 0; a second call copies the spoofed value after validating buffer size, returning `ENOMEM` on undersize.

Both hooks are installed in `%ctor` immediately after the existing `access`/`stat`/`lstat` hooks, gated on `globalDecoyEnabled`. Sysctl hooks do not increment the probe counter — `sysctl` and `sysctlbyname` are called constantly during normal ObjC/Foundation initialisation and do not indicate a Corellium probe.

Three additional detection vectors are spoofed when `globalDecoyEnabled` is active:

- **`getenv("CORELLIUM_ENV")`** (via `MSHookFunction`) — returns `NULL`. Corellium sets this environment variable in some configurations; the hook prevents it from leaking into env-var scans inside the daemon processes.
- **`kern.osversion`** (via `sysctlbyname`) — returns `"21C62"`, consistent with the spoofed `hw.model`. A mismatched build string is trivially detectable by any checker that cross-references model against expected OS version.
- **`/var/db/uuidtext/` path probes** (via `hook_access`) — any `access` call into this path returns `0` (success). Corellium may replace the UUID log directory; its absence fingerprints the VM. OSLog hits this path on every log write throughout daemon lifetime, so these calls do not feed the probe counter.

---

## How targeting works

`loadPrefs()` runs in `%ctor` and on every Darwin notification from the preferences panel. It determines whether the current process should be active and which mitigations to apply.

### Process matching

The current process's bundle ID and process name are both checked (in that order) against:

1. **Custom daemon IDs** (`activeCustomDaemonIDs`) and **manual app rules** (`restrictedApps`, `restrictedApps-<id>`) — user-added overrides
2. **Auto-protection tier 3** — the four preset daemon process names and their bundle IDs (`com.apple.imagent`, `imagent`, `com.apple.apsd`, `apsd`, etc.)

Tier 1 and tier 2 (UIKit apps) are not relevant here and are never evaluated.

### Cross-alias disabled check

Before the tier 3 matching loop runs, the tweak checks whether the current process is individually disabled by the user (via the "Restrict System Daemons" switches in Settings). This check runs against **both** the bundle ID and the short process name, so that disabling `"apsd"` via the UI (which stores the short name) correctly suppresses the hook even when the process reports its bundle ID `"com.apple.apsd"` first.

```
isDisabledByUser = bundleID in disabledPresetRules
                 OR processName in disabledPresetRules
```

If either alias is in the disabled list, tier 3 matching is skipped entirely for that process.

### Per-mitigation resolution

`applyDisableIMessageDL` is the flag the `IMFileTransfer` hooks read. It resolves as:

```
globalTweakEnabled AND (globalDisableIMessageDL OR (currentProcessRestricted AND disableIMessageDL))
```

Global overrides apply the mitigation regardless of tier or per-process rules. Per-process rules come from `TargetRules_<matchedID>` preference keys written by the settings UI.

`globalDecoyEnabled` (the flag the file-path hooks read) resolves as:

```
globalTweakEnabled AND corelliumDecoyEnabled AND currentProcessRestricted
```

All three must be true. If any is false, every file-path hook passes through to the real syscall with no overhead.

### Thread safety

Hook functions can be called from any thread. All flags read at hook call time (`applyDisableIMessageDL`, `globalDecoyEnabled`, `currentProcessRestricted`) are declared `_Atomic`. Intermediate variables computed inside `loadPrefs()` itself use plain `BOOL` since they are not shared across threads.

The `_ads_sysctl_active` thread-local flag is `static __thread BOOL` and exists as a forward-safety sentinel at the top of `hook_sysctlbyname`; it is no longer actively set.

---

## How it differs from AntiDarkSwordUI

| | AntiDarkSwordDaemon | AntiDarkSwordUI |
|---|---|---|
| **Injection filter** | `Executables` (process name) | Bundle filter (`com.apple.UIKit`) |
| **Target processes** | `imagent`, `IMDPersistenceAgent`, `apsd`, `identityservicesd` | All UIKit apps + specified services |
| **iMessage blocking** | Yes — primary, daemon-level | Yes — secondary, UI-level fallback |
| **WebKit hardening** | No | Yes |
| **UA spoofing** | No | Yes |
| **C-function hooks** | Yes — `MSHookFunction` for POSIX | Only `JSEvaluateScript` via `%hookf` |
| **Corellium spoofing** | Yes — file-path hooks (rootless) | No |
| **Auto-protect tier** | Tier 3 only | Tier 1, 2 (Tier 3 is empty in UI) |

---

## Hook entry points

| Hook | Trigger |
|---|---|
| `IMFileTransfer -isAutoDownloadable` | iMessage attachment auto-download query |
| `IMFileTransfer -canAutoDownload` | iMessage attachment download eligibility query |
| `NSFileManager -fileExistsAtPath:` | ObjC-level file existence check for Corellium path; also triggers probe counter |
| `NSFileManager -fileExistsAtPath:isDirectory:` | ObjC-level file existence + directory check; also triggers probe counter |
| `access` (C function via `MSHookFunction`) | POSIX existence check for Corellium path; also returns `0` for any path under `/var/db/uuidtext/`; increments probe counter on corelliumd path only |
| `stat` (C function via `MSHookFunction`) | POSIX metadata query for Corellium path |
| `lstat` (C function via `MSHookFunction`) | POSIX metadata query (symlink-aware) for Corellium path |
| `getenv` (C function via `MSHookFunction`) | Returns `NULL` for `CORELLIUM_ENV`; all other env var lookups pass through |
| `sysctl` (C function via `MSHookFunction`) | Hardware query; spoofs `hw.model`/`hw.machine` → `"iPhone15,2"`, `hw.cpusubtype` → `CPU_SUBTYPE_ARM64E`, `kern.boottime` → stable PID-seeded uptime |
| `sysctlbyname` (C function via `MSHookFunction`) | Named sysctl variant; same hardware spoof targets as `sysctl`; also returns `"21C62"` for `kern.osversion` |
