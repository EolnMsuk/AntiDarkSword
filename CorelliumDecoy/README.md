# CorelliumDecoy

A subcomponent of [AntiDarkSword](../README.md). It makes a jailbroken iOS device appear to be running inside a [Corellium](https://corellium.com/) virtualized research environment, causing advanced spyware and exploit kits to self-abort before they run.

Thanks to [ghh-jb](https://github.com/ghh-jb) for the original [CorelliumDecoy](https://github.com/ghh-jb/CorelliumDecoy) concept.

---

## How exploits use Corellium detection

Corellium is a commercial iOS virtualization platform used by security researchers to safely analyze malware and exploits. Sophisticated spyware (Coruna, Predator, and others in the same class) checks whether it is running on a Corellium device **before doing anything harmful** — if it detects the research environment, it aborts immediately to avoid being captured and reverse-engineered.

The primary signal these payloads check is the presence of Corellium's own daemon: `/usr/libexec/corelliumd`. If that binary exists and has a live process ID, the payload treats the device as a Corellium instance and self-destructs.

CorelliumDecoy exploits this defensive check by planting exactly that signal on a real device.

---

## What this subproject does

Two separate mechanisms work together to plant the signal:

### 1. The binary (`corelliumd`)

A minimal C program installed at `/usr/libexec/corelliumd` (rootful) or `/var/jb/usr/libexec/corelliumd` (rootless). Its only job is to hold a live process ID at zero CPU cost:

```c
CFRunLoopRun(); // sleep forever, burn nothing
```

It handles `SIGTERM`, `SIGINT`, and `SIGHUP` cleanly. The `platform-application` entitlement in `entitlements.plist` prevents jetsam from evicting it on rootless installs where the process runs outside the normal app sandbox.

### 2. The LaunchDaemon (`c.eolnmsuk.corelliumdecoy.plist`)

Registered with `launchd` so `corelliumd` starts at boot and is restarted if it exits (`KeepAlive: true`). The plist path differs by install type — see [Rootful vs. Rootless](#rootful-vs-rootless) below.

### 3. File-path spoofing (daemon tweak — rootless only)

On a rootless jailbreak the binary lives under `/var/jb/`, not at the rootful path `/usr/libexec/corelliumd`. A payload checking the bare rootful path would find nothing. The `AntiDarkSwordDaemon` tweak closes this gap by hooking the five most common existence checks in the processes it injects into:

| Hook | What it intercepts |
|---|---|
| `access("/usr/libexec/corelliumd", ...)` | Returns `0` (exists) |
| `stat("/usr/libexec/corelliumd", ...)` | Fills in a plausible `stat` buffer (regular file, 755, ~34 KB, uid=0, gid=0) |
| `lstat("/usr/libexec/corelliumd", ...)` | Same as `stat` |
| `[NSFileManager fileExistsAtPath:"/usr/libexec/corelliumd"]` | Returns `YES` |
| `[NSFileManager fileExistsAtPath:"/usr/libexec/corelliumd" isDirectory:]` | Returns `YES`, sets `*isDirectory = NO` |

These hooks only activate when `globalDecoyEnabled` is `YES` — they pass through to the real syscall otherwise, so there is no overhead on a rootful install or when the feature is disabled.

### 4. Probe counter

Every intercepted probe increments a persistent `corelliumProbeCount` counter in CFPreferences, visible as a live-updating cell in the Settings.app preferences panel. The counter is debounced (2-second window) to collapse the rapid multi-syscall burst a single probe generates into one count. Writes are dispatched asynchronously on a private serial queue to avoid deadlocking `apsd`'s synchronous cfprefsd calls. A separate Darwin notification (`com.eolnmsuk.antidarkswordprefs/counter`) is posted after each increment so Settings.app refreshes the counter cell independently of a full prefs reload.

### 5. sysctl / sysctlbyname spoofing (daemon tweak)

File-path checks are not the only environment probe a payload may use. Hardware queries via `sysctl` and `sysctlbyname` return real device identifiers — model name, machine string, CPU subtype, and boot time — that are distinct from a Corellium-virtualized environment and can expose a real device to fingerprinting.

`AntiDarkSwordDaemon` hooks both C functions via `MSHookFunction` and returns values consistent with a genuine Corellium instance:

| Key | Spoofed value |
|---|---|
| `hw.model` / `hw.machine` | `"iPhone15,2"` |
| `hw.cpusubtype` | `2` (`CPU_SUBTYPE_ARM64E`) |
| `kern.boottime` | `now − 10800 − (getpid() % 3600)` — stable PID-seeded uptime of 3–4 hours |

The helper `ads_spoof_bytes` implements the correct POSIX two-pass sysctl contract: a first call with `oldp == NULL` writes the required size to `*oldlenp` and returns 0; a second call copies the spoofed value after validating buffer size, returning `ENOMEM` on undersize.

A thread-local `_ads_sysctl_active` flag prevents re-entrancy: GCD's `dispatch_async` internally calls `sysctl("hw.ncpu")` on the same thread during queue enqueue. Without the guard, the hook would recurse when `ads_increment_probe_counter()` dispatches its counter write. The flag is set immediately before the dispatch call and cleared immediately after.

All intercepted sysctl queries call `ads_increment_probe_counter()`, feeding the same debounced probe counter as the file-path hooks.

---

## Rootful vs. Rootless

The binary path, plist path, and whether file-path spoofing is needed all differ between rootful and rootless jailbreaks.

| | Rootful | Rootless |
|---|---|---|
| **Binary path** | `/usr/libexec/corelliumd` | `/var/jb/usr/libexec/corelliumd` |
| **LaunchDaemon path** | `/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist` | `/var/jb/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist` |
| **Plist `ProgramArguments`** | `/usr/libexec/corelliumd` | `/var/jb/usr/libexec/corelliumd` (rewritten by `sed` at build time) |
| **File-path spoofing hooks needed?** | No — binary is already at the expected rootful path | Yes — hooks spoof `/usr/libexec/corelliumd` as present even though it lives under `/var/jb/` |
| **`postinst` prefix** | `""` | `/var/jb` |

### How the Makefile handles this

The `CorelliumDecoy/Makefile` runs a `sed` substitution at staging time when `THEOS_PACKAGE_SCHEME=rootless`:

```makefile
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
    sed 's|/usr/libexec/corelliumd|/var/jb/usr/libexec/corelliumd|g' \
        c.eolnmsuk.corelliumdecoy.plist > $(STAGING)/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist
else
    cp c.eolnmsuk.corelliumdecoy.plist $(STAGING)/Library/LaunchDaemons/
endif
```

The source plist always uses the rootful path — the build system rewrites it for rootless packages. This keeps a single source file for both variants.

### How `postinst` handles this

The `layout/DEBIAN/postinst` script detects the jailbreak type at install time and applies the correct prefix for all `launchctl` and `chmod`/`chown` calls:

```sh
PREFIX=""
if [ -d /var/jb ]; then PREFIX="/var/jb"; fi

chmod 755 $PREFIX/usr/libexec/corelliumd
chown root:wheel $PREFIX/usr/libexec/corelliumd
launchctl load $PREFIX/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist
```

---

## What activates the spoofing hooks

The file-path hooks in `AntiDarkSwordDaemon` are installed unconditionally (so live pref changes take effect without re-injection), but their bodies only run when all three conditions are true:

1. **`globalTweakEnabled`** — master AntiDarkSword switch is ON
2. **`corelliumDecoyEnabled`** — Corellium Honeypot switch is ON (found in Settings > AntiDarkSword > Restrict System Daemons)
3. **`currentProcessRestricted`** — the daemon process is active under Level 3 auto-protection and has not been individually disabled

If any condition is false the hooks call through to the real `access`/`stat`/`lstat` with zero overhead.

### Why all four daemons must be active

The `currentProcessRestricted` flag is evaluated per-process — each daemon independently computes whether it is active. The POSIX hooks intercept filesystem calls only from within a daemon where the tweak is running. This means:

- An exploit that calls `access("/usr/libexec/corelliumd")` from within **`imagent`** will only see the spoofed result if `imagent` has the tweak active.
- Having only `apsd` enabled but `imagent` disabled means calls from `imagent` context are **not** intercepted.

Because zero-click iMessage exploits typically execute inside `imagent` or `IMDPersistenceAgent`, disabling any daemon reduces spoofing coverage for payloads delivered through that vector.

**For this reason, toggling the Corellium Honeypot ON in the Settings UI automatically re-enables all four daemons** (`imagent`, `apsd`, `identityservicesd`, `IMDPersistenceAgent`) and grays out their individual toggle switches while the honeypot remains active. This ensures complete coverage regardless of which daemon a payload targets.

---

## What payloads actually see

A payload performing standard Corellium detection on a device running AntiDarkSword at Level 3 encounters:

- `access("/usr/libexec/corelliumd", F_OK)` → `0` ✅
- `stat("/usr/libexec/corelliumd", &buf)` → `0`, buffer filled with a plausible regular-file stat ✅
- `[NSFileManager fileExistsAtPath:@"/usr/libexec/corelliumd"]` → `YES` ✅
- `ps` / process enumeration → `corelliumd` is a real running process with a real PID ✅
- `sysctl`/`sysctlbyname("hw.model")` → `"iPhone15,2"` ✅
- `sysctl`/`sysctlbyname("hw.cpusubtype")` → `CPU_SUBTYPE_ARM64E` ✅
- `sysctl`/`sysctlbyname("kern.boottime")` → plausible 3–4 hour uptime ✅

All checks pass. The payload concludes it is inside a Corellium research environment and aborts.

---

## Limitations

- **Rootless spoofing scope**: The file-path hooks only run inside the tier-3 daemon processes the tweak injects into (`imagent`, `apsd`, `identityservicesd`, `IMDPersistenceAgent`). A payload that checks for `corelliumd` from within a sandboxed app process it controls separately would not see the spoofed path from those hooks — though process-level visibility (`ps`, PID enumeration) still holds system-wide.
- **Detection fingerprint**: Determined adversaries can probe for inconsistencies (e.g., the fake `stat` buffer returns a fixed size and zeroed timestamps). The decoy is effective against automated payload abort logic, not against a human analyst actively examining a device.
- **TrollFools build**: CorelliumDecoy is not included. The dylib cannot install a LaunchDaemon or hook POSIX syscalls with `MSHookFunction` — both require a jailbreak. See the [TrollFools README](../AntiDarkSwordTF/README.md).

---

## Building standalone

```sh
# From the repo root — built as part of the full package:
make package
make package THEOS_PACKAGE_SCHEME=rootless

# The binary ends up at:
# .theos/obj/CorelliumDecoy/corelliumd
```

CorelliumDecoy is listed as a subproject in the root `Makefile` and is always included in both rootful and rootless `.deb` packages.
