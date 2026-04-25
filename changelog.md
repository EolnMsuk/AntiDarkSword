# Changelog

## ADSLogging.h
- Removed two inline comments explaining the obvious macro behaviour.

## AntiDarkSwordDaemon/Tweak.x
- Removed all four `// ===...===` section-banner comments.
- Removed obvious comments: `// Pure C check — safe for %ctor`, docstring above `ads_prefs_path()`, `// Check custom / manually-added daemon IDs first`, `// Corellium decoy: only active at level 3+`, `// Per-target rule override from preferences`.
- Condensed `loadPrefs()` CAS comment; kept cross-alias check explanation (non-obvious invariant).
- Condensed `ads_increment_probe_counter` deadlock comment block; preserved core rationale.
- Kept stat-struct value comments (`// plausible inode`, `// 9 × 4096-byte APFS blocks`).
- Kept `%ctor` ordering note for `isRootlessJB` and queue-before-hooks comment.
- Normalised `globalTweakEnabled`/`globalDisableIMessageDL`/`autoProtectLevel` reads to consistent two-line `? : NO` alignment.

## AntiDarkSwordUI/Tweak.x
- **Full indentation rewrite**: `adsBrandsFromUA`, `adsJSONStringLiteral`, `injectUAScript`, `applyWebKitMitigations`, `loadPrefs`, all hook bodies, and `%ctor` had mixed/broken indentation — normalised to 4-space throughout.
- Removed all five `// ===...===` section-banner comments.
- Removed state-variable group comments (`// Runtime State Variables`, `// Global Overrides`, etc.); replaced with single architectural note on atomic vs. non-atomic fields.
- Removed obvious inline comments throughout `loadPrefs()` and hooks.
- Collapsed `disableMedia = NO; disableRTC = NO; disableIMessageDL = NO;` into a single chain assignment; same for `disableJIT = disableJIT15 = disableJS = disableFileAccess = NO`.
- Kept non-obvious comments: iOS 14 guard rationale in `applyWebKitMitigations`, BLASTPASS note, Tier 3 structural note, CFPreferences fallback rationale in `%ctor`.
- Aligned `TargetRules_` appRules extraction block for readability.

## AntiDarkSwordTF/Tweak.x
- Replaced 17-line verbose header comment with a 3-line summary.
- Removed all `// ===...===` section-banner comments (7 banners).
- Removed section-header comments within `viewDidLoad` (`// --- Dimmed / blurred backdrop ---`, `// --- Card ---`, `// --- Header ---`, `// --- Master enabled row ---`, `// --- Table view ---`, `// --- Buttons ---`, `// --- Auto Layout ---`, layout sub-headers, `// ---- UITableViewDataSource ----`, `// ---- Actions ----`).
- Condensed `ads_read_prefs`, `ads_write_prefs`, `loadPrefs`, `ads_tf_setting_rows`, `ads_default_value_for_key` comments.
- Collapsed master-switch background-colour comment; kept `NSIntegerMax` sentinel comment (non-obvious).
- Removed `// 1.`, `// 2.`, `// 3.` numbered-step comments in `ads_read_prefs`.

## antidarkswordprefs/RootListController.m
- **Structural fix**: moved `PrefsChangedNotification` static C function from inside `@implementation AntiDarkSwordPrefsRootListController` to file scope above the `@implementation`. Static C function definitions inside ObjC `@implementation` blocks are non-standard; all sibling callbacks (`DaemonPrefsChangedNotification`, `AltPrefsChangedNotification`, `ProbeCounterNotification`) were already at file scope.

## Files unchanged
- `CorelliumDecoy/main.m` — 23 lines, no actionable comments.
- `antidarkswordprefs/ADSGames.m`, `ADSPyEater.m` — out of scope for this pass.
- All `Makefile*`, plist files — no source changes required.

---

## Static & Runtime Analysis Pass

