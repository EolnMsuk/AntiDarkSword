// AntiDarkSwordUI/Tweak.x
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CoreFoundation/CoreFoundation.h>
#include <unistd.h>
#include <stdatomic.h>
#include <objc/runtime.h>

#import "../ADSLogging.h"

// lockdownModeEnabled became public in iOS 16 (SDK 160000+); forward-declare only for older SDKs.
#if __IPHONE_OS_VERSION_MAX_ALLOWED < 160000
@interface WKWebpagePreferences (Private)
@property (nonatomic, assign) BOOL lockdownModeEnabled;
@end
#endif

#if __IPHONE_OS_VERSION_MAX_ALLOWED < 140000
@interface WKWebpagePreferences (iOS14)
@property (nonatomic, assign) BOOL allowsContentJavaScript;
@end
#endif

@interface _WKProcessPoolConfiguration : NSObject
@property (nonatomic, assign) BOOL JITEnabled;
@end

@interface WKProcessPool (Private)
@property (nonatomic, readonly) _WKProcessPoolConfiguration *_configuration;
@end

// IMFileTransfer lives in IMCore; CKAttachmentMessagePartChatItem in ChatKit.
// Both load in com.apple.MobileSMS and related iMessage UI processes.
@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

@interface CKAttachmentMessagePartChatItem : NSObject
- (BOOL)_needsPreviewGeneration;
- (NSURL *)fullSizeImageURL;
@end

static BOOL isRootlessJB = NO;
// Set in %ctor when the current process is an app extension; holds the parent app bundle ID.
static NSString *currentExtensionParentBundleID = nil;

static NSString *ads_prefs_path(void) {
    return isRootlessJB
        ? @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"
        : @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist";
}

// Resolves the parent app bundle ID for an app extension process.
// Extension path pattern: …/Parent.app/PlugIns/Extension.appex
static NSString *ads_parent_bundle_id_for_appex(void) {
    NSString *p = [[NSBundle mainBundle] bundlePath];
    if (![p hasSuffix:@".appex"]) return nil;
    NSString *pluginsDir = [p stringByDeletingLastPathComponent];
    if (![[pluginsDir lastPathComponent] isEqualToString:@"PlugIns"]) return nil;
    NSString *parentApp = [pluginsDir stringByDeletingLastPathComponent];
    if (![parentApp hasSuffix:@".app"]) return nil;
    return [[NSBundle bundleWithPath:parentApp] bundleIdentifier];
}

// Shared tier arrays — used by both loadPrefs() and the %ctor extension gate to avoid duplication.
static NSArray *ads_tier1_ids(void) {
    static NSArray *t; static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @[
            @"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail",
            @"com.apple.mobilenotes", @"com.apple.iBooks", @"com.apple.news",
            @"com.apple.podcasts", @"com.apple.stocks",
            @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
            @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon",
            @"com.apple.messages.NotificationServiceExtension",
            @"com.apple.MailNotificationServiceExtension"
        ];
    });
    return t;
}

static NSArray *ads_tier2_ids(void) {
    static NSArray *t; static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @[
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
            @"com.ally.auto", @"com.navyfederal.navyfederal.mydata", @"com.1debit.ChimeProdApp"
        ];
    });
    return t;
}

// Non-atomic globals are only written inside loadPrefs() under the prefsLoaded CAS gate
// (one writer at a time). Atomic flags are read from hooks on arbitrary threads.
static _Atomic BOOL prefsLoaded              = NO;
static _Atomic BOOL currentProcessRestricted = NO;
static _Atomic BOOL currentProcessIsPreset   = NO;
static BOOL globalTweakEnabled               = NO;
static BOOL globalUASpoofingEnabled          = NO;
static NSString *customUAString              = @"";
static _Atomic BOOL shouldSpoofUA            = NO;
static BOOL globalDisableJIT                 = NO;
static BOOL globalDisableJIT15               = NO;
static BOOL globalDisableJS                  = NO;
static BOOL globalDisableMedia               = NO;
static BOOL globalDisableRTC                 = NO;
static BOOL globalDisableFileAccess          = NO;
static BOOL globalDisableIMessageDL          = NO;
static BOOL globalBlockRemoteContent         = NO;
static BOOL globalBlockRiskyAttachments      = NO;
static BOOL disableJIT                       = NO;
static BOOL disableJIT15                     = NO;
static BOOL disableJS                        = NO;
static BOOL disableMedia                     = NO;
static BOOL disableRTC                       = NO;
static BOOL disableFileAccess                = NO;
static BOOL disableIMessageDL                = NO;
static BOOL blockRemoteContent               = NO;
static BOOL blockRiskyAttachments            = NO;
static _Atomic BOOL applyDisableJIT          = NO;
static _Atomic BOOL applyDisableJIT15        = NO;
static _Atomic BOOL applyDisableJS           = NO;
static _Atomic BOOL applyDisableMedia        = NO;
static _Atomic BOOL applyDisableRTC          = NO;
static _Atomic BOOL applyDisableFileAccess   = NO;
static _Atomic BOOL applyDisableIMessageDL   = NO;
static _Atomic BOOL applyBlockRemoteContent  = NO;
static _Atomic BOOL applyBlockRiskyAttachments = NO;

