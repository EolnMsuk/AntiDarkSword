# 4.9.3 feature port — implementation record

Implemented locally on November 14, 2026. Control remains **4.9.7**.

The user's revised request replaces the earlier focused-repair scope: base the
runtime on the supplied working 4.9.3 source, add manual update checking and
Venmo/crypto donation, and remove automatic update checking. The original
`plan.md` and handoffs are retained as historical evidence, not current behavior.

## Source baseline and explicit differences

- Games (`ADSGames.h`, credits/menu, PyEater, JailTris) and TrollFools runtime are
  byte-identical to the supplied 4.9.3 reference.
- Daemon/UI runtime is restored from that reference with package/preference path
  adaptations only: compile-selected targets and canonical mobile preferences
  with the existing legacy-path fallback.
- RootListController is restored from 4.9.3 with manual Updates, existing donation,
  installed-version display and typed package path adapters.
- Settings commands follow the reference's order and preference timing, including
  inline waits, unchecked child statuses, Cancel reversal and reset/restart flags.
  The later staged transactions, output-capturing runner and audio rewrite were
  removed. This is an intentional baseline restore, not an extension of the prior
  transaction repair.
- Process invocation: absolute executable selected by ADSPaths; literal
  `launchctl`/`killall` argv[0]; NULL spawn attributes and envp; inherited stdio.
  Native plist arguments still use typed `rootfs(jbroot(...))`; rootless retains
  `/var/jb`. No privilege helper or boot-policy change was introduced.
- Installer/removal scripts use 4.9.3's best-effort load/unload sequence and
  remove/purge behavior, retaining fixed compile-selected packaging paths.
- Update checking has one call site, the manual button. Automatic entry checks,
  the daily gate, clock/boot timestamps and lock-file bookkeeping are removed.
  Network request deadlines remain; they are not an update schedule.
- Donation helper bytes are unchanged, including EolnMsuk Venmo and all eight
  coin/network/address tuples. Exact INFO dictionaries/order are preserved;
  every other Root.plist row matches the reference.
- Five-target build workflow, target configuration, ADSPaths, dependencies and
  native signing files are retained. Native Roothide remains unverified and is
  separate from a rootless package converted by a patcher.

## Latest device evidence and limits

After the earlier NULL-envp/basename change, the user still observed:
ordinary rootless unload exited normally with status 1 and empty output; native
Roothide unload terminated by signal 6 with a plist-patching failure. Thus that
compatibility change was insufficient. No underlying command cause is established.

The 4.9.3 source saves the Honeypot preference without gating on unload status.
Restoring it removes the later refusal to save OFF, but does not prove that
launchd removed the job. Entering Level 3 sets the Honeypot preference ON in the
reference. Install/boot registration is independent of preferences; deleting a
preference file does not unload a job. RunAtLoad/KeepAlive remains unchanged.

The supplied source folder contains no later Process Control Failed alerts.
A fresh build of the reference would not produce those particular alerts from
its settings code. Source review cannot guarantee a rebuild matches the old
installed binary/toolchain or that an unchecked child command succeeds.

## Checks actually run

- Focused source comparison against the untouched 4.9.3 reference.
- Starting snapshot comparison: 28 changed files, four removed files (all backed
  up), 115 unchanged project/reference files before adding this record.
- Parsed eight relevant plists and two JSON files.
- Exact INFO dictionary/order and all other rows compared structurally.
- Donation helper, workflow, path helper, target configuration and control hashes
  match the session start. Reference project hashes remain unchanged.
- `python -B scripts/version.py sync`: updated the current depiction notes only.
- `python -B scripts/version.py check`: metadata matches 4.9.7.
- `python -B scripts/check_sources.py`: updater and donation pass; controller and
  all three game files fail on missing `arm_neon.h` in the supplied checker
  dependencies. The checker source-count expectation was changed from eight to
  six to match the actual bundle list; no dependency checks were bypassed.
- Limited supplemental controller parse: 0 errors, one signedness warning at
  line 1004. The game import was replaced only in memory by its exact preferences
  macro. This is not a full-script pass.