### AntiDarkSwordTF/Tweak.x
- **Bug fix**: `applyBlockRemoteContent` was absent from the atomic reset chain in the `!masterEnabled` early-return path of `loadPrefs()`. If a user had previously enabled "Block Remote Content" via the overlay and then turned the overlay's master "Enable Protection" switch off, the `WKContentRuleList` blocker continued firing on every new `WKWebView` init. Added `applyBlockRemoteContent = NO` to the chain alongside the other apply-flags.
- **Race fix**: `adsContentBlocker` (a bare `static WKContentRuleList *`) was read directly from hook callbacks running on arbitrary threads while being assigned from the async `WKContentRuleListStore` completion handler. Captured to a `WKContentRuleList *localBlocker` local before use in both `applyWebKitMitigations()` and `%hook WKWebViewConfiguration setUserContentController:`, eliminating the window where ARC retain-count operations on the pointer could race.

### antidarkswordprefs/ADSJailTris.m
- Renamed internal C constants and block-shape array from legacy `kRop*` / `rop_blocks` namespace to `kJT*` / `jt_blocks` (JailTris-scoped). All 30 usage sites updated. Zero behaviour change — purely internal symbols not exposed in the header.

### antidarkswordprefs/ADSCreditsMenu.m
- Renamed private ivar/local-variable names for the two game-select buttons from pre-rename ghost names (`_btnSnake`, `snakeLbl`, `_btnTetris`, `tetrisLbl`) to current game names (`_btnPyEater`, `pyEaterLbl`, `_btnJailTris`, `jailTrisLbl`). All 28 usage sites updated. Zero behaviour change.

### Verified correct / no change required
- `_Atomic BOOL prefsLoaded` CAS gate: plain assignment `prefsLoaded = NO` is an atomic store under C11 for `_Atomic`-qualified types. No data race.
- `ads_counter_queue` init ordering: `ads_increment_probe_counter` checks `globalDecoyEnabled` (NO during init) and has a `!ads_counter_queue` nil guard; POSIX hooks installed strictly after queue creation.
- `CFPreferencesCopyMultiple` ownership: `(__bridge_transfer NSDictionary *)dict` + `CFRelease(keyList)` pattern is correct across all three tweaks.
- `isRootlessJB` set before `%init` in all three tweaks; never written again.
- `internal` generator compliance in TF: no `<substrate.h>`, no `MSHookFunction`, no `%hookf`.
- `@"ADS_SnakeHighScore"` NSUserDefaults key in `ADSPyEater.m` intentionally preserved — renaming would silently erase user high scores on update.

---

## Feature Pass — Corellium sysctl Spoofing + Navigation Enforcement

### AntiDarkSwordDaemon/Tweak.x
- **New feature**: Extended Corellium decoy with `hook_sysctl` and `hook_sysctlbyname` via `MSHookFunction`. Intercepts `hw.model` / `hw.machine` → `"iPhone15,2"`; `hw.cpusubtype` → `2` (`CPU_SUBTYPE_ARM64E`); `kern.boottime` → stable spoofed `timeval`. All intercepts call `ads_increment_probe_counter()`, feeding the existing probe counter.
- Added `#include <sys/sysctl.h>` and `#include <sys/time.h>`.
- Added `ads_spoof_bytes(src, required, oldp, oldlenp)` helper implementing the correct POSIX two-pass sysctl contract: pass 1 (`oldp == NULL`) writes required size to `*oldlenp` and returns 0; pass 2 validates `*oldlenp >= required` before `memcpy`, returns `-1`/`ENOMEM` on undersized buffer.
- Added `static __thread BOOL _ads_sysctl_active = NO` thread-local re-entrancy guard. Set immediately before `ads_increment_probe_counter()`, reset immediately after. Prevents infinite recursion via GCD internals calling `sysctl("hw.ncpu")` during `dispatch_async` enqueue on the same thread.
- `ads_spoofed_boottime` initialised once in `%ctor`: `now - 10800 - (getpid() % 3600)` — 3–4 h before process start, stable for process lifetime, varies per PID.
- `MSHookFunction` calls for `sysctl` and `sysctlbyname` added to `%ctor` immediately after the existing `access`/`stat`/`lstat` hooks; both gated on `globalDecoyEnabled` at call time.

