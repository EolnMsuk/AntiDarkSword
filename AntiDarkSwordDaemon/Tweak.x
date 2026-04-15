// AntiDarkSwordDaemon/Tweak.x
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>
#include <unistd.h>
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

static _Atomic BOOL currentProcessRestricted = NO;
static BOOL globalTweakEnabled              = NO;
static BOOL globalDisableIMessageDL         = NO;
static BOOL globalDecoyEnabled              = NO;
static BOOL disableIMessageDL               = NO;
static BOOL applyDisableIMessageDL          = NO;

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

    // Auto-protection tier matching
    if (!isTargetRestricted && globalTweakEnabled) {
        // Tier 1 & 2 — UIKit apps.  Listed here only so that user-added custom entries that happen
        // to match a preset ID are still handled correctly; the daemon plist will never inject into
        // these processes under normal use.
        NSArray *tier1 = @[
            @"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail",
            @"com.apple.mobilecal", @"com.apple.mobilenotes", @"com.apple.iBooks",
            @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks",
            @"com.apple.Maps", @"com.apple.weather", @"com.apple.SafariViewService",
            @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService",
            @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService",
            @"com.apple.QuickLookDaemon"
        ];
        NSArray *tier2 = @[
            @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram",
            @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph",
            @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio",
            @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line",
            @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.google.GoogleMobile",
            @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser",
            @"com.duckduckgo.mobile.ios", @"pinterest", @"com.tumblr.tumblr",
            @"com.facebook.Facebook", @"com.atebits.Tweetie2", @"com.burbn.instagram",
            @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn", @"com.reddit.Reddit",
            @"com.google.ios.youtube", @"tv.twitch", @"com.google.gemini",
            @"com.openai.chat", @"com.deepseek.chat", @"com.github.stormbreaker.prod",
            @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza",
            @"com.squareup.cash", @"net.kortina.labs.Venmo", @"com.yourcompany.PPClient",
            @"com.robinhood.release.Robinhood", @"com.vilcsak.bitcoin2", @"com.sixdays.trust",
            @"io.metamask.MetaMask", @"app.phantom.phantom", @"com.chase",
            @"com.bankofamerica.BofAMobileBanking", @"com.wellsfargo.net.mobilebanking",
            @"com.citi.citimobile", @"com.capitalone.enterprisemobilebanking",
            @"com.americanexpress.amelia", @"com.fidelity.iphone", @"com.schwab.mobile",
            @"com.etrade.mobilepro.iphone", @"com.discoverfinancial.mobile",
            @"com.usbank.mobilebanking", @"com.monzo.ios", @"com.revolut.iphone",
            @"com.binance.dev", @"com.kraken.invest", @"com.barclays.ios.bmb",
            @"com.ally.auto", @"com.navyfederal.navyfederal.mydata"
        ];
        // Tier 3 — system daemons targeted for zero-click blocking and Corellium spoofing.
        // These are the only processes the daemon plist actually injects into.
        NSArray *tier3 = @[
            @"com.apple.imagent",             @"imagent",
            @"com.apple.apsd",                @"apsd",
            @"com.apple.identityservicesd",   @"identityservicesd",
            @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"
        ];

        for (int i = 0; i < 2; i++) {
            NSString *target = targetsToCheck[i];
            if (!target) continue;

            NSString *targetMatch = nil;
            if ([tier1 containsObject:target]) targetMatch = target;
            else if (autoProtectLevel >= 2 && [tier2 containsObject:target]) targetMatch = target;
            else if (autoProtectLevel >= 3 && [tier3 containsObject:target]) targetMatch = target;

            if (targetMatch && ![disabledPresetRules containsObject:targetMatch]) {
                isTargetRestricted = YES;
                matchedID = targetMatch;
                break;
            }
        }
    }

    currentProcessRestricted = (globalTweakEnabled && isTargetRestricted);

    // Corellium decoy: only active at level 3+ (currentProcessRestricted requires a tier3 match)
    BOOL decoyPref = (prefs && [prefs[@"corelliumDecoyEnabled"] respondsToSelector:@selector(boolValue)])
                     ? [prefs[@"corelliumDecoyEnabled"] boolValue] : NO;
    globalDecoyEnabled = (globalTweakEnabled && decoyPref && currentProcessRestricted);

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

static void reloadDaemonPrefsNotification(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object,
                                          CFDictionaryRef userInfo) {
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
// CORELLIUM HONEYPOT — POSIX FILE PATH SPOOFING
// Spoofs /usr/libexec/corelliumd for rootless installs so
// that advanced payloads checking for the Corellium path
// (at the expected rootful location) see it as present.
// On rootful the binary IS at that path, no spoof needed.
// =========================================================

static int (*orig_access)(const char *path, int amode);
int hook_access(const char *path, int amode) {
    if (globalDecoyEnabled && isRootlessJB &&
        path && strcmp(path, "/usr/libexec/corelliumd") == 0)
        return 0;
    return orig_access(path, amode);
}

static int (*orig_stat)(const char *path, struct stat *buf);
int hook_stat(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && isRootlessJB &&
        path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        if (buf) {
            memset(buf, 0, sizeof(struct stat));
            buf->st_mode = S_IFREG | 0755;
            buf->st_uid  = 0;
            buf->st_gid  = 0;
            buf->st_size = 34520;
        }
        return 0;
    }
    return orig_stat(path, buf);
}

static int (*orig_lstat)(const char *path, struct stat *buf);
int hook_lstat(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && isRootlessJB &&
        path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        if (buf) {
            memset(buf, 0, sizeof(struct stat));
            buf->st_mode = S_IFREG | 0755;
            buf->st_uid  = 0;
            buf->st_gid  = 0;
            buf->st_size = 34520;
        }
        return 0;
    }
    return orig_lstat(path, buf);
}

%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if (globalDecoyEnabled && isRootlessJB &&
        [path isEqualToString:@"/usr/libexec/corelliumd"])
        return YES;
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (globalDecoyEnabled && isRootlessJB &&
        [path isEqualToString:@"/usr/libexec/corelliumd"]) {
        if (isDirectory) *isDirectory = NO;
        return YES;
    }
    return %orig;
}
%end

%ctor {
    %init;

    isRootlessJB = (access("/var/jb", F_OK) == 0);

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
