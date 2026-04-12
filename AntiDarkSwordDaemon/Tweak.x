#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>
#include <unistd.h>
#include <substrate.h>

#import "../ADSLogging.h"

@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

@interface CKAttachmentMessagePartChatItem : NSObject
- (BOOL)_needsPreviewGeneration;
@end

#define PREFS_PATH (access("/var/jb", F_OK) == 0 ? @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist" : @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist")

static _Atomic BOOL currentProcessRestricted = NO;
static BOOL globalTweakEnabled = NO;
static BOOL globalUASpoofingEnabled = NO;
static NSString *customUAString = @"";
static BOOL shouldSpoofUA = NO;
static BOOL globalDecoyEnabled = NO;

static BOOL globalDisableIMessageDL = NO;
static BOOL disableIMessageDL = NO;
static BOOL applyDisableIMessageDL = NO;

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
            if ([item isKindOfClass:[NSString class]] && ![restrictedAppsArray containsObject:item]) {
                [restrictedAppsArray addObject:item];
            }
        }
    }

    for (NSString *key in [prefs allKeys]) {
        if ([key hasPrefix:@"restrictedApps-"] && [prefs[key] respondsToSelector:@selector(boolValue)] && [prefs[key] boolValue]) {
            NSString *appID = [key substringFromIndex:@"restrictedApps-".length];
            if (![restrictedAppsArray containsObject:appID]) [restrictedAppsArray addObject:appID];
        }
    }
}

