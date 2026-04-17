// AntiDarkSwordDaemon/Tweak.x
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>
#include <substrate.h>

#import "../ADSLogging.h"

// =========================================================
// PRIVATE INTERFACES — iMessage transfer blocking
// =========================================================
@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

// Pure C check — safe for %ctor
static BOOL isRootlessJB = NO;

// Returns the correct prefs path for the active jailbreak type.
// Relies on isRootlessJB being set in %ctor before first use.
static NSString *ads_prefs_path(void) {
    return isRootlessJB
        ? @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"
        : @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist";
}

static _Atomic BOOL prefsLoaded             = NO;
static _Atomic BOOL currentProcessRestricted = NO;
static _Atomic BOOL globalTweakEnabled       = NO;
static _Atomic BOOL globalDisableIMessageDL  = NO;
static _Atomic BOOL globalDecoyEnabled       = NO;
static _Atomic BOOL disableIMessageDL        = NO;
static _Atomic BOOL applyDisableIMessageDL   = NO;
static _Atomic BOOL countersEnabled          = NO;
static _Atomic time_t lastProbeTime          = 0;

static void parseRestrictedApps(NSDictionary *prefs, NSMutableArray *restrictedAppsArray) {
    id restrictedAppsRaw = prefs[@"restrictedApps"];
    if ([restrictedAppsRaw isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in [restrictedAppsRaw allKeys]) {
            if ([restrictedAppsRaw[key] respondsToSelector:@selector(boolValue)] && [restrictedAppsRaw[key] boolValue]) {
                if (![restrictedAppsArray containsObject:key]) [restrictedAppsArray addObject:key];
            }
        }
    } else if ([restrictedAppsRaw isKindOfClass:[NSArray class]]) {
        for (id item in restrictedAppsRaw) {
            if ([item isKindOfClass:[NSString class]] && ![restrictedAppsArray containsObject:item])
                [restrictedAppsArray addObject:item];
        }
    }

    for (NSString *key in [prefs allKeys]) {
        if ([key hasPrefix:@"restrictedApps-"] &&
            [prefs[key] respondsToSelector:@selector(boolValue)] && [prefs[key] boolValue]) {
            NSString *appID = [key substringFromIndex:@"restrictedApps-".length];
            if (![restrictedAppsArray containsObject:appID]) [restrictedAppsArray addObject:appID];
        }
    }
}

