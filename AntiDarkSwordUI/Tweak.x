// AntiDarkSwordUI/Tweak.x
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>
#include <unistd.h>
#include <substrate.h>

#import "../ADSLogging.h"

@interface WKWebpagePreferences (Private)
@property (nonatomic, assign) BOOL lockdownModeEnabled;
@end

@interface _WKProcessPoolConfiguration : NSObject
@property (nonatomic, assign) BOOL JITEnabled;
@end

@interface WKProcessPool (Private)
@property (nonatomic, readonly) _WKProcessPoolConfiguration *_configuration;
@end

#define PREFS_PATH ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/"] ? @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist" : @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist")

static BOOL prefsLoaded = NO;
static _Atomic BOOL currentProcessRestricted = NO;
static BOOL globalTweakEnabled = NO;
static BOOL globalUASpoofingEnabled = NO;
static NSString *customUAString = @"";
static BOOL shouldSpoofUA = NO;

static BOOL globalDisableJIT = NO;
static BOOL globalDisableJIT15 = NO;
static BOOL globalDisableJS = NO;
static BOOL globalDisableMedia = NO;
static BOOL globalDisableRTC = NO;
static BOOL globalDisableFileAccess = NO;

static BOOL disableJIT = NO;
static BOOL disableJIT15 = NO;
static BOOL disableJS = NO;
static BOOL disableMedia = NO;
static BOOL disableRTC = NO;
static BOOL disableFileAccess = NO;

static BOOL applyDisableJIT = NO;
static BOOL applyDisableJIT15 = NO;
static BOOL applyDisableJS = NO;
static BOOL applyDisableMedia = NO;
static BOOL applyDisableRTC = NO;
static BOOL applyDisableFileAccess = NO;

// Decoy Variables
static BOOL globalDecoyEnabled = NO;
static BOOL isRootlessJB = NO;

// Crash-Free JSON Encoder
static NSString *adsJSONStringLiteral(NSString *str) {
    if (!str || str.length == 0) return @"\"\"";
    NSArray *wrapper = @[str];
    NSData *data = [NSJSONSerialization dataWithJSONObject:wrapper options:0 error:nil];
    if (!data) return @"\"\"";
    NSString *jsonArrayString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (jsonArrayString.length >= 2) {
        return [jsonArrayString substringWithRange:NSMakeRange(1, jsonArrayString.length - 2)];
    }
    return @"\"\"";
}