### AntiDarkSwordUI/Tweak.x / AntiDarkSwordTF/Tweak.x
- **Investigated and rejected**: navigation re-enforcement hooks (`reload`, `goBack`, `goForward`) were prototyped and removed. `WKWebViewConfiguration` properties (`javaScriptEnabled`, `allowsContentJavaScript`) are deep-copied and locked at `initWithFrame:configuration:` time — mutations from inside navigation method hooks are no-ops against the live `WKWebContent` XPC process. Re-assigning `customUserAgent` mid-navigation after provisional load resolves its request headers triggers WebKit IPC races. Existing enforcement via setter hooks (`setAllowsContentJavaScript:`, `setJavaScriptEnabled:`, `setLockdownModeEnabled:`, `setJITEnabled:`) and init-time `applyWebKitMitigations` is sufficient. Net change to both files: none.



  Changelog — all patches applied:
                                                                                                                                                                                      ADSGames.h
  - ADSSynthState → +5 fields: bgmPhase2 (bass osc), sfxEnvInit (envelope anchor), sfxFreq2/sfxPhase2/sfxDur2 (2nd SFX voice)                                                       
  ADSJailTris.m
  - willMoveFromView → _sourceNode = nil after engine stop (dangling ref fix)
  - setupAudio render block → melody triangle wave (0.028 amp) + bass square wave (0.012 amp) at octave below; SFX voice-1 pulse+envelope (0.22×env); SFX voice-2 pulse+envelope
  (0.12×env)
  - playSFX:dur: → resets sfxPhase=0, clears sfxDur2=0, sets sfxEnvInit
  - +playSFX2:freq2:dur: → new two-voice SFX method, resets both phases
  - handlePan multi-move dispatch → weak/strong self pattern (retain cycle fix)
  - handlePan move (both paths) → playSFX2:220 freq2:440 dur:0.03
  - handlePan hard-drop → 90Hz+180Hz 0.09s (was 150Hz 0.05s)
  - handleTap rotate → playSFX2:330 freq2:659 dur:0.06
  - lockBlock → playSFX2:200 freq2:400 dur:0.06 (was 150 0.05)
  - clearLines 1/2/3x → delegates to showLineClearFX:count: (horizontal flash bars + combo labels + shockwave on 3x + per-count ascending 2-voice arp)
  - clearLines 4x fanfare → all playSFX2 power-chords + 8 burst circles flying radially
  - clearLines new-high-score mid-game → playSFX2 octave pairs
  - die new high score → playSFX2 ascending fanfare; death SFX → 120+60Hz
  - showLeaderboard → playSFX2:1046 freq2:1318
  - +showLineClearFX:count: → new method; green/cyan/gold color per count; SKShapeNode bar flash per cleared row; ascending 2-voice SFX sequences; 3x shockwave SKShapeNode circle;
  2x/3x floating combo label

  ADSPyEater.m
  - willMoveFromView → _sourceNode = nil
  - +_foodLayer ivar → persistent food node layer, avoids O(n) food recreation every 16ms tick
  - didMoveToView → _foodLayer added to bloomNode before gameLayer (food renders below snake)
  - setupAudio render block → same two-voice BGM/SFX pattern; 16-note E-minor pentatonic melody (was 8-note); bass array at octave below; triangle mel (0.026) + square bass
  (0.011); envelope on both SFX voices
  - playSFX:dur: → same upgrades as JailTris
  - +playSFX2:freq2:dur: → added
  - +updateFoodNode → creates persistent pulsing food node in _foodLayer; called by spawnFood
  - render → food creation removed; snake gradient head (0.4,1.0,1.0 cornered) → tail fade (0.45× floor); shapeNodeWithRectOfSize:cornerRadius:3 for head
  - update: eat branch → playSFX2:880 freq2:1760; growth pulse: teal ring expands 2.8× in 0.22s added to bloomNode; new-high-score SFX → octave playSFX2 pairs
  - die → double-strobe red flash (0.04/0.07/0.04/0.18s); shockwave ring from head position; SFX death → 120+60Hz; new-high-score SFX → ascending playSFX2 fanfare
  - touchesEnded high-score tap → playSFX2:1046 freq2:1318

