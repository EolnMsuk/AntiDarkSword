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

On a rootless jailbreak the binary lives under `/var/jb/`, not at the rootful path `/usr/libexec/corelliumd`. A payload checking the bare rootful path would find nothing. The `AntiDarkSwordDaemon` tweak closes this gap by hooking the four most common existence checks in the processes it injects into:

| Hook | What it intercepts |
|---|---|
| `access("/usr/libexec/corelliumd", ...)` | Returns `0` (exists) |
| `stat("/usr/libexec/corelliumd", ...)` | Fills in a fake `stat` buffer (regular file, 755, ~34 KB) |
| `lstat("/usr/libexec/corelliumd", ...)` | Same as `stat` |
| `[NSFileManager fileExistsAtPath:"/usr/libexec/corelliumd"]` | Returns `YES` |

These hooks only activate when `globalDecoyEnabled` is `YES` — they pass through to the real syscall otherwise, so there is no overhead on a rootful install or when the feature is disabled.

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

---

## What payloads actually see

A payload performing standard Corellium detection on a device running AntiDarkSword at Level 3 encounters:

- `access("/usr/libexec/corelliumd", F_OK)` → `0` ✅
- `stat("/usr/libexec/corelliumd", &buf)` → `0`, buffer filled with a plausible regular-file stat ✅
- `[NSFileManager fileExistsAtPath:@"/usr/libexec/corelliumd"]` → `YES` ✅
- `ps` / process enumeration → `corelliumd` is a real running process with a real PID ✅

All four checks pass. The payload concludes it is inside a Corellium research environment and aborts.

---

## Limitations

- **TrollFools build**: CorelliumDecoy is not included. The dylib cannot install a LaunchDaemon or hook POSIX syscalls with `MSHookFunction` — both require a jailbreak. See the [TrollFools README](../AntiDarkSwordTF/README.md).
- **Rootless spoofing scope**: The file-path hooks only run inside the tier-3 daemon processes the tweak injects into (`imagent`, `apsd`, `identityservicesd`, `IMDPersistenceAgent`). A payload that checks for `corelliumd` from within a sandboxed app process it controls separately would not see the spoofed path from those hooks — though process-level visibility (`ps`, PID enumeration) still holds system-wide.
- **Detection fingerprint**: Determined adversaries can probe for inconsistencies (e.g., the fake `stat` buffer returns a fixed size and zeroed timestamps). The decoy is effective against automated payload abort logic, not against a human analyst actively examining a device.

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