static void injectUAScript(WKUserContentController *ucc) {
    if (!ucc || !shouldSpoofUA || !customUAString || customUAString.length == 0) return;
    ADSLog(@"[MITIGATION] Injecting UA spoof script. UA: %@", customUAString);

    NSString *jsonUA = adsJSONStringLiteral(customUAString);
    NSString *platform = @"\"iPhone\"";
    if ([customUAString containsString:@"iPad"])       platform = @"\"iPad\"";
    else if ([customUAString containsString:@"Macintosh"]) platform = @"\"MacIntel\"";
    else if ([customUAString containsString:@"Windows"])   platform = @"\"Win32\"";
    else if ([customUAString containsString:@"Android"])   platform = @"\"Linux aarch64\"";
    
    NSString *vendor = @"\"Apple Computer, Inc.\"";
    if ([customUAString containsString:@"Chrome"] || [customUAString containsString:@"Android"]) {
        vendor = @"\"Google Inc.\"";
    }

    NSString *appVersion = customUAString;
    if ([customUAString hasPrefix:@"Mozilla/"]) appVersion = [customUAString substringFromIndex:8];
    NSString *jsonAppVersion = adsJSONStringLiteral(appVersion);

    NSString *jsSource = [NSString stringWithFormat:
        @"(function(){"
         "var d=Object.defineProperty,n=navigator;"
         "d(n,'userAgent',  {get:function(){return %@},configurable:true});"
         "d(n,'appVersion', {get:function(){return %@},configurable:true});"
         "d(n,'platform',   {get:function(){return %@},configurable:true});"
         "d(n,'vendor',     {get:function(){return %@},configurable:true});"
         "})();",
        jsonUA, jsonAppVersion, platform, vendor];
        
    WKUserScript *script = [[WKUserScript alloc] initWithSource:jsSource injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [ucc addUserScript:script];
}

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

static void applyWebKitMitigations(WKWebViewConfiguration *configuration) {
    if (!configuration) return;
    if (applyDisableJS) {
        if ([configuration respondsToSelector:@selector(defaultWebpagePreferences)]) configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) configuration.preferences.javaScriptEnabled = NO;
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)]) configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    }
    if (applyDisableJIT && [configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
        if ([configuration.defaultWebpagePreferences respondsToSelector:@selector(setLockdownModeEnabled:)]) [(id)configuration.defaultWebpagePreferences setLockdownModeEnabled:YES];
    }
    if ((applyDisableJIT15 || applyDisableJIT) && [configuration respondsToSelector:@selector(processPool)]) {
        if ([configuration.processPool respondsToSelector:@selector(_configuration)]) {
            id poolConfig = [(id)configuration.processPool _configuration];
            if ([poolConfig respondsToSelector:@selector(setJITEnabled:)]) [(id)poolConfig setJITEnabled:NO];
        }
    }
    if (applyDisableMedia) {
        if ([configuration respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) configuration.allowsInlineMediaPlayback = NO;
        if ([configuration respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        if ([configuration respondsToSelector:@selector(setAllowsPictureInPictureMediaPlayback:)]) configuration.allowsPictureInPictureMediaPlayback = NO;
    }
    if ([configuration.preferences respondsToSelector:@selector(setValue:forKey:)]) {
        @try {
            if (applyDisableFileAccess) {
                [configuration.preferences setValue:@NO forKey:@"allowFileAccessFromFileURLs"];
                [configuration.preferences setValue:@NO forKey:@"allowUniversalAccessFromFileURLs"];
            }
            if (applyDisableRTC) {
                [configuration.preferences setValue:@NO forKey:@"webGLEnabled"];
                [configuration.preferences setValue:@NO forKey:@"mediaStreamEnabled"]; 
                [configuration.preferences setValue:@NO forKey:@"peerConnectionEnabled"];
            }
        } @catch (NSException *e) {}
    }
    if (shouldSpoofUA) injectUAScript(configuration.userContentController);
}

static void loadPrefs() {
    if (prefsLoaded) return;
    prefsLoaded = YES;

    NSDictionary *prefs = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    
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
        globalDisableJIT = [prefs[@"globalDisableJIT"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableJIT"] boolValue] : NO;
        globalDisableJIT15 = [prefs[@"globalDisableJIT15"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableJIT15"] boolValue] : NO;
        globalDisableJS = [prefs[@"globalDisableJS"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableJS"] boolValue] : NO;
        globalDisableMedia = [prefs[@"globalDisableMedia"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableMedia"] boolValue] : NO;
        globalDisableRTC = [prefs[@"globalDisableRTC"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableRTC"] boolValue] : NO;
        globalDisableFileAccess = [prefs[@"globalDisableFileAccess"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableFileAccess"] boolValue] : NO;
        autoProtectLevel = [prefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)] ? [prefs[@"autoProtectLevel"] integerValue] : 1;
        
        BOOL decoyPref = [prefs[@"corelliumDecoyEnabled"] respondsToSelector:@selector(boolValue)] ? [prefs[@"corelliumDecoyEnabled"] boolValue] : NO;
        globalDecoyEnabled = (globalTweakEnabled && decoyPref); // Global for browser contexts
        
        id customDaemonIDsRaw = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"];
        if ([customDaemonIDsRaw isKindOfClass:[NSArray class]]) activeCustomDaemonIDs = customDaemonIDsRaw;

        id disabledPresetRaw = prefs[@"disabledPresetRules"];
        if ([disabledPresetRaw isKindOfClass:[NSArray class]]) disabledPresetRules = disabledPresetRaw;
        
        id presetUARaw = prefs[@"selectedUAPreset"];
        NSString *presetUA = [presetUARaw isKindOfClass:[NSString class]] ? presetUARaw : nil;
        if (!presetUA || [presetUA isEqualToString:@"NONE"]) presetUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
        
        id manualUARaw = prefs[@"customUAString"];
        NSString *manualUA = [manualUARaw isKindOfClass:[NSString class]] ? manualUARaw : @"";
        if ([presetUA isEqualToString:@"CUSTOM"]) {
            NSString *trimmedUA = [manualUA stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            customUAString = (trimmedUA.length > 0) ? trimmedUA : @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
        } else {
            customUAString = presetUA;
        }
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";
    BOOL isTargetRestricted = NO;
    BOOL isPresetMatch = NO;
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
            @"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.mobilenotes", 
            @"com.apple.iBooks", @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks", 
            @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", 
            @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"
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
            @"net.kortina.labs.Venmo", @"com.yourcompany.PPClient", @"com.robinhood.release.Robinhood", 
            @"com.vilcsak.bitcoin2", @"com.sixdays.trust", @"io.metamask.MetaMask", @"app.phantom.phantom", 
            @"com.chase", @"com.bankofamerica.BofAMobileBanking", @"com.wellsfargo.net.mobilebanking", @"com.citi.citimobile", 
            @"com.capitalone.enterprisemobilebanking", @"com.americanexpress.amelia", @"com.fidelity.iphone", 
            @"com.schwab.mobile", @"com.etrade.mobilepro.iphone", @"com.discoverfinancial.mobile", 
            @"com.usbank.mobilebanking", @"com.monzo.ios", @"com.revolut.iphone", @"com.binance.dev", 
            @"com.kraken.invest", @"com.barclays.ios.bmb", @"com.ally.auto", @"com.navyfederal.navyfederal.mydata", 
            @"com.1debit.ChimeProdApp"
        ];
        NSArray *tier3 = @[]; 
        
        for (int i = 0; i < 2; i++) {
            NSString *target = targetsToCheck[i];
            if (!target || target.length == 0) continue;
            
            NSString *targetMatch = nil;
            if ([tier1 containsObject:target]) targetMatch = target;
            else if (autoProtectLevel >= 2 && [tier2 containsObject:target]) targetMatch = target;
            else if (autoProtectLevel >= 3 && [tier3 containsObject:target]) targetMatch = target;
            
            if (targetMatch && ![disabledPresetRules containsObject:targetMatch]) {
                isTargetRestricted = YES;
                matchedID = targetMatch;
                isPresetMatch = YES;
                break;
            }
        }
    }
    
    currentProcessRestricted = (globalTweakEnabled && isTargetRestricted);
    disableMedia = NO;
    disableRTC = NO;
    BOOL spoofUARule = NO;
    disableJIT = NO;
    disableJIT15 = NO;
    disableJS = NO;
    disableFileAccess = NO;

    if (currentProcessRestricted && isPresetMatch) {
        BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
        disableJIT = isIOS16OrGreater;
        disableJIT15 = !isIOS16OrGreater;
        disableJS = !isIOS16OrGreater;

        NSArray *msgAndMail = @[
            @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.MailCompositionService", 
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.google.Gmail", 
            @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail", 
            @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", 
            @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.apple.Passbook"
        ];
        NSArray *browsers = @[
            @"com.apple.mobilesafari", @"com.apple.SafariViewService", @"com.google.chrome.ios", 
            @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"
        ];
        
        if ([msgAndMail containsObject:matchedID]) {
            disableMedia = YES;
            disableRTC = YES; 
            disableFileAccess = YES; 
            if (![matchedID hasPrefix:@"com.apple."]) spoofUARule = (autoProtectLevel >= 2);
        } else if ([browsers containsObject:matchedID]) {
            if ([matchedID isEqualToString:@"com.apple.mobilesafari"] || [matchedID isEqualToString:@"com.apple.SafariViewService"]) {
                spoofUARule = YES;
            } else {
                spoofUARule = (autoProtectLevel >= 2);
            }
            if (autoProtectLevel >= 3) { 
                disableRTC = YES;
                disableMedia = YES;
            }
        } else if (![matchedID containsString:@"daemon"] && ![matchedID hasPrefix:@"com.apple."]) {
            spoofUARule = (autoProtectLevel >= 2);
        }
    }

    if (currentProcessRestricted && matchedID && prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", matchedID];
        NSDictionary *appRules = prefs[dictKey];
        if (appRules && [appRules isKindOfClass:[NSDictionary class]]) {
            if ([appRules[@"disableJIT"] respondsToSelector:@selector(boolValue)]) disableJIT = [appRules[@"disableJIT"] boolValue];
            if ([appRules[@"disableJIT15"] respondsToSelector:@selector(boolValue)]) disableJIT15 = [appRules[@"disableJIT15"] boolValue];
            if ([appRules[@"disableJS"] respondsToSelector:@selector(boolValue)]) disableJS = [appRules[@"disableJS"] boolValue];
            if ([appRules[@"disableMedia"] respondsToSelector:@selector(boolValue)]) disableMedia = [appRules[@"disableMedia"] boolValue];
            if ([appRules[@"disableRTC"] respondsToSelector:@selector(boolValue)]) disableRTC = [appRules[@"disableRTC"] boolValue];
            if ([appRules[@"disableFileAccess"] respondsToSelector:@selector(boolValue)]) disableFileAccess = [appRules[@"disableFileAccess"] boolValue];
            if ([appRules[@"spoofUA"] respondsToSelector:@selector(boolValue)]) spoofUARule = [appRules[@"spoofUA"] boolValue];
        }
    }

    applyDisableJIT = globalTweakEnabled && (globalDisableJIT || (currentProcessRestricted && disableJIT));
    applyDisableJIT15 = globalTweakEnabled && (globalDisableJIT15 || (currentProcessRestricted && disableJIT15));
    applyDisableJS = globalTweakEnabled && (globalDisableJS || (currentProcessRestricted && disableJS));
    applyDisableMedia = globalTweakEnabled && (globalDisableMedia || (currentProcessRestricted && disableMedia));
    applyDisableRTC = globalTweakEnabled && (globalDisableRTC || (currentProcessRestricted && disableRTC));
    applyDisableFileAccess = globalTweakEnabled && (globalDisableFileAccess || (currentProcessRestricted && disableFileAccess));
    
    shouldSpoofUA = NO;
    if (globalTweakEnabled) {
        if (globalUASpoofingEnabled && customUAString && customUAString.length > 0) shouldSpoofUA = YES;
        else if (currentProcessRestricted && spoofUARule && customUAString && customUAString.length > 0) shouldSpoofUA = YES;
    }

    // Logging restored!
    if (currentProcessRestricted) {
        ADSLog(@"[STATUS] Protection is ACTIVE for this process. JS:%d JIT:%d Media:%d RTC:%d", applyDisableJS, applyDisableJIT, applyDisableMedia, applyDisableRTC);
    } else {
        ADSLog(@"[STATUS] Process is unrestricted. Tweak is dormant here.");
    }
}

static void reloadPrefsNotification() {
    prefsLoaded = NO; 
    loadPrefs();
}

// UI Process Posix Hooks
static int (*orig_access_ui)(const char *path, int amode);
int hook_access_ui(const char *path, int amode) {
    if (globalDecoyEnabled && isRootlessJB && path && strcmp(path, "/usr/libexec/corelliumd") == 0) return 0;
    return orig_access_ui(path, amode);
}

static int (*orig_stat_ui)(const char *path, struct stat *buf);
int hook_stat_ui(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && isRootlessJB && path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        if (buf) { memset(buf, 0, sizeof(struct stat)); buf->st_mode = S_IFREG | 0755; buf->st_uid = 0; buf->st_gid = 0; buf->st_size = 34520; }
        return 0;
    }
    return orig_stat_ui(path, buf);
}

static int (*orig_lstat_ui)(const char *path, struct stat *buf);
int hook_lstat_ui(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && isRootlessJB && path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        if (buf) { memset(buf, 0, sizeof(struct stat)); buf->st_mode = S_IFREG | 0755; buf->st_uid = 0; buf->st_gid = 0; buf->st_size = 34520; }
        return 0;
    }
    return orig_lstat_ui(path, buf);
}

%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if (globalDecoyEnabled && isRootlessJB && [path isEqualToString:@"/usr/libexec/corelliumd"]) return YES;
    return %orig;
}
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (globalDecoyEnabled && isRootlessJB && [path isEqualToString:@"/usr/libexec/corelliumd"]) {
        if (isDirectory) *isDirectory = NO;
        return YES;
    }
    return %orig;
}
%end

// =========================================================
// WEBKIT EXPLOIT MITIGATIONS & ANTI-FINGERPRINTING
// =========================================================

%hook WKWebViewConfiguration
- (void)setUserContentController:(WKUserContentController *)userContentController {
    %orig;
    if (shouldSpoofUA && userContentController) injectUAScript(userContentController);
}
- (void)setApplicationNameForUserAgent:(NSString *)applicationNameForUserAgent {
    if (shouldSpoofUA) return %orig(@"");
    %orig;
}
%end

%hook WKWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    applyWebKitMitigations(configuration);
    WKWebView *webView = %orig(frame, configuration);
    if (webView && shouldSpoofUA && [webView respondsToSelector:@selector(setCustomUserAgent:)]) webView.customUserAgent = customUAString;
    return webView;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    WKWebView *webView = %orig(coder);
    if (!webView) return nil;
    applyWebKitMitigations(webView.configuration);
    if (shouldSpoofUA && [webView respondsToSelector:@selector(setCustomUserAgent:)]) webView.customUserAgent = customUAString;
    return webView;
}
- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    if (applyDisableJS) {
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) self.configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        if ([self.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) self.configuration.preferences.javaScriptEnabled = NO;
    }
    if (shouldSpoofUA) {
        if ([self respondsToSelector:@selector(setCustomUserAgent:)]) self.customUserAgent = customUAString;
        if ([request respondsToSelector:@selector(valueForHTTPHeaderField:)]) {
            NSString *existingUA = [request valueForHTTPHeaderField:@"User-Agent"];
            if (existingUA && ![existingUA isEqualToString:customUAString]) {
                NSMutableURLRequest *mutableReq = [request mutableCopy];
                [mutableReq setValue:customUAString forHTTPHeaderField:@"User-Agent"];
                return %orig(mutableReq);
            }
        }
    }
    return %orig;
}
- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL {
    if (applyDisableJS) {
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) self.configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        if ([self.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) self.configuration.preferences.javaScriptEnabled = NO;
    }
    if (shouldSpoofUA && [self respondsToSelector:@selector(setCustomUserAgent:)]) self.customUserAgent = customUAString;
    return %orig;
}
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *))completionHandler {
    if (applyDisableJS) {
        if (completionHandler) completionHandler(nil, [NSError errorWithDomain:@"AntiDarkSword" code:1 userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}]);
        return;
    }
    %orig;
}
- (void)evaluateJavaScript:(NSString *)javaScriptString inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)contentWorld completionHandler:(void (^)(id, NSError *))completionHandler {
    if (applyDisableJS) {
        if (completionHandler) completionHandler(nil, [NSError errorWithDomain:@"AntiDarkSword" code:1 userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}]);
        return;
    }
    %orig;
}
- (void)setCustomUserAgent:(NSString *)customUserAgent {
    if (shouldSpoofUA) %orig(customUAString);
    else %orig;
}
%end

%hook WKWebpagePreferences
- (void)setAllowsContentJavaScript:(BOOL)allowed {
    if (applyDisableJS && allowed) return %orig(NO);
    %orig;
}
%end

%hook WKPreferences
- (void)setJavaScriptEnabled:(BOOL)enabled {
    if (applyDisableJS && enabled) return %orig(NO);
    %orig;
}
%end

%hookf(JSValueRef, JSEvaluateScript, JSContextRef ctx, JSStringRef script, JSObjectRef thisObject, JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception) {
    if (applyDisableJS) return NULL;
    return %orig(ctx, script, thisObject, sourceURL, startingLineNumber, exception);
}

%hook UIWebView
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    if (applyDisableJS) return @"";
    return %orig;
}
%end

// =========================================================
// %ctor MUST ALWAYS BE AT THE VERY BOTTOM OF THE FILE
// =========================================================
%ctor {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";
    NSArray *ignored = @[@"PosterBoard", @"WeatherPoster", @"PassbookUIService", @"Spotlight", @"Tunnel", @"Preferences", @"cfprefsd", @"searchd", @"druid"];
    if ([ignored containsObject:processName]) return;

    NSString *path = [[NSBundle mainBundle] bundlePath] ?: @"";
    if ([path hasSuffix:@".appex"]) return;

    BOOL isUserApp = [path localizedCaseInsensitiveContainsString:@"/Containers/Bundle/Application/"];
    BOOL isSystemOrJBApp = [path containsString:@"/Applications/"];
    NSArray *allowedServices = @[@"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"];
    BOOL isAllowedService = [allowedServices containsObject:bundleID];

    BOOL isManualOverride = NO;
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    if (prefs) {
        NSArray *customDaemons = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"] ?: @[];
        if ([customDaemons containsObject:bundleID] || [customDaemons containsObject:processName]) isManualOverride = YES;
        if (!isManualOverride && bundleID.length > 0) {
            if ([prefs[[NSString stringWithFormat:@"restrictedApps-%@", bundleID]] boolValue]) isManualOverride = YES;
        }
    }

    if (!isUserApp && !isSystemOrJBApp && !isAllowedService && !isManualOverride) return;

    // Logos reads Top-to-Bottom. %init belongs down here so hooks are parsed first!
    %init;
    isRootlessJB = (access("/var/jb", F_OK) == 0);
    
    MSHookFunction((void *)access, (void *)hook_access_ui, (void **)&orig_access_ui);
    MSHookFunction((void *)stat, (void *)hook_stat_ui, (void **)&orig_stat_ui);
    MSHookFunction((void *)lstat, (void *)hook_lstat_ui, (void **)&orig_lstat_ui);

    loadPrefs();
    ADSLog(@"[INIT] AntiDarkSwordUI loaded into process: %@", processName);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reloadPrefsNotification, CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}