---

## Full Audit Pass — Code Verification & Documentation Sync

### AntiDarkSwordDaemon/Tweak.x — verified correct, no changes
- CAS gate (`prefsLoaded`) + `%init`-before-`loadPrefs()` ordering: NSFileManager hook fires before `globalDecoyEnabled` is set → check evaluates NO immediately → no false-positive decoy on init-time file lookups. ✓
- `ads_counter_queue` nil guard in `ads_increment_probe_counter`: `countersEnabled` is NO until `loadPrefs()` completes; POSIX hooks installed strictly after queue creation → no null-deref window. ✓
- Thread-local `_ads_sysctl_active` scope: set immediately before `ads_increment_probe_counter()`, cleared immediately after; dispatched block runs on queue thread where flag is NOT set → CFPreferences* calls in the block do not recurse into the sysctl hook. ✓
- `ads_spoof_bytes` two-pass contract: pass 1 (`oldp == NULL`) writes `required` to `*oldlenp`, returns 0; pass 2 validates `avail >= required` before `memcpy`, returns `-1`/`ENOMEM` on short buffer. Correct POSIX sysctl semantics. ✓
- `ads_spoofed_boottime` init: `now - 10800 - (getpid() % 3600)` — 3–4 h window, stable for process lifetime, PID-seeded for per-process variation. Written once in `%ctor` before hooks install; no concurrent write path. ✓
- Cross-alias disabledPresetRules check: both `bundleID` and `processName` slots checked before tier3 matching — prevents `"apsd"` short-name override from being bypassed by bundle-ID match. ✓