static void loadPrefs() {
    NSDictionary *prefs = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    }

    if (!prefs || ![prefs isKindOfClass:[NSDictionary class]]) {
        CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            CFDictionaryRef dict = CFPreferencesCopyMultiple(keyList, CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (dict) prefs = (__bridge_transfer NSDictionary *)dict;
            CFRelease(keyList);
        }
    }

    NSInteger autoProtectLevel = 1;
    NSArray *activeCustomDaemonIDs = @[];
    NSArray *disabledPresetRules = @[];
    NSMutableArray *restrictedAppsArray = [NSMutableArray array];
    
    if (prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        parseRestrictedApps(prefs, restrictedAppsArray);
        globalTweakEnabled = [prefs[@"enabled"] respondsToSelector:@selector(boolValue)] ? [prefs[@"enabled"] boolValue] : NO;
        globalUASpoofingEnabled = [prefs[@"globalUASpoofingEnabled"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalUASpoofingEnabled"] boolValue] : NO;
        globalDisableIMessageDL = [prefs[@"globalDisableIMessageDL"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableIMessageDL"] boolValue] : NO;
        
        autoProtectLevel = [prefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)] ? [prefs[@"autoProtectLevel"] integerValue] : 1;
        id customDaemonIDsRaw = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"];
        if ([customDaemonIDsRaw isKindOfClass:[NSArray class]]) activeCustomDaemonIDs = customDaemonIDsRaw;

        id disabledPresetRaw = prefs[@"disabledPresetRules"];
        if ([disabledPresetRaw isKindOfClass:[NSArray class]]) disabledPresetRules = disabledPresetRaw;
        
        id presetUARaw = prefs[@"selectedUAPreset"];
        NSString *presetUA = [presetUARaw isKindOfClass:[NSString class]] ? presetUARaw : nil;
        if (!presetUA || [presetUA isEqualToString:@"NONE"]) {
            presetUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
        }
        
        id manualUARaw = prefs[@"customUAString"];
        NSString *manualUA = [manualUARaw isKindOfClass:[NSString class]] ? manualUARaw : @"";
        if ([presetUA isEqualToString:@"CUSTOM"]) {
            NSString *trimmedUA = [manualUA stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            customUAString = (trimmedUA.length > 0) ? trimmedUA : @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
        } else {
            customUAString = presetUA;
        }
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isTargetRestricted = NO;
    NSString *matchedID = nil;
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
        NSArray *tier1 = @[
            @"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.mobilecal", 
            @"com.apple.mobilenotes", @"com.apple.iBooks", @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks", 
            @"com.apple.Maps", @"com.apple.weather", @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", 
            @"com.apple.QuickLookDaemon"
        ];
        NSArray *tier2 = @[
            @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail",
            @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", @"com.toyopagroup.picaboo", 
            @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line", 
            @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.google.GoogleMobile", @"com.google.chrome.ios", 
            @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios", @"pinterest", 
            @"com.tumblr.tumblr", @"com.facebook.Facebook", @"com.atebits.Tweetie2", @"com.burbn.instagram", 
            @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn", @"com.reddit.Reddit", @"com.google.ios.youtube", 
            @"tv.twitch", @"com.google.gemini", @"com.openai.chat", @"com.deepseek.chat", @"com.github.stormbreaker.prod",
            @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza", @"com.squareup.cash", 
            @"net.kortina.labs.Venmo", @"com.yourcompany.PPClient", @"com.robinhood.release.Robinhood", @"com.vilcsak.bitcoin2", 
            @"com.sixdays.trust", @"io.metamask.MetaMask", @"app.phantom.phantom", @"com.chase", @"com.bankofamerica.BofAMobileBanking", 
            @"com.wellsfargo.net.mobilebanking", @"com.citi.citimobile", @"com.capitalone.enterprisemobilebanking", 
            @"com.americanexpress.amelia", @"com.fidelity.iphone", @"com.schwab.mobile", @"com.etrade.mobilepro.iphone", 
            @"com.discoverfinancial.mobile", @"com.usbank.mobilebanking", @"com.monzo.ios", @"com.revolut.iphone", 
            @"com.binance.dev", @"com.kraken.invest", @"com.barclays.ios.bmb", @"com.ally.auto", @"com.navyfederal.navyfederal.mydata"
        ];
        NSArray *tier3 = @[@"com.apple.imagent", @"imagent", @"networkd", @"apsd", @"identityservicesd"];
        
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
    
    // LIMITATION ENFORCEMENT: Only apply decoy hooks if process is restricted
    BOOL decoyPref = (prefs && [prefs[@"corelliumDecoyEnabled"] respondsToSelector:@selector(boolValue)]) ? [prefs[@"corelliumDecoyEnabled"] boolValue] : NO;
    globalDecoyEnabled = (globalTweakEnabled && decoyPref && currentProcessRestricted);

    BOOL spoofUARule = YES;
    disableIMessageDL = NO;

    NSArray *daemons = @[
        @"com.apple.appstored", @"com.apple.itunesstored", @"com.apple.imagent", @"imagent", 
        @"com.apple.mediaserverd", @"mediaserverd", @"com.apple.networkd", @"networkd", 
        @"com.apple.apsd", @"apsd", @"com.apple.identityservicesd", @"identityservicesd", 
        @"com.apple.nsurlsessiond", @"com.apple.cfnetwork"
    ];

    if (matchedID) {
        if ([daemons containsObject:matchedID]) spoofUARule = NO;
        if ([matchedID isEqualToString:@"com.apple.imagent"] || [matchedID isEqualToString:@"imagent"]) {
            disableIMessageDL = YES;
        }
    } else if (processName) {
        if ([processName containsString:@"daemon"] || [processName hasSuffix:@"d"]) spoofUARule = NO;
    }

    if (currentProcessRestricted && matchedID && prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", matchedID];
        NSDictionary *appRules = prefs[dictKey];
        if (appRules && [appRules isKindOfClass:[NSDictionary class]]) {
            if ([appRules[@"spoofUA"] respondsToSelector:@selector(boolValue)]) spoofUARule = [appRules[@"spoofUA"] boolValue];
            if ([appRules[@"disableIMessageDL"] respondsToSelector:@selector(boolValue)]) disableIMessageDL = [appRules[@"disableIMessageDL"] boolValue];
        }
    }

    applyDisableIMessageDL = globalTweakEnabled && (globalDisableIMessageDL || (currentProcessRestricted && disableIMessageDL));
    shouldSpoofUA = NO;
    
    if (globalTweakEnabled) {
        if (globalUASpoofingEnabled && customUAString && customUAString.length > 0) {
            shouldSpoofUA = YES;
        } else if (currentProcessRestricted && spoofUARule && customUAString && customUAString.length > 0) {
            shouldSpoofUA = YES;
        }
    }
}

%ctor {
    ADSLog(@"[INIT] AntiDarkSwordDaemon loaded into daemon/process: %@", [[NSProcessInfo processInfo] processName]);
    loadPrefs();
    if (currentProcessRestricted) {
        ADSLog(@"[STATUS] Daemon protection is ACTIVE. iMessageDL blocked: %d", applyDisableIMessageDL);
    }
    
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}

%hook NSMutableURLRequest
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (shouldSpoofUA && [field caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
        return %orig(customUAString, field);
    }
    %orig;
}
%end

%hook NSUserDefaults
- (id)objectForKey:(NSString *)defaultName {
    if (shouldSpoofUA && ([defaultName isEqualToString:@"UserAgent"] || [defaultName isEqualToString:@"User-Agent"])) {
        return customUAString;
    }
    return %orig;
}

- (NSString *)stringForKey:(NSString *)defaultName {
    if (shouldSpoofUA && ([defaultName isEqualToString:@"UserAgent"] || [defaultName isEqualToString:@"User-Agent"])) {
        return customUAString;
    }
    return %orig;
}
%end

%hook IMFileTransfer
- (BOOL)isAutoDownloadable {
    if (![self respondsToSelector:@selector(isAutoDownloadable)]) return %orig;

    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Blocked auto-download of an iMessage file transfer.");
        return NO;
    }
    return %orig;
}

- (BOOL)canAutoDownload {
    if (![self respondsToSelector:@selector(canAutoDownload)]) return %orig;

    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Denied canAutoDownload permission for iMessage transfer.");
        return NO;
    }
    return %orig;
}
%end

%hook CKAttachmentMessagePartChatItem
- (BOOL)_needsPreviewGeneration {
    if (applyDisableIMessageDL) return NO;
    return %orig;
}
%end

static int (*orig_access)(const char *path, int amode);
int hook_access(const char *path, int amode) {
    if (globalDecoyEnabled && path && (strcmp(path, "/usr/libexec/corelliumd") == 0 || strcmp(path, "/var/jb/usr/libexec/corelliumd") == 0)) {
        return 0;
    }
    return orig_access(path, amode);
}

static int (*orig_stat)(const char *path, struct stat *buf);
int hook_stat(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && path && (strcmp(path, "/usr/libexec/corelliumd") == 0 || strcmp(path, "/var/jb/usr/libexec/corelliumd") == 0)) {
        if (buf) {
            memset(buf, 0, sizeof(struct stat));
            buf->st_mode = S_IFREG | 0755;
            buf->st_uid = 0;
            buf->st_gid = 0;
            buf->st_size = 34520;
        }
        return 0;
    }
    return orig_stat(path, buf);
}

%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if (globalDecoyEnabled && ([path isEqualToString:@"/usr/libexec/corelliumd"] || [path isEqualToString:@"/var/jb/usr/libexec/corelliumd"])) return YES;
    return %orig;
}
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (globalDecoyEnabled && ([path isEqualToString:@"/usr/libexec/corelliumd"] || [path isEqualToString:@"/var/jb/usr/libexec/corelliumd"])) {
        if (isDirectory) *isDirectory = NO;
        return YES;
    }
    return %orig;
}
%end

%ctor {
    NSString *processName = [[NSProcessInfo processInfo] processName];
    
    // Universal bypass: POSIX hooks in apsd trigger Sandbox/PAC crash-loops
    if (![processName isEqualToString:@"apsd"]) {
        MSHookFunction((void *)access, (void *)hook_access, (void **)&orig_access);
        MSHookFunction((void *)stat, (void *)hook_stat, (void **)&orig_stat);
    } else {
        ADSLog(@"[MITIGATION] Bypassing POSIX hooks for apsd (Crash Prevention)");
    }
}