// Generation counter — bumped on every pref reload that changes UA settings.
// Stored with each UCC so a generation mismatch triggers re-injection instead
// of requiring UCC dealloc + realloc to clear the guard.
static NSUInteger adsUAGeneration = 0;

// Compiled once in %ctor; blocks external http/https resource loads.
// Written on main queue from async completion handler; read from WebKit hooks (main thread).
static WKContentRuleList *adsContentBlocker = nil;

static NSString *adsJSONStringLiteral(NSString *str);

// Marks a WKUserContentController as having received the ADS UA script so
// injectUAScript is idempotent. Stores the adsUAGeneration at injection time;
// a mismatch on re-check forces re-injection (e.g., after a UA pref change).
static const char kADSUCCInjectedKey = 0;

// Derives navigator.userAgentData.brands JSON array from a UA string,
// keeping engine/browser tokens consistent with userAgent.
static NSString *adsBrandsFromUA(NSString *ua) {
    if (!ua) return @"[{\"brand\":\"Safari\",\"version\":\"18\"}]";

    NSString *(^majorAfter)(NSString *) = ^NSString *(NSString *token) {
        NSRange r = [ua rangeOfString:token];
        if (r.location == NSNotFound) return @"120";
        NSString *after = [ua substringFromIndex:NSMaxRange(r)];
        NSRange stop = [after rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
        NSString *ver = stop.location > 0 ? [after substringToIndex:stop.location] : after;
        return (ver.length > 0 && ver.length <= 6) ? ver : @"120";
    };

    // Edge — must check before Chrome; Edge UAs also contain "Chrome/".
    if ([ua containsString:@"Edg/"] || [ua containsString:@"EdgA/"] || [ua containsString:@"EdgiOS/"]) {
        NSString *token = [ua containsString:@"Edg/"] ? @"Edg/" :
                          ([ua containsString:@"EdgA/"] ? @"EdgA/" : @"EdgiOS/");
        NSString *ver = majorAfter(token);
        return [NSString stringWithFormat:
            @"[{\"brand\":\"Not(A:Brand\",\"version\":\"24\"},"
             "{\"brand\":\"Chromium\",\"version\":\"%@\"},"
             "{\"brand\":\"Microsoft Edge\",\"version\":\"%@\"}]", ver, ver];
    }

    NSString *chromeToken = [ua containsString:@"Chrome/"] ? @"Chrome/" :
                            ([ua containsString:@"CriOS/"] ? @"CriOS/" : nil);
    if (chromeToken) {
        NSString *ver = majorAfter(chromeToken);
        return [NSString stringWithFormat:
            @"[{\"brand\":\"Not(A:Brand\",\"version\":\"24\"},"
             "{\"brand\":\"Chromium\",\"version\":\"%@\"},"
             "{\"brand\":\"Google Chrome\",\"version\":\"%@\"}]", ver, ver];
    }

    NSString *ffToken = [ua containsString:@"Firefox/"] ? @"Firefox/" :
                        ([ua containsString:@"FxiOS/"] ? @"FxiOS/" : nil);
    if (ffToken) {
        NSString *ver = majorAfter(ffToken);
        return [NSString stringWithFormat:@"[{\"brand\":\"Firefox\",\"version\":\"%@\"}]", ver];
    }

    // Safari or unrecognised — userAgentData not implemented in real Safari, but a consistent
    // stub prevents property-missing throws on sites that check it.
    return @"[{\"brand\":\"Safari\",\"version\":\"18\"}]";
}

static NSString *adsJSONStringLiteral(NSString *str) {
    if (!str || str.length == 0) return @"\"\"";
    NSArray  *wrapper = @[str];
    NSData   *data    = [NSJSONSerialization dataWithJSONObject:wrapper options:0 error:nil];
    if (!data) return @"\"\"";
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json.length >= 2)
        return [json substringWithRange:NSMakeRange(1, json.length - 2)];
    return @"\"\"";
}