static void loadPrefs() {
    // CAS gate — same pattern as the UI tweak.
    // reloadDaemonPrefsNotification resets prefsLoaded before calling back in.
    BOOL expected = NO;
    if (!atomic_compare_exchange_strong(&prefsLoaded, &expected, YES)) return;

    NSDictionary *prefs = nil;
    NSString *prefsFilePath = ads_prefs_path();
    if ([[NSFileManager defaultManager] fileExistsAtPath:prefsFilePath]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:prefsFilePath];
    }

    if (!prefs || ![prefs isKindOfClass:[NSDictionary class]]) {
        CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("com.eolnmsuk.antidarkswordprefs"),
                                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            CFDictionaryRef dict = CFPreferencesCopyMultiple(keyList, CFSTR("com.eolnmsuk.antidarkswordprefs"),
                                                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (dict) prefs = (__bridge_transfer NSDictionary *)dict;
            CFRelease(keyList);
        }
    }

    NSInteger autoProtectLevel         = 1;
    NSArray  *activeCustomDaemonIDs    = @[];
    NSArray  *disabledPresetRules      = @[];
    NSMutableArray *restrictedAppsArray = [NSMutableArray array];

    if (prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        parseRestrictedApps(prefs, restrictedAppsArray);
        globalTweakEnabled       = [prefs[@"enabled"] respondsToSelector:@selector(boolValue)]               ? [prefs[@"enabled"] boolValue]               : NO;
        globalDisableIMessageDL  = [prefs[@"globalDisableIMessageDL"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableIMessageDL"] boolValue] : NO;
        autoProtectLevel         = [prefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)]    ? [prefs[@"autoProtectLevel"] integerValue]    : 1;

        id customDaemonIDsRaw = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"];
        if ([customDaemonIDsRaw isKindOfClass:[NSArray class]]) activeCustomDaemonIDs = customDaemonIDsRaw;

        id disabledPresetRaw = prefs[@"disabledPresetRules"];
        if ([disabledPresetRaw isKindOfClass:[NSArray class]]) disabledPresetRules = disabledPresetRaw;
    }

    NSString *bundleID    = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isTargetRestricted = NO;
    NSString *matchedID   = nil;
    NSString *targetsToCheck[] = { bundleID, processName };

    // Check custom / manually-added daemon IDs first
    for (int i = 0; i < 2; i++) {
        NSString *target = targetsToCheck[i];
        if (!target) continue;
        if ([activeCustomDaemonIDs containsObject:target] || [restrictedAppsArray containsObject:target]) {
            isTargetRestricted = YES;
            matchedID = target;
            break;
        }
    }

    // Auto-protection tier matching — only tier3 daemon IDs are ever present in
    // processes the daemon plist injects into. Tier1/2 UIKit app IDs are handled
    // exclusively by AntiDarkSwordUI and have no role here.
    if (!isTargetRestricted && globalTweakEnabled) {
        NSArray *tier3 = @[
            @"com.apple.imagent",             @"imagent",
            @"com.apple.apsd",                @"apsd",
            @"com.apple.identityservicesd",   @"identityservicesd",
            @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"
        ];

        // A daemon is disabled if ANY of its known aliases (short process name OR
        // bundle-ID prefix) appears in disabledPresetRules. Without this cross-alias
        // check, disabling "apsd" via the UI (which stores the short name) would not
        // suppress the hook when the process reports its bundleID "com.apple.apsd"
        // first in the targetsToCheck loop.
        BOOL isDisabledByUser = NO;
        for (int i = 0; i < 2; i++) {
            if (targetsToCheck[i] && [disabledPresetRules containsObject:targetsToCheck[i]]) {
                isDisabledByUser = YES;
                break;
            }
        }

        if (!isDisabledByUser) {
            for (int i = 0; i < 2; i++) {
                NSString *target = targetsToCheck[i];
                if (!target) continue;

                if (autoProtectLevel >= 3 && [tier3 containsObject:target]) {
                    isTargetRestricted = YES;
                    matchedID = target;
                    break;
                }
            }
        }
    }

    currentProcessRestricted = (globalTweakEnabled && isTargetRestricted);

    // Corellium decoy: only active at level 3+ (currentProcessRestricted requires a tier3 match)
    BOOL decoyPref = (prefs && [prefs[@"corelliumDecoyEnabled"] respondsToSelector:@selector(boolValue)])
                     ? [prefs[@"corelliumDecoyEnabled"] boolValue] : NO;
    globalDecoyEnabled = (globalTweakEnabled && decoyPref && currentProcessRestricted);
    countersEnabled    = (prefs && [prefs[@"countersEnabled"] respondsToSelector:@selector(boolValue)])
                         ? [prefs[@"countersEnabled"] boolValue] : NO;

    // iMessage auto-download blocking applies to imagent and IMDPersistenceAgent by default.
    // identityservicesd / apsd are included via tier3 for Corellium spoofing only;
    // IMCore is not guaranteed to load there so the hook simply won't fire — safe.
    disableIMessageDL = NO;
    if (matchedID) {
        if ([matchedID isEqualToString:@"com.apple.imagent"]             ||
            [matchedID isEqualToString:@"imagent"]                       ||
            [matchedID isEqualToString:@"com.apple.IMDPersistenceAgent"] ||
            [matchedID isEqualToString:@"IMDPersistenceAgent"]) {
            disableIMessageDL = YES;
        }
    }

    // Per-target rule override from preferences
    if (currentProcessRestricted && matchedID && prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", matchedID];
        NSDictionary *appRules = prefs[dictKey];
        if (appRules && [appRules isKindOfClass:[NSDictionary class]]) {
            if ([appRules[@"disableIMessageDL"] respondsToSelector:@selector(boolValue)])
                disableIMessageDL = [appRules[@"disableIMessageDL"] boolValue];
        }
    }

    applyDisableIMessageDL = globalTweakEnabled &&
                             (globalDisableIMessageDL || (currentProcessRestricted && disableIMessageDL));
}

static void reloadDaemonPrefsNotification(CFNotificationCenterRef center __unused,
                                          void *observer __unused,
                                          CFStringRef name __unused,
                                          const void *object __unused,
                                          CFDictionaryRef userInfo __unused) {
    prefsLoaded = NO;
    loadPrefs();
}

// =========================================================
// iMESSAGE ZERO-CLICK MITIGATIONS
// =========================================================

%hook IMFileTransfer
- (BOOL)isAutoDownloadable {
    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Blocked auto-download of iMessage file transfer.");
        return NO;
    }
    return %orig;
}

- (BOOL)canAutoDownload {
    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Denied canAutoDownload for iMessage transfer.");
        return NO;
    }
    return %orig;
}
%end

// =========================================================
// CORELLIUM PROBE COUNTER
// Debounced — collapses the rapid access+stat+lstat burst
// that a single probe event generates into one count.
// Fires for both rootless (spoof path) and rootful (real
// binary present, but we still detect the probe call).
// =========================================================