- `arm_neon.h` is an ARM compiler intrinsic header, absent from the supplied
  reference and local checker dependencies. Both game versions import the same
  SDK chain. The local missing header does not diagnose a device game defect.
- No build, package/preparation helper, dependency installation, network request,
  updater run, Git mutation or device action was performed.

The syntax checks do not validate Logos, linking, signatures, all target branches,
bootstrap privileges or runtime behavior.

## Review artifacts

- Starting source/docs snapshot:
  `local-backups/before-4.9.3-feature-port-2026-11-14.zip`
- Small runtime/INFO diff against 4.9.3:
  `local-backups/4.9.3-runtime-feature-diff.patch`
- Local backups are excluded by `.gitignore`.
- The reference `AntiDarkSword-4.9.3`, protected dependencies and generated trees
  were not edited.

## Files changed in this port

- `.gitignore`
- `AntiDarkSwordDaemon/README.md`
- `AntiDarkSwordDaemon/Tweak.x`
- `AntiDarkSwordTF/README.md`
- `AntiDarkSwordTF/Tweak.x`
- `AntiDarkSwordUI/README.md`
- `AntiDarkSwordUI/Tweak.x`
- `CorelliumDecoy/README.md`
- `ProjectStructure.md`
- `README.md`
- `antidarkswordprefs/ADSCreditsMenu.m`
- `antidarkswordprefs/ADSGames.h`
- `antidarkswordprefs/ADSJailTris.m`
- `antidarkswordprefs/ADSPyEater.m`
- `antidarkswordprefs/ADSUpdateChecker.h`
- `antidarkswordprefs/ADSUpdateChecker.m`
- `antidarkswordprefs/Makefile`
- `antidarkswordprefs/README.md`
- `antidarkswordprefs/Resources/Root.plist`
- `antidarkswordprefs/RootListController.m`
- `changelog.md`
- `compatibility.md`
- `depiction.json`
- `docs/building.md`
- `docs/validation.md`
- `layout/DEBIAN/postinst`
- `layout/DEBIAN/prerm`
- `scripts/check_sources.py`

Added: this implementation record.

Removed from the active source tree, preserved in the backup:

- `antidarkswordprefs/ADSAudio.h`
- `antidarkswordprefs/ADSAudio.m`
- `antidarkswordprefs/ADSProcessRunner.h`
- `antidarkswordprefs/ADSProcessRunner.m`

Use the full updated working tree for the next build so the six-file source
list, restored game sources and removals stay together.

## User-run regression matrix

Build/test ordinary Dopamine rootless first. Validate patcher-converted rootless
and native Roothide separately when available; one route does not verify another.

| Scenario | Expected behavior or observation | Result |
|---|---|---|
| Level 1/2, master enable/disable, Save and Cancel | Matches supplied 4.9.3 flow; settings remain usable | Pending |
| Enter Level 3, turn Honeypot OFF, leave/reopen pane, Save | OFF preference persists; separately observe whether the job actually stops | Pending |
| Level/Honeypot edits while master OFF | Matches reference behavior; this port does not claim the removed no-command optimization | Pending |
| Respring, userspace reboot, Reset | Reference command flow; verify actual restart and preference reset on device | Pending |
| Already registered/absent job; command failure | Compare preference result with actual job state; no success inferred merely from absence of an alert | Pending |
| Protected/unprotected apps and four daemons | Reference mitigation, preset/plugin and custom-rule behavior | Pending |
| Open/reopen settings without tapping Updates | No update request | Pending |
| Updates button, repeated taps, offline/error/newer/up-to-date result | One in-flight request, correct manual feedback and installed-version comparison | Pending |
| INFO, Venmo, eight crypto wallets | Exact labels/order, destination, copy feedback and Cancel | Pending |
| Credits, PyEater, JailTris, audio, TrollFools and other package targets | Reference runtime behavior | Pending |

For command diagnosis, retain the package route, installed tool/bootstrap builds,
actual operation, normal exit status or signal, and any output. Rootless status 1
must not be described as the native Roothide signal-6 failure.