static void injectUAScript(WKUserContentController *ucc) {
    if (!ucc || !shouldSpoofUA || !customUAString || customUAString.length == 0) return;
    // Generation-based dedup: re-inject when UA prefs change (adsUAGeneration bumped in reload).
    NSNumber *injectedGen = objc_getAssociatedObject(ucc, &kADSUCCInjectedKey);
    if ([injectedGen isKindOfClass:[NSNumber class]] && injectedGen.unsignedIntegerValue == adsUAGeneration) return;
    objc_setAssociatedObject(ucc, &kADSUCCInjectedKey, @(adsUAGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ADSLog(@"[MITIGATION] Injecting UA spoof script. UA: %@", customUAString);

    NSString *jsonUA = adsJSONStringLiteral(customUAString);

    NSString *platform = @"\"iPhone\"";
    if ([customUAString containsString:@"iPad"])           platform = @"\"iPad\"";
    else if ([customUAString containsString:@"Macintosh"]) platform = @"\"MacIntel\"";
    else if ([customUAString containsString:@"Windows"])   platform = @"\"Win32\"";
    else if ([customUAString containsString:@"Android"])   platform = @"\"Linux aarch64\"";

    NSString *vendor = @"\"Apple Computer, Inc.\"";
    if ([customUAString containsString:@"Chrome"] || [customUAString containsString:@"Android"])
        vendor = @"\"Google Inc.\"";

    NSString *appVersion = customUAString;
    if ([customUAString hasPrefix:@"Mozilla/"]) appVersion = [customUAString substringFromIndex:8];
    NSString *jsonAppVersion = adsJSONStringLiteral(appVersion);

    BOOL isMobileUA = [customUAString containsString:@"iPhone"] ||
                      [customUAString containsString:@"iPad"]   ||
                      [customUAString containsString:@"Android"];
    NSString *uadMobile   = isMobileUA ? @"true" : @"false";
    NSString *uadPlatform = @"\"iOS\"";
    if ([customUAString containsString:@"Macintosh"])    uadPlatform = @"\"macOS\"";
    else if ([customUAString containsString:@"Windows"]) uadPlatform = @"\"Windows\"";
    else if ([customUAString containsString:@"Android"]) uadPlatform = @"\"Android\"";
    NSString *uadBrands = adsBrandsFromUA(customUAString);

    NSString *jsSource = [NSString stringWithFormat:
        @"(function(){"
         "var d=Object.defineProperty,n=navigator;"
         "d(n,'userAgent',  {get:function(){return %@},configurable:true});"
         "d(n,'appVersion', {get:function(){return %@},configurable:true});"
         "d(n,'platform',   {get:function(){return %@},configurable:true});"
         "d(n,'vendor',     {get:function(){return %@},configurable:true});"
         "try{var ud={brands:%@,mobile:%@,platform:%@,"
         "getHighEntropyValues:function(h){return Promise.resolve({});}};"
         "d(n,'userAgentData',{get:function(){return ud;},configurable:true});}catch(e){}"
         "})();",
        jsonUA, jsonAppVersion, platform, vendor, uadBrands, uadMobile, uadPlatform];

    WKUserScript *script = [[WKUserScript alloc]
        initWithSource:jsSource
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:NO];
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

static void applyWebKitMitigations(WKWebViewConfiguration *configuration) {
    if (!configuration) return;

    if (applyDisableJS) {
        // allowsContentJavaScript added in iOS 14; guard to avoid crash on iOS 13.
        if ([configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            WKWebpagePreferences *pagePrefs = configuration.defaultWebpagePreferences;
            if ([pagePrefs respondsToSelector:@selector(setAllowsContentJavaScript:)])
                pagePrefs.allowsContentJavaScript = NO;
        }
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)])
            configuration.preferences.javaScriptEnabled = NO;
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)])
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    }

    if (applyDisableJIT && [configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
        if ([configuration.defaultWebpagePreferences respondsToSelector:@selector(setLockdownModeEnabled:)])
            [(id)configuration.defaultWebpagePreferences setLockdownModeEnabled:YES];
    }

    if ((applyDisableJIT15 || applyDisableJIT) && [configuration respondsToSelector:@selector(processPool)]) {
        if ([configuration.processPool respondsToSelector:@selector(_configuration)]) {
            id poolConfig = [(id)configuration.processPool _configuration];
            if ([poolConfig respondsToSelector:@selector(setJITEnabled:)])
                [(id)poolConfig setJITEnabled:NO];
        }
    }

    if (applyDisableMedia) {
        if ([configuration respondsToSelector:@selector(setAllowsInlineMediaPlayback:)])
            configuration.allowsInlineMediaPlayback = NO;
        if ([configuration respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)])
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        if ([configuration respondsToSelector:@selector(setAllowsPictureInPictureMediaPlayback:)])
            configuration.allowsPictureInPictureMediaPlayback = NO;
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

    WKContentRuleList *localBlocker = adsContentBlocker;
    if (applyBlockRemoteContent && localBlocker)
        [configuration.userContentController addContentRuleList:localBlocker];

    if (shouldSpoofUA) injectUAScript(configuration.userContentController);
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

    NSInteger autoProtectLevel      = 1;
    NSArray  *activeCustomDaemonIDs = @[];
    NSArray  *disabledPresetRules   = @[];
    NSMutableArray *restrictedAppsArray = [NSMutableArray array];

    if (prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        parseRestrictedApps(prefs, restrictedAppsArray);
        globalTweakEnabled          = [prefs[@"enabled"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"enabled"] boolValue] : NO;
        globalUASpoofingEnabled     = [prefs[@"globalUASpoofingEnabled"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalUASpoofingEnabled"] boolValue] : NO;
        globalDisableJIT            = [prefs[@"globalDisableJIT"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalDisableJIT"] boolValue] : NO;
        globalDisableJIT15          = [prefs[@"globalDisableJIT15"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalDisableJIT15"] boolValue] : NO;
        globalDisableJS             = [prefs[@"globalDisableJS"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalDisableJS"] boolValue] : NO;
        globalDisableMedia          = [prefs[@"globalDisableMedia"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalDisableMedia"] boolValue] : NO;
        globalDisableRTC            = [prefs[@"globalDisableRTC"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalDisableRTC"] boolValue] : NO;
        globalDisableFileAccess     = [prefs[@"globalDisableFileAccess"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalDisableFileAccess"] boolValue] : NO;
        globalDisableIMessageDL     = [prefs[@"globalDisableIMessageDL"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalDisableIMessageDL"] boolValue] : NO;
        globalBlockRemoteContent    = [prefs[@"globalBlockRemoteContent"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalBlockRemoteContent"] boolValue] : NO;
        globalBlockRiskyAttachments = [prefs[@"globalBlockRiskyAttachments"] respondsToSelector:@selector(boolValue)]
                                      ? [prefs[@"globalBlockRiskyAttachments"] boolValue] : NO;
        autoProtectLevel            = [prefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)]
                                      ? [prefs[@"autoProtectLevel"] integerValue] : 1;

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
            customUAString = (trimmedUA.length > 0) ? trimmedUA
                : @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
        } else {
            customUAString = presetUA;
        }
    }

    NSString *bundleID       = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *processName    = [[NSProcessInfo processInfo] processName] ?: @"";
    // When running inside an app extension, parentBundleID is the host app; used for tier
    // matching and as a fallback when the plugin has no plugin-specific TargetRules_ entry.
    NSString *parentBundleID = currentExtensionParentBundleID ?: @"";
    BOOL isTargetRestricted  = NO;
    BOOL isPresetMatch       = NO;
    NSString *matchedID      = nil;
    // Three-slot check: own bundle ID, process name, then parent app (for extension processes).
    NSString *targetsToCheck[] = { bundleID, processName, parentBundleID };

    for (int i = 0; i < 3; i++) {
        NSString *target = targetsToCheck[i];
        if (!target || target.length == 0) continue;
        if ([activeCustomDaemonIDs containsObject:target] || [restrictedAppsArray containsObject:target]) {
            isTargetRestricted = YES;
            matchedID = target;
            break;
        }
    }

    if (!isTargetRestricted && globalTweakEnabled) {
        NSArray *tier1 = ads_tier1_ids();
        NSArray *tier2 = ads_tier2_ids();
        // Tier 3 handled exclusively by AntiDarkSwordDaemon; preserved here to maintain the tier loop structure.
        NSArray *tier3 = @[];

        for (int i = 0; i < 3; i++) {
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
    currentProcessIsPreset   = isPresetMatch;

    disableMedia = disableRTC = disableIMessageDL = NO;
    blockRemoteContent = blockRiskyAttachments = NO;
    BOOL spoofUARule = NO;
    disableJIT = disableJIT15 = disableJS = disableFileAccess = NO;

    if (currentProcessRestricted && isPresetMatch) {
        BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
        disableJIT   = isIOS16OrGreater;
        disableJIT15 = !isIOS16OrGreater;
        disableJS    = !isIOS16OrGreater;

        // com.apple.Passbook included for BLASTPASS (PassKit attachment) mitigation.
        NSArray *msgAndMail = @[
            @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
            @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram",
            @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph",
            @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio",
            @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line",
            @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.apple.Passbook",
            // NSEs receive attachments before the user interacts — treat same as messaging apps.
            @"com.apple.messages.NotificationServiceExtension",
            @"com.apple.MailNotificationServiceExtension"
        ];
        NSArray *iMessageUIApps = @[
            @"com.apple.MobileSMS", @"com.apple.iMessageAppsViewService",
            @"com.apple.ActivityMessagesApp"
        ];
        NSArray *browsers = @[
            @"com.apple.mobilesafari", @"com.apple.SafariViewService",
            @"com.google.chrome.ios", @"org.mozilla.ios.Firefox",
            @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"
        ];
        NSArray *quicklookApps = @[
            @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"
        ];

        if ([msgAndMail containsObject:matchedID]) {
            disableMedia = disableRTC = disableFileAccess = YES;
            blockRemoteContent = YES;
            if ([iMessageUIApps containsObject:matchedID]) disableIMessageDL = YES;
            if (![matchedID hasPrefix:@"com.apple."]) spoofUARule = (autoProtectLevel >= 2);
        } else if ([browsers containsObject:matchedID]) {
            if ([matchedID isEqualToString:@"com.apple.mobilesafari"] ||
                [matchedID isEqualToString:@"com.apple.SafariViewService"]) {
                spoofUARule = YES;
            } else {
                spoofUARule = (autoProtectLevel >= 2);
            }
            if (autoProtectLevel >= 3) disableRTC = disableMedia = YES;
        } else if ([quicklookApps containsObject:matchedID]) {
            blockRemoteContent = YES;
        } else if (![matchedID containsString:@"daemon"] && ![matchedID hasPrefix:@"com.apple."]) {
            spoofUARule = (autoProtectLevel >= 2);
        }
    }

    // IMFileTransfer hooks are injected into the Messages UI layer only. Extension processes
    // (share extensions, NSEs, etc.) do not host that class — suppress the preset default.
    if (parentBundleID.length > 0) disableIMessageDL = NO;

    if (currentProcessRestricted && matchedID && prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        // For extension processes: check for a plugin-specific TargetRules_ entry first.
        // If none exists, fall back to the parent app's rules (matchedID = parent bundle ID).
        NSString *rulesID = matchedID;
        if (parentBundleID.length > 0 && ![matchedID isEqualToString:bundleID]) {
            NSString *pluginKey = [NSString stringWithFormat:@"TargetRules_%@", bundleID];
            if ([prefs[pluginKey] isKindOfClass:[NSDictionary class]])
                rulesID = bundleID;
        }
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", rulesID];
        NSDictionary *appRules = prefs[dictKey];
        if (appRules && [appRules isKindOfClass:[NSDictionary class]]) {
            if ([appRules[@"disableJIT"]           respondsToSelector:@selector(boolValue)]) disableJIT           = [appRules[@"disableJIT"] boolValue];
            if ([appRules[@"disableJIT15"]         respondsToSelector:@selector(boolValue)]) disableJIT15         = [appRules[@"disableJIT15"] boolValue];
            if ([appRules[@"disableJS"]            respondsToSelector:@selector(boolValue)]) disableJS            = [appRules[@"disableJS"] boolValue];
            if ([appRules[@"disableMedia"]         respondsToSelector:@selector(boolValue)]) disableMedia         = [appRules[@"disableMedia"] boolValue];
            if ([appRules[@"disableRTC"]           respondsToSelector:@selector(boolValue)]) disableRTC           = [appRules[@"disableRTC"] boolValue];
            if ([appRules[@"disableFileAccess"]    respondsToSelector:@selector(boolValue)]) disableFileAccess    = [appRules[@"disableFileAccess"] boolValue];
            if ([appRules[@"disableIMessageDL"]    respondsToSelector:@selector(boolValue)]) disableIMessageDL    = [appRules[@"disableIMessageDL"] boolValue];
            if ([appRules[@"spoofUA"]              respondsToSelector:@selector(boolValue)]) spoofUARule          = [appRules[@"spoofUA"] boolValue];
            if ([appRules[@"blockRemoteContent"]   respondsToSelector:@selector(boolValue)]) blockRemoteContent   = [appRules[@"blockRemoteContent"] boolValue];
            if ([appRules[@"blockRiskyAttachments"] respondsToSelector:@selector(boolValue)]) blockRiskyAttachments = [appRules[@"blockRiskyAttachments"] boolValue];
        }
    }

    applyDisableJIT          = globalTweakEnabled && (globalDisableJIT        || (currentProcessRestricted && disableJIT));
    applyDisableJIT15        = globalTweakEnabled && (globalDisableJIT15      || (currentProcessRestricted && disableJIT15));
    applyDisableJS           = globalTweakEnabled && (globalDisableJS         || (currentProcessRestricted && disableJS));
    applyDisableMedia        = globalTweakEnabled && (globalDisableMedia      || (currentProcessRestricted && disableMedia));
    applyDisableRTC          = globalTweakEnabled && (globalDisableRTC        || (currentProcessRestricted && disableRTC));
    applyDisableFileAccess   = globalTweakEnabled && (globalDisableFileAccess || (currentProcessRestricted && disableFileAccess));
    applyDisableIMessageDL   = globalTweakEnabled && (globalDisableIMessageDL || (currentProcessRestricted && disableIMessageDL));
    applyBlockRemoteContent  = globalTweakEnabled && (globalBlockRemoteContent  || (currentProcessRestricted && blockRemoteContent));
    applyBlockRiskyAttachments = globalTweakEnabled && (globalBlockRiskyAttachments || (currentProcessRestricted && blockRiskyAttachments));

    shouldSpoofUA = NO;
    if (globalTweakEnabled) {
        if (globalUASpoofingEnabled && customUAString && customUAString.length > 0)
            shouldSpoofUA = YES;
        else if (currentProcessRestricted && spoofUARule && customUAString && customUAString.length > 0)
            shouldSpoofUA = YES;
    }

    if (currentProcessRestricted) {
        ADSLog(@"[STATUS] Protection ACTIVE. JS:%d JIT:%d Media:%d RTC:%d iMsgDL:%d RemoteBlock:%d RiskyAttach:%d",
               applyDisableJS, applyDisableJIT, applyDisableMedia, applyDisableRTC,
               applyDisableIMessageDL, applyBlockRemoteContent, applyBlockRiskyAttachments);
    } else {
        ADSLog(@"[STATUS] Process unrestricted — tweak dormant.");
    }
}

static void reloadPrefsNotification(CFNotificationCenterRef center __unused,
                                    void *observer __unused,
                                    CFStringRef name __unused,
                                    const void *object __unused,
                                    CFDictionaryRef userInfo __unused) {
    // Bump generation so existing WKUserContentControllers re-inject on next use
    // rather than retaining a stale or removed UA script.
    adsUAGeneration++;
    prefsLoaded = NO;
    loadPrefs();
}

%hook WKWebViewConfiguration

- (void)setUserContentController:(WKUserContentController *)userContentController {
    %orig;
    if (shouldSpoofUA && userContentController) injectUAScript(userContentController);
    WKContentRuleList *localBlocker = adsContentBlocker;
    if (applyBlockRemoteContent && localBlocker && userContentController)
        [userContentController addContentRuleList:localBlocker];
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
    if (webView && shouldSpoofUA && [webView respondsToSelector:@selector(setCustomUserAgent:)])
        webView.customUserAgent = customUAString;
    return webView;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    WKWebView *webView = %orig(coder);
    if (!webView) return nil;
    applyWebKitMitigations(webView.configuration);
    if (shouldSpoofUA && [webView respondsToSelector:@selector(setCustomUserAgent:)])
        webView.customUserAgent = customUAString;
    return webView;
}

- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    if (applyDisableJS) {
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            WKWebpagePreferences *pagePrefs = self.configuration.defaultWebpagePreferences;
            if ([pagePrefs respondsToSelector:@selector(setAllowsContentJavaScript:)])
                pagePrefs.allowsContentJavaScript = NO;
        }
        if ([self.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)])
            self.configuration.preferences.javaScriptEnabled = NO;
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
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            WKWebpagePreferences *pagePrefs = self.configuration.defaultWebpagePreferences;
            if ([pagePrefs respondsToSelector:@selector(setAllowsContentJavaScript:)])
                pagePrefs.allowsContentJavaScript = NO;
        }
        if ([self.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)])
            self.configuration.preferences.javaScriptEnabled = NO;
    }
    if (shouldSpoofUA && [self respondsToSelector:@selector(setCustomUserAgent:)])
        self.customUserAgent = customUAString;
    return %orig;
}

- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *))completionHandler {
    if (applyDisableJS) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AntiDarkSword" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}];
            completionHandler(nil, err);
        }
        return;
    }
    %orig;
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
- (void)evaluateJavaScript:(NSString *)javaScriptString inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)contentWorld completionHandler:(void (^)(id, NSError *))completionHandler {
    if (applyDisableJS) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AntiDarkSword" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}];
            completionHandler(nil, err);
        }
        return;
    }
    %orig;
}

- (void)callAsyncJavaScript:(NSString *)functionBody arguments:(NSDictionary<NSString *, id> *)arguments inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)contentWorld completionHandler:(void (^)(id, NSError *))completionHandler {
    if (applyDisableJS) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AntiDarkSword" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}];
            completionHandler(nil, err);
        }
        return;
    }
    %orig;
}
#endif

- (void)setCustomUserAgent:(NSString *)customUserAgent {
    if (shouldSpoofUA) %orig(customUAString);
    else %orig;
}

%end

%hook WKWebpagePreferences
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
- (void)setAllowsContentJavaScript:(BOOL)allowed {
    if (applyDisableJS && allowed) return %orig(NO);
    %orig;
}
#endif
// Prevents apps or exploits from disabling lockdown mode after it is enforced.
- (void)setLockdownModeEnabled:(BOOL)enabled {
    if (applyDisableJIT && !enabled) return;
    %orig;
}
%end

%hook WKPreferences
- (void)setJavaScriptEnabled:(BOOL)enabled {
    if (applyDisableJS && enabled) return %orig(NO);
    %orig;
}
%end

// Prevents re-enabling JIT after it has been disabled via the pool configuration.
%hook _WKProcessPoolConfiguration
- (void)setJITEnabled:(BOOL)enabled {
    if (enabled && (applyDisableJIT || applyDisableJIT15)) return;
    %orig;
}
%end

%hookf(JSValueRef, JSEvaluateScript, JSContextRef ctx, JSStringRef script, JSObjectRef thisObject, JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception) {
    if (applyDisableJS) {
        // Populate exception so callers receive a meaningful error rather than a NULL return
        // with a NULL exception pointer (undefined behaviour in the JSC C API).
        if (ctx && exception) {
            JSStringRef msg = JSStringCreateWithUTF8CString("Script execution blocked by AntiDarkSword");
            *exception = JSValueMakeString(ctx, msg);
            JSStringRelease(msg);
        }
        return NULL;
    }
    return %orig(ctx, script, thisObject, sourceURL, startingLineNumber, exception);
}

// UI-layer iMessage mitigations: second layer on top of daemon-level IMCore hooks.
%hook IMFileTransfer
- (BOOL)isAutoDownloadable {
    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Blocked auto-download of iMessage file transfer (UI layer).");
        return NO;
    }
    return %orig;
}

- (BOOL)canAutoDownload {
    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Denied canAutoDownload for iMessage transfer (UI layer).");
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

// Intercepts the URL used to fetch attachment previews. Returns nil for high-risk
// image/document formats (HEIC, WebP, PDF) to prevent ImageIO/CoreGraphics from
// parsing potentially exploit-bearing files in the context of the Messages UI process.
- (NSURL *)fullSizeImageURL {
    NSURL *url = %orig;
    if (!applyBlockRiskyAttachments || !url) return url;
    static NSSet *riskyExts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        riskyExts = [NSSet setWithObjects:@"heic", @"heif", @"webp", @"pdf", nil];
    });
    NSString *ext = url.pathExtension.lowercaseString;
    if ([riskyExts containsObject:ext]) {
        ADSLog(@"[MITIGATION] Blocked risky attachment preview (%@): %@", ext, url.lastPathComponent);
        return nil;
    }
    return url;
}
%end

%hook UIWebView
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    if (applyDisableJS) return @"";
    return %orig;
}
%end

%ctor {
    isRootlessJB = (access("/var/jb", F_OK) == 0);

    NSString *bundleID    = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";

    NSArray *ignored = @[@"PosterBoard", @"WeatherPoster", @"PassbookUIService", @"Spotlight",
                         @"Tunnel", @"Preferences", @"cfprefsd", @"searchd", @"druid"];
    if ([ignored containsObject:processName]) return;

    NSString *path = [[NSBundle mainBundle] bundlePath] ?: @"";

    // Read prefs early — used by both the extension gate and the manual-override check below.
    // Falls back to CFPreferences for Roothide installs and fresh installs where the plist
    // has not yet been flushed to disk.
    NSDictionary *earlyPrefs = [NSDictionary dictionaryWithContentsOfFile:ads_prefs_path()];
    if (!earlyPrefs) {
        CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("com.eolnmsuk.antidarkswordprefs"),
                                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            CFDictionaryRef dict = CFPreferencesCopyMultiple(keyList, CFSTR("com.eolnmsuk.antidarkswordprefs"),
                                                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (dict) earlyPrefs = (__bridge_transfer NSDictionary *)dict;
            CFRelease(keyList);
        }
    }

    // App extension gate: Apple NSEs pass unconditionally (zero-click primary surface).
    // All other extensions require the parent app to be a protected target — share extensions,
    // notification content extensions, and iMessage app extensions of tier1/tier2 apps carry
    // the same web-content and attachment attack surface as their parent.
    if ([path hasSuffix:@".appex"]) {
        currentExtensionParentBundleID = ads_parent_bundle_id_for_appex();

        static NSArray *allowedNSEBundleIDs;
        static dispatch_once_t nseOnce;
        dispatch_once(&nseOnce, ^{
            allowedNSEBundleIDs = @[
                @"com.apple.messages.NotificationServiceExtension",
                @"com.apple.MailNotificationServiceExtension"
            ];
        });

        if (![allowedNSEBundleIDs containsObject:bundleID]) {
            NSString *parentID  = currentExtensionParentBundleID;
            BOOL parentProtected = NO;
            if (parentID.length > 0) {
                NSInteger lvl = [earlyPrefs[@"autoProtectLevel"] integerValue] ?: 1;
                parentProtected = [ads_tier1_ids() containsObject:parentID] ||
                                  (lvl >= 2 && [ads_tier2_ids() containsObject:parentID]);
                if (!parentProtected) {
                    NSArray *customD = earlyPrefs[@"activeCustomDaemonIDs"] ?: earlyPrefs[@"customDaemonIDs"] ?: @[];
                    NSString *pKey   = [NSString stringWithFormat:@"restrictedApps-%@", parentID];
                    id legacyApps    = earlyPrefs[@"restrictedApps"];
                    parentProtected  =
                        [customD containsObject:parentID] ||
                        ([earlyPrefs[pKey] respondsToSelector:@selector(boolValue)] && [earlyPrefs[pKey] boolValue]) ||
                        ([legacyApps isKindOfClass:[NSDictionary class]] && [legacyApps[parentID] boolValue]);
                }
            }
            if (!parentProtected) return;
        }
    }

    BOOL isUserApp       = [path localizedCaseInsensitiveContainsString:@"/Containers/Bundle/Application/"];
    BOOL isSystemOrJBApp = [path containsString:@"/Applications/"];

    NSArray *allowedServices = @[
        @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
        @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon",
        @"com.apple.messages.NotificationServiceExtension",
        @"com.apple.MailNotificationServiceExtension"
    ];
    BOOL isAllowedService = [allowedServices containsObject:bundleID];

    BOOL isManualOverride = NO;
    if (earlyPrefs) {
        NSArray *customDaemons = earlyPrefs[@"activeCustomDaemonIDs"] ?: earlyPrefs[@"customDaemonIDs"] ?: @[];
        if ([customDaemons containsObject:bundleID] || [customDaemons containsObject:processName])
            isManualOverride = YES;
        if (!isManualOverride && bundleID.length > 0) {
            NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", bundleID];
            if ([earlyPrefs[prefKey] respondsToSelector:@selector(boolValue)] && [earlyPrefs[prefKey] boolValue]) {
                isManualOverride = YES;
            } else {
                NSDictionary *restrictedApps = earlyPrefs[@"restrictedApps"];
                if ([restrictedApps isKindOfClass:[NSDictionary class]] && [restrictedApps[bundleID] boolValue])
                    isManualOverride = YES;
            }
        }
    }

    if (!isUserApp && !isSystemOrJBApp && !isAllowedService && !isManualOverride) return;

    loadPrefs();
    ADSLog(@"[INIT] AntiDarkSwordUI loaded into: %@", processName);

    // Pre-compile the remote content blocker. Blocks external http/https resource loads
    // in WKWebViews — primary zero-click attack surface for HTML email rendering.
    NSString *blockRules =
        @"[{\"trigger\":{\"url-filter\":\"^https?://\","
         "\"resource-type\":[\"image\",\"style-sheet\",\"script\","
         "\"font\",\"media\",\"svg-document\",\"raw\"]},"
         "\"action\":{\"type\":\"block\"}}]";
    [WKContentRuleListStore.defaultStore
        compileContentRuleListForIdentifier:@"com.eolnmsuk.ads.remoteblock"
        encodedContentRuleList:blockRules
        completionHandler:^(WKContentRuleList *list, NSError *err) {
            if (list) dispatch_async(dispatch_get_main_queue(), ^{ adsContentBlocker = list; });
            else ADSLog(@"[WARN] Remote content blocker compile failed: %@", err);
        }];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)reloadPrefsNotification,
        CFSTR("com.eolnmsuk.antidarkswordprefs/saved"),
        NULL, CFNotificationSuspensionBehaviorCoalesce);
}