static void ads_increment_probe_counter(void) {
    if (!countersEnabled) return;
    time_t now = time(NULL);
    time_t prev = atomic_load(&lastProbeTime);
    if (now - prev < 2) return;
    if (!atomic_compare_exchange_strong(&lastProbeTime, &prev, now)) return;

    CFPreferencesAppSynchronize(CFSTR("com.eolnmsuk.antidarkswordprefs"));
    CFPropertyListRef val = CFPreferencesCopyValue(
        CFSTR("corelliumProbeCount"),
        CFSTR("com.eolnmsuk.antidarkswordprefs"),
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    NSInteger count = 0;
    if (val) {
        CFNumberGetValue((CFNumberRef)val, kCFNumberNSIntegerType, &count);
        CFRelease(val);
    }
    NSInteger newVal = count + 1;
    CFNumberRef newCount = CFNumberCreate(NULL, kCFNumberNSIntegerType, &newVal);
    CFPreferencesSetValue(
        CFSTR("corelliumProbeCount"),
        newCount,
        CFSTR("com.eolnmsuk.antidarkswordprefs"),
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    CFRelease(newCount);
    CFPreferencesAppSynchronize(CFSTR("com.eolnmsuk.antidarkswordprefs"));

    // Separate notification so Settings.app refreshes the counter cell
    // without triggering a full prefs reload in all other tweaks.
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.eolnmsuk.antidarkswordprefs/counter"),
        NULL, NULL, YES);

    ADSLog(@"[COUNTER] Corellium probe detected. Total: %ld", (long)newVal);
}

// =========================================================
// CORELLIUM HONEYPOT — POSIX FILE PATH SPOOFING
// Spoofs /usr/libexec/corelliumd for rootless installs so
// that advanced payloads checking for the Corellium path
// (at the expected rootful location) see it as present.
// On rootful the binary IS at that path, no spoof needed.
// =========================================================

static int (*orig_access)(const char *path, int amode);
int hook_access(const char *path, int amode) {
    if (globalDecoyEnabled && path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        ads_increment_probe_counter();
        if (isRootlessJB) return 0;
    }
    return orig_access(path, amode);
}

static int (*orig_stat)(const char *path, struct stat *buf);
int hook_stat(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        ads_increment_probe_counter();
        if (isRootlessJB) {
            if (buf) {
                memset(buf, 0, sizeof(struct stat));
                buf->st_dev     = 1;          // root filesystem device
                buf->st_ino     = 0x00c12a7f; // plausible inode
                buf->st_mode    = S_IFREG | 0755;
                buf->st_nlink   = 1;
                buf->st_uid     = 0;
                buf->st_gid     = 0;
                buf->st_size    = 34520;
                buf->st_blksize = 4096;
                buf->st_blocks  = 72; // 9 × 4096-byte APFS blocks in 512-byte units
            }
            return 0;
        }
    }
    return orig_stat(path, buf);
}

static int (*orig_lstat)(const char *path, struct stat *buf);
int hook_lstat(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        ads_increment_probe_counter();
        if (isRootlessJB) {
            if (buf) {
                memset(buf, 0, sizeof(struct stat));
                buf->st_dev     = 1;
                buf->st_ino     = 0x00c12a7f;
                buf->st_mode    = S_IFREG | 0755;
                buf->st_nlink   = 1;
                buf->st_uid     = 0;
                buf->st_gid     = 0;
                buf->st_size    = 34520;
                buf->st_blksize = 4096;
                buf->st_blocks  = 72;
            }
            return 0;
        }
    }
    return orig_lstat(path, buf);
}

%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if (globalDecoyEnabled && [path isEqualToString:@"/usr/libexec/corelliumd"]) {
        ads_increment_probe_counter();
        if (isRootlessJB) return YES;
    }
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (globalDecoyEnabled && [path isEqualToString:@"/usr/libexec/corelliumd"]) {
        ads_increment_probe_counter();
        if (isRootlessJB) {
            if (isDirectory) *isDirectory = NO;
            return YES;
        }
    }
    return %orig;
}
%end

%ctor {
    // isRootlessJB must be set before %init so that the NSFileManager hook
    // has the correct value the instant it becomes active.
    isRootlessJB = (access("/var/jb", F_OK) == 0);

    %init;

    ADSLog(@"[INIT] AntiDarkSwordDaemon loaded into: %@",
           [[NSProcessInfo processInfo] processName]);
    loadPrefs();

    if (currentProcessRestricted) {
        ADSLog(@"[STATUS] Daemon protection ACTIVE. iMessageDL blocked: %d",
               applyDisableIMessageDL);
    }

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)reloadDaemonPrefsNotification,
        CFSTR("com.eolnmsuk.antidarkswordprefs/saved"),
        NULL, CFNotificationSuspensionBehaviorCoalesce);

    // Hooks check globalDecoyEnabled at call time; install unconditionally
    // so pref changes take effect immediately without re-hooking.
    MSHookFunction((void *)access, (void *)hook_access, (void **)&orig_access);
    MSHookFunction((void *)stat,   (void *)hook_stat,   (void **)&orig_stat);
    MSHookFunction((void *)lstat,  (void *)hook_lstat,  (void **)&orig_lstat);
}
