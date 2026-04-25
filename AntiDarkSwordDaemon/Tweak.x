// AntiDarkSwordDaemon/Tweak.x
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <unistd.h>
#include <time.h>
#include <substrate.h>

#import "../ADSLogging.h"

@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

static BOOL isRootlessJB = NO;

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
static dispatch_queue_t ads_counter_queue    = nil;

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
    BOOL expected = NO;
    if (!atomic_compare_exchange_strong(&prefsLoaded, &expected, YES)) return;

    NSDictionary *prefs = nil;
    NSString *prefsFilePath = ads_prefs_path();
    if ([[NSFileManager defaultManager] fileExistsAtPath:prefsFilePath])
        prefs = [NSDictionary dictionaryWithContentsOfFile:prefsFilePath];

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
        globalTweakEnabled       = [prefs[@"enabled"] respondsToSelector:@selector(boolValue)]
                                   ? [prefs[@"enabled"] boolValue] : NO;
        globalDisableIMessageDL  = [prefs[@"globalDisableIMessageDL"] respondsToSelector:@selector(boolValue)]
                                   ? [prefs[@"globalDisableIMessageDL"] boolValue] : NO;
        autoProtectLevel         = [prefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)]
                                   ? [prefs[@"autoProtectLevel"] integerValue] : 1;

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

    for (int i = 0; i < 2; i++) {
        NSString *target = targetsToCheck[i];
        if (!target) continue;
        if ([activeCustomDaemonIDs containsObject:target] || [restrictedAppsArray containsObject:target]) {
            isTargetRestricted = YES;
            matchedID = target;
            break;
        }
    }

    if (!isTargetRestricted && globalTweakEnabled) {
        NSArray *tier3 = @[
            @"com.apple.imagent",             @"imagent",
            @"com.apple.apsd",                @"apsd",
            @"com.apple.identityservicesd",   @"identityservicesd",
            @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"
        ];

        // Cross-alias check: disabling "apsd" via UI stores the short name, but the process
        // may first report its bundleID "com.apple.apsd" — both aliases must be checked.
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

    BOOL decoyPref = (prefs && [prefs[@"corelliumDecoyEnabled"] respondsToSelector:@selector(boolValue)])
                     ? [prefs[@"corelliumDecoyEnabled"] boolValue] : NO;
    globalDecoyEnabled = (globalTweakEnabled && decoyPref && currentProcessRestricted);
    countersEnabled    = (prefs && [prefs[@"countersEnabled"] respondsToSelector:@selector(boolValue)])
                         ? [prefs[@"countersEnabled"] boolValue] : NO;

    // identityservicesd/apsd: Corellium spoof only — IMCore not guaranteed to load there,
    // so the IMFileTransfer hook simply won't fire; safe to include in tier3.
    disableIMessageDL = NO;
    if (matchedID) {
        if ([matchedID isEqualToString:@"com.apple.imagent"]             ||
            [matchedID isEqualToString:@"imagent"]                       ||
            [matchedID isEqualToString:@"com.apple.IMDPersistenceAgent"] ||
            [matchedID isEqualToString:@"IMDPersistenceAgent"]) {
            disableIMessageDL = YES;
        }
    }

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

static void ads_increment_probe_counter(void) {
    if (!countersEnabled) return;
    time_t now = time(NULL);
    time_t prev = atomic_load(&lastProbeTime);
    if (now - prev < 2) return;
    // CAS collapses the rapid access+stat+lstat burst from a single probe into one count,
    // even before the async block has executed.
    if (!atomic_compare_exchange_strong(&lastProbeTime, &prev, now)) return;

    // Async dispatch on a serial queue prevents deadlock: this fires inside POSIX hooks called
    // from apsd, which calls cfprefsd synchronously. Calling CFPreferences here on the same
    // thread creates an apsd→cfprefsd→apsd cycle that blocks push notification delivery.
    // CFPreferencesSynchronize (not CFPreferencesAppSynchronize) targets kCFPreferencesAnyHost
    // to match the host key used by SetValue/CopyValue, ensuring the value reaches the plist.
    if (!ads_counter_queue) return;
    dispatch_async(ads_counter_queue, ^{
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
        // Flush the any-host layer — must match the user/host pair used by SetValue.
        CFPreferencesSynchronize(
            CFSTR("com.eolnmsuk.antidarkswordprefs"),
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost);

        // Separate notification so Settings.app refreshes the counter cell without
        // triggering a full prefs reload across all other tweaks.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.eolnmsuk.antidarkswordprefs/counter"),
            NULL, NULL, YES);

        ADSLog(@"[COUNTER] Corellium probe detected. Total: %ld", (long)newVal);
    });
}

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);

static const char     kADSSpoofModel[] = "iPhone15,2";
static struct timeval ads_spoofed_boottime;

// Thread-local re-entrancy guard: GCD queries sysctl (e.g. hw.ncpu) during dispatch_async
// enqueue on the same thread. Without this, ads_increment_probe_counter → dispatch_async
// → sysctl → hook → dispatch_async → ... causes a stack overflow.
static __thread BOOL _ads_sysctl_active = NO;