### AntiDarkSwordUI/Tweak.x — verified correct, no changes
- Non-atomic intermediate vars (`disableJIT`, `disableJS`, etc.) only written inside `loadPrefs()` under the CAS gate; final assignments to `_Atomic apply*` flags happen at end of `loadPrefs()` as a sequenced write. No concurrent write path for non-atomic vars. ✓
- `%hookf JSEvaluateScript`: returns NULL with populated `*exception` when `ctx && exception`; returns NULL with no exception when `exception == NULL` (valid per JSC C API — NULL return is the caller's signal for failure regardless of exception pointer). ✓
- `injectUAScript` double-registration risk in `setUserContentController:`: scripts are `configurable:true` — last definition wins; multiple injections from the hook and `applyWebKitMitigations` are wasteful but not semantically harmful. Acceptable. ✓
- `%ctor` early-exit for `.appex`, ignored process names, non-app/non-service paths: prevents injection into extension sandboxes and noisy system processes before any hook is registered. ✓

### AntiDarkSwordTF/Tweak.x — verified correct, no changes
- `adsContentBlocker` race: `WKContentRuleList *localBlocker = adsContentBlocker` local capture in both `applyWebKitMitigations` and `%hook WKWebViewConfiguration setUserContentController:` eliminates the ARC race window introduced by the async compile completion handler. ✓
- `applyBlockRemoteContent` reset chain: included alongside all other `apply*` flags in the `!masterEnabled` early-return path — ensures the content blocker is not applied to new WKWebViews when protection is toggled off. ✓
- `ADSTFGestureHandler` singleton: `dispatch_once` + static ivar; `UITapGestureRecognizer` holds a strong ref internally, but the target must outlive the recognizer — singleton satisfies this. ✓
- `ads_write_prefs` sandboxed fallback: iterates `dictionaryRepresentation` to remove stale keys before writing new values; prevents deleted prefs keys from persisting across saves. ✓
- `ads_key_window` iOS 13+ path: if no `UISceneActivationStateForegroundActive` scene contains a key window, falls through to deprecated `keyWindow` getter — safe defensive fallback. ✓

### antidarkswordprefs/ADSGames.h — structural change documented
- `ADSGames.m` deleted; game scene implementations (including `ADSGameMenuScene`) consolidated into `ADSJailTris.m` and `ADSPyEater.m`.
- `ADSGames.h` expanded: added `AntiDarkSwordCreditsController` forward declaration (previously forward-declared inline in `ADSCreditsMenu.m`).

### Documentation updates applied (no code changes)
- `CLAUDE.md` Corellium decoy flow: updated point 2 to list `sysctl`/`sysctlbyname` alongside `access`/`stat`/`lstat`/`NSFileManager`; added sysctl spoof targets and reentrancy guard note.
- `CLAUDE.md` arch table: updated Daemon capability cell to enumerate all five POSIX hook targets.
- `ProjectStructure.md` ADSGames.h entry: added `AntiDarkSwordCreditsController` to declaration list; noted ADSGames.m removal and implementation consolidation.

### Constraint validation
- `LOGOS_DEFAULT_GENERATOR=internal` compliance (TF): no `#include <substrate.h>`, no `MSHookFunction`, no `%hookf`. `%hook`/`%orig`/`%ctor` only. ✓
- Daemon minimal linkage: no UIKit/WebKit/JavaScriptCore import; Foundation + CoreFoundation + POSIX only. ✓
- `isRootlessJB` set before `%init` in all three tweaks; written once; never mutated post-init. ✓
- All `%hook` blocks have matching `%end`; all `%ctor` blocks are well-formed. ✓


---



● All clean. Changelog:

  ---
  MEMORY / SAFETY
                                                                                                                                                                                      ┌─────┬──────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │                       File                       │                                                        Fix                                                         │     ├─────┼──────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ M1  │ ADSCreditsMenu.m ·                               │ _sourceNode = nil added → eliminates UAF window where render block held dangling ADSSynthState* after free()       │
  │     │ ADSGameMenuScene.willMoveFromView:               │                                                                                                                    │
  ├─────┼──────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ M2  │ ADSCreditsMenu.m · launchGame                    │ __weak typeof(self) weakSelf → breaks temporary retain cycle in UIView animateWithDuration: block                  │
  ├─────┼──────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ M3  │ ADSJailTris.m · clearLines runBlock              │ Guard: !_isDead && _isPlaying before spawnBlock — prevents spawn call on reset-during-clear-delay                  │
  ├─────┼──────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ M4  │ ADSJailTris.m · handlePan: dispatch_after blocks │ Added _isPlaying && !_isDead && !_isPaused gate before move validation — blocks queued at 25ms intervals no longer │
  │     │                                                  │  fire into dead/reset state                                                                                        │
  ├─────┼──────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ M5  │ ADSPyEater.m · spawnFood                         │ Guard [self maxX] <= [self minX] || [self maxY] <= [self minY] → eliminates infinite loop on zero-size scene       │
  └─────┴──────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  AUDIO STRUCT (ADSGames.h)

  Added 5 fields: bgmPhase3, bgmTime2, bgmIdx2 (3rd oscillator), sfxSweepRate, sfxSweep2Rate (per-sample pitch sweep on both SFX channels).

  ---
  AUDIO ENGINE (both games)

  ┌────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                 Change                 │                                                               Detail                                                                │
  ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ playSFX / playSFX2                     │ Zero sfxSweepRate / sfxSweep2Rate on every call — prevents stale sweep rate from previous SFX leaking                               │
  ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ playSFXSweep:sweep:dur:                │ New helper — single-osc SFX with pitch sweep (Hz/s)                                                                                 │
  ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ playSFX2Sweep:freq2:sweep1:sweep2:dur: │ New helper — dual-osc SFX with independent sweep per channel                                                                        │
  ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Render block — arpeggio voice          │ 25%-duty pulse wave at mel[bgmIdx] × {1.0, 1.498, 2.0, 1.498} cycling at 16th-note rate (0.0625s JailTris / 0.06s PyEater); amp     │
  │                                        │ 0.007f / 0.006f; mixed into arpSamp alongside existing triangle+square                                                              │
  ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Render block — sweep                   │ Per-sample sfxFreq += sfxSweepRate / sr (clamped ≥20Hz) on each active SFX channel                                                  │
  └────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  SFX retune:

  ┌────────────────┬──────────────────────────┬───────────────────────────────────────────────────────┐
  │     Event      │          Before          │                         After                         │
  ├────────────────┼──────────────────────────┼───────────────────────────────────────────────────────┤
  │ JT hard-drop   │ 90/180 Hz · 0.09s square │ 280Hz → 136Hz sweep −1800 · 0.08s thud                │
  ├────────────────┼──────────────────────────┼───────────────────────────────────────────────────────┤
  │ JT rotate      │ 330/659 Hz · 0.06s       │ 380Hz → 450Hz sweep +1400 · 0.05s chirp               │
  ├────────────────┼──────────────────────────┼───────────────────────────────────────────────────────┤
  │ JT soft-lock   │ 200/400 Hz · 0.06s       │ 220/440 Hz → 165/385Hz sweep −700 · 0.07s thunk       │
  ├────────────────┼──────────────────────────┼───────────────────────────────────────────────────────┤
  │ JT die (no HS) │ 120/60 Hz · 0.5s flat    │ 300/150 Hz → 60Hz sweep −400/−200 · 0.6s falling womp │
  ├────────────────┼──────────────────────────┼───────────────────────────────────────────────────────┤
  │ PE die (no HS) │ 120/60 Hz · 0.55s flat   │ 320/160 Hz → 57Hz sweep −420/−210 · 0.6s falling womp │
  └────────────────┴──────────────────────────┴───────────────────────────────────────────────────────┘

  ---
  GRAPHICS

  ┌─────┬────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │               Scene                │                                                              Change                                                              │
  ├─────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ G1  │ JailTris · showLineClearFX         │ +1 / +2 / +3 score-pop label rises from (w/2+68, h/2) in bar-flash color; fades+drifts upward                                    │
  ├─────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ G2  │ JailTris · clearLines in-game HS   │ "🏆 NEW BEST!" label fades in at top center, drifts up, fades out over 1.12s                                                     │
  │     │ surpass                            │                                                                                                                                  │
  ├─────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ G3  │ JailTris · 4x clear burst          │ 8 gold circles → 12 mixed-color circles {gold, white, orange, cyan}, 3 radii {9, 6, 4}pt, 3 distance tiers {55, 83, 111}pt,      │
  │     │                                    │ staggered durations {0.5, 0.62}s                                                                                                 │
  ├─────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ G4  │ PyEater · food eat                 │ Cyan circle pulse (r=kGridSize×0.65) scales → 2.2× and fades to 0 over 0.12s on bloomNode at eat position                        │
  ├─────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ G5  │ PyEater · update: in-game HS       │ "🏆 NEW BEST!" label (cyan) same rise-and-fade animation as G2                                                                   │
  │     │ surpass                            │                                                                                                                                  │
  ├─────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ G6  │ PyEater · die                      │ gameLayer 4-step shudder (−8,+5 → +16,−10 → −16,+10 → +8,−5 → origin) over 0.19s before death overlay mounts                     │
  └─────┴────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

✻ Cooked for 3m 33s