// Two-pass sysctl contract:
//   pass 1 — oldp == NULL: caller queries required size; set *oldlenp, return 0.
//   pass 2 — oldp != NULL: caller supplies buffer of *oldlenp bytes; validate before writing.
// Writing without validating *oldlenp corrupts the caller's heap/stack.
static int ads_spoof_bytes(const void *src, size_t required,
                           void *oldp, size_t *oldlenp) {
    if (oldp) {
        size_t avail = oldlenp ? *oldlenp : 0;
        if (avail < required) {
            if (oldlenp) *oldlenp = required;
            errno = ENOMEM;
            return -1;
        }
        memcpy(oldp, src, required);
    }
    if (oldlenp) *oldlenp = required;
    return 0;
}

int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (_ads_sysctl_active || !globalDecoyEnabled || !name)
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);

    if (strcmp(name, "hw.model") == 0 || strcmp(name, "hw.machine") == 0) {
        _ads_sysctl_active = YES;
        ads_increment_probe_counter();
        _ads_sysctl_active = NO;
        return ads_spoof_bytes(kADSSpoofModel, sizeof(kADSSpoofModel), oldp, oldlenp);
    }
    if (strcmp(name, "hw.cpusubtype") == 0) {
        _ads_sysctl_active = YES;
        ads_increment_probe_counter();
        _ads_sysctl_active = NO;
        static const uint32_t kSubtype = 2; // CPU_SUBTYPE_ARM64E
        return ads_spoof_bytes(&kSubtype, sizeof(kSubtype), oldp, oldlenp);
    }
    if (strcmp(name, "kern.boottime") == 0) {
        _ads_sysctl_active = YES;
        ads_increment_probe_counter();
        _ads_sysctl_active = NO;
        return ads_spoof_bytes(&ads_spoofed_boottime, sizeof(ads_spoofed_boottime), oldp, oldlenp);
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (_ads_sysctl_active || !globalDecoyEnabled || !name || namelen < 2)
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);

    if (name[0] == CTL_HW && (name[1] == HW_MODEL || name[1] == HW_MACHINE)) {
        _ads_sysctl_active = YES;
        ads_increment_probe_counter();
        _ads_sysctl_active = NO;
        return ads_spoof_bytes(kADSSpoofModel, sizeof(kADSSpoofModel), oldp, oldlenp);
    }
    if (name[0] == CTL_KERN && name[1] == KERN_BOOTTIME) {
        _ads_sysctl_active = YES;
        ads_increment_probe_counter();
        _ads_sysctl_active = NO;
        return ads_spoof_bytes(&ads_spoofed_boottime, sizeof(ads_spoofed_boottime), oldp, oldlenp);
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static int (*orig_access)(const char *path, int amode);
int hook_access(const char *path, int amode) {
    if (globalDecoyEnabled && path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        ads_increment_probe_counter();
        if (isRootlessJB) return 0;
    }
    return orig_access(path, amode);
}

// Fills buf with a plausible stat for the decoy corelliumd binary.
// Timestamps are derived from ads_spoofed_boottime so they are internally
// consistent: birth ≈ one week before "boot", access ≈ 30 s after "boot".
// Zero timestamps (epoch) are immediately detectable by any detector that
// compares st_birthtimespec against system uptime or install history.
static void ads_fill_corellium_stat(struct stat *buf) {
    if (!buf) return;
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

    // Binary was "installed" one week before boot; last accessed 30 s after boot.
    time_t installTime = ads_spoofed_boottime.tv_sec - (86400 * 7);
    time_t accessTime  = ads_spoofed_boottime.tv_sec + 30;
    buf->st_birthtimespec.tv_sec = installTime;
    buf->st_ctimespec.tv_sec     = installTime;
    buf->st_mtimespec.tv_sec     = installTime;
    buf->st_atimespec.tv_sec     = accessTime;
}

static int (*orig_stat)(const char *path, struct stat *buf);
int hook_stat(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        ads_increment_probe_counter();
        if (isRootlessJB) {
            ads_fill_corellium_stat(buf);
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
            ads_fill_corellium_stat(buf);
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
    // Must be set before %init so NSFileManager hook has the correct value the instant it becomes active.
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

    // Queue must exist before POSIX hooks install so ads_increment_probe_counter() is safe immediately.
    ads_counter_queue = dispatch_queue_create("com.eolnmsuk.ads.counter", DISPATCH_QUEUE_SERIAL);

    // Stable spoofed boot time: 3–4 h before process start, pid-seeded for per-process variation.
    time_t _t = time(NULL);
    ads_spoofed_boottime = (struct timeval){ .tv_sec = _t - 10800 - (getpid() % 3600), .tv_usec = 0 };

    // Installed unconditionally; globalDecoyEnabled checked at call time so pref changes
    // take effect without re-hooking.
    MSHookFunction((void *)access,       (void *)hook_access,       (void **)&orig_access);
    MSHookFunction((void *)stat,         (void *)hook_stat,         (void **)&orig_stat);
    MSHookFunction((void *)lstat,        (void *)hook_lstat,        (void **)&orig_lstat);
    MSHookFunction((void *)sysctl,       (void *)hook_sysctl,       (void **)&orig_sysctl);
    MSHookFunction((void *)sysctlbyname, (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname);
}
