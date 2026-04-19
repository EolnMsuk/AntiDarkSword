// AntiDarkSwordUI/Tweak.x
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CoreFoundation/CoreFoundation.h>
#include <unistd.h>
#include <stdatomic.h>

#import "../ADSLogging.h"

// =========================================================
// PRIVATE WEBKIT INTERFACES (JIT & LOCKDOWN MODE)
// =========================================================
#if __IPHONE_OS_VERSION_MAX_ALLOWED < 160000
@interface WKWebpagePreferences (Private)
@property (nonatomic, assign) BOOL lockdownModeEnabled;
@end
#endif

@interface _WKProcessPoolConfiguration : NSObject
@property (nonatomic, assign) BOOL JITEnabled;
@end

@interface WKProcessPool (Private)
@property (nonatomic, readonly) _WKProcessPoolConfiguration *_configuration;
@end

// =========================================================
// PRIVATE INTERFACES — iMessage transfer / preview blocking
// =========================================================
@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

@interface CKAttachmentMessagePartChatItem : NSObject
- (BOOL)_needsPreviewGeneration;
@end

static BOOL isRootlessJB = NO;
static NSString *ads_prefs_path(void) {
    return isRootlessJB
        ? @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"
        : @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist";
}

// Runtime State Variables
static _Atomic BOOL prefsLoaded              = NO;
static _Atomic BOOL currentProcessRestricted = NO;
static _Atomic BOOL currentProcessIsPreset   = NO;
static BOOL globalTweakEnabled     = NO;
static BOOL globalUASpoofingEnabled = NO;
static NSString *customUAString = @"";
static _Atomic BOOL shouldSpoofUA          = NO;

// Global Overrides
static BOOL globalDisableJIT       = NO;
static BOOL globalDisableJIT15     = NO;
static BOOL globalDisableJS        = NO;
static BOOL globalDisableMedia     = NO;
static BOOL globalDisableRTC       = NO;
static BOOL globalDisableFileAccess = NO;
static BOOL globalDisableIMessageDL = NO;

// App-Specific Granular Features
static BOOL disableJIT             = NO;
static BOOL disableJIT15           = NO;
static BOOL disableJS              = NO;
static BOOL disableMedia           = NO;
static BOOL disableRTC             = NO;
static BOOL disableFileAccess      = NO;
static BOOL disableIMessageDL      = NO;

// Final Evaluated States
static _Atomic BOOL applyDisableJIT        = NO;
static _Atomic BOOL applyDisableJIT15      = NO;
static _Atomic BOOL applyDisableJS         = NO;
static _Atomic BOOL applyDisableMedia      = NO;
static _Atomic BOOL applyDisableRTC        = NO;
static _Atomic BOOL applyDisableFileAccess = NO;
static _Atomic BOOL applyDisableIMessageDL = NO;

// =========================================================
// HELPERS
// =========================================================

static NSString *adsJSONStringLiteral(NSString *str);

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

    if ([ua containsString:@"Edg/"] || [ua containsString:@"EdgA/"] || [ua containsString:@"EdgiOS/"]) {
        NSString *token = [ua containsString:@"Edg/"] ? @"Edg/" : ([ua containsString:@"EdgA/"] ? @"EdgA/" : @"EdgiOS/");
        NSString *ver = majorAfter(token);
        return [NSString stringWithFormat:
            @"[{\"brand\":\"Not(A:Brand\",\"version\":\"24\"},"
             "{\"brand\":\"Chromium\",\"version\":\"%@\"},"
             "{\"brand\":\"Microsoft Edge\",\"version\":\"%@\"}]", ver, ver];
    }

    NSString *chromeToken = [ua containsString:@"Chrome/"] ? @"Chrome/" : ([ua containsString:@"CriOS/"] ? @"CriOS/" : nil);
    if (chromeToken) {
        NSString *ver = majorAfter(chromeToken);
        return [NSString stringWithFormat:
            @"[{\"brand\":\"Not(A:Brand\",\"version\":\"24\"},"
             "{\"brand\":\"Chromium\",\"version\":\"%@\"},"
             "{\"brand\":\"Google Chrome\",\"version\":\"%@\"}]", ver, ver];
    }

    NSString *ffToken = [ua containsString:@"Firefox/"] ? @"Firefox/" : ([ua containsString:@"FxiOS/"] ? @"FxiOS/" : nil);
    if (ffToken) {
        NSString *ver = majorAfter(ffToken);
        return [NSString stringWithFormat:@"[{\"brand\":\"Firefox\",\"version\":\"%@\"}]", ver];
    }

    return @"[{\"brand\":\"Safari\",\"version\":\"18\"}]";
}

static NSString *adsJSONStringLiteral(NSString *str) {
    if (!str || str.length == 0) return @"\"\"";
    NSArray *wrapper = @[str];
    NSData  *data    = [NSJSONSerialization dataWithJSONObject:wrapper options:0 error:nil];
    if (!data) return @"\"\"";
    NSString *jsonArrayString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (jsonArrayString.length >= 2)
        return [jsonArrayString substringWithRange:NSMakeRange(1, jsonArrayString.length - 2)];
    return @"\"\"";
}

static void injectUAScript(WKUserContentController *ucc) {
    if (!ucc || !shouldSpoofUA || !customUAString || customUAString.length == 0) return;
    ADSLog(@"[MITIGATION] Injecting UA spoof script. UA: %@", customUAString);

    NSString *jsonUA = adsJSONStringLiteral(customUAString);

    NSString *platform = @"\"iPhone\"";
    if ([customUAString containsString:@"iPad"])        platform = @"\"iPad\"";
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
    if ([customUAString containsString:@"Macintosh"])      uadPlatform = @"\"macOS\"";
    else if ([customUAString containsString:@"Windows"])   uadPlatform = @"\"Windows\"";
    else if ([customUAString containsString:@"Android"])   uadPlatform = @"\"Android\"";
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

// =========================================================
// PREFERENCES PARSING HELPERS
// =========================================================

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

    if (shouldSpoofUA) {
        injectUAScript(configuration.userContentController);
    }
}

static void loadPrefs() {
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

    NSInteger autoProtectLevel      = 1;
    NSArray  *activeCustomDaemonIDs = @[];
    NSArray  *disabledPresetRules   = @[];
    NSMutableArray *restrictedAppsArray = [NSMutableArray array];
    if (prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        parseRestrictedApps(prefs, restrictedAppsArray);
        globalTweakEnabled        = [prefs[@"enabled"] respondsToSelector:@selector(boolValue)]                ? [prefs[@"enabled"] boolValue]                : NO;
        globalUASpoofingEnabled   = [prefs[@"globalUASpoofingEnabled"] respondsToSelector:@selector(boolValue)]   ? [prefs[@"globalUASpoofingEnabled"] boolValue]   : NO;
        globalDisableJIT          = [prefs[@"globalDisableJIT"] respondsToSelector:@selector(boolValue)]           ? [prefs[@"globalDisableJIT"] boolValue]           : NO;
        globalDisableJIT15        = [prefs[@"globalDisableJIT15"] respondsToSelector:@selector(boolValue)]         ? [prefs[@"globalDisableJIT15"] boolValue]         : NO;
        globalDisableJS           = [prefs[@"globalDisableJS"] respondsToSelector:@selector(boolValue)]            ? [prefs[@"globalDisableJS"] boolValue]            : NO;
        globalDisableMedia        = [prefs[@"globalDisableMedia"] respondsToSelector:@selector(boolValue)]         ? [prefs[@"globalDisableMedia"] boolValue]         : NO;
        globalDisableRTC          = [prefs[@"globalDisableRTC"] respondsToSelector:@selector(boolValue)]           ? [prefs[@"globalDisableRTC"] boolValue]           : NO;
        globalDisableFileAccess   = [prefs[@"globalDisableFileAccess"] respondsToSelector:@selector(boolValue)]    ? [prefs[@"globalDisableFileAccess"] boolValue]    : NO;
        globalDisableIMessageDL   = [prefs[@"globalDisableIMessageDL"] respondsToSelector:@selector(boolValue)]   ? [prefs[@"globalDisableIMessageDL"] boolValue]    : NO;
        autoProtectLevel          = [prefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)]        ? [prefs[@"autoProtectLevel"] integerValue]        : 1;

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

    NSString *bundleID    = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";
    BOOL isTargetRestricted = NO;
    BOOL isPresetMatch      = NO;
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
        NSArray *tier1 = @[
            @"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail",
            @"com.apple.mobilenotes", @"com.apple.iBooks", @"com.apple.news",
            @"com.apple.podcasts", @"com.apple.stocks",
            @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
            @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"
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
            @"com.ally.auto", @"com.navyfederal.navyfederal.mydata", @"com.1debit.ChimeProdApp"
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
    currentProcessIsPreset   = isPresetMatch;

    disableMedia      = NO;
    disableRTC        = NO;
    disableIMessageDL = NO;
    BOOL spoofUARule  = NO;
    disableJIT        = NO;
    disableJIT15      = NO;
    disableJS         = NO;
    disableFileAccess = NO;
    if (currentProcessRestricted && isPresetMatch) {
        BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
        disableJIT   = isIOS16OrGreater;
        disableJIT15 = !isIOS16OrGreater;
        disableJS    = !isIOS16OrGreater;
        NSArray *msgAndMail = @[
            @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
            @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram",
            @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph",
            @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio",
            @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line",
            @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.apple.Passbook"
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
        if ([msgAndMail containsObject:matchedID]) {
            disableMedia      = YES;
            disableRTC        = YES;
            disableFileAccess = YES;
            if ([iMessageUIApps containsObject:matchedID]) disableIMessageDL = YES;
            if (![matchedID hasPrefix:@"com.apple."]) spoofUARule = (autoProtectLevel >= 2);
        } else if ([browsers containsObject:matchedID]) {
            if ([matchedID isEqualToString:@"com.apple.mobilesafari"] ||
                [matchedID isEqualToString:@"com.apple.SafariViewService"]) {
                spoofUARule = YES;
            } else {
                spoofUARule = (autoProtectLevel >= 2);
            }
            if (autoProtectLevel >= 3) {
                disableRTC   = YES;
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
            if ([appRules[@"disableJIT"] respondsToSelector:@selector(boolValue)])         disableJIT         = [appRules[@"disableJIT"] boolValue];
            if ([appRules[@"disableJIT15"] respondsToSelector:@selector(boolValue)])       disableJIT15       = [appRules[@"disableJIT15"] boolValue];
            if ([appRules[@"disableJS"] respondsToSelector:@selector(boolValue)])          disableJS          = [appRules[@"disableJS"] boolValue];
            if ([appRules[@"disableMedia"] respondsToSelector:@selector(boolValue)])       disableMedia       = [appRules[@"disableMedia"] boolValue];
            if ([appRules[@"disableRTC"] respondsToSelector:@selector(boolValue)])         disableRTC         = [appRules[@"disableRTC"] boolValue];
            if ([appRules[@"disableFileAccess"] respondsToSelector:@selector(boolValue)]) disableFileAccess  = [appRules[@"disableFileAccess"] boolValue];
            if ([appRules[@"disableIMessageDL"] respondsToSelector:@selector(boolValue)]) disableIMessageDL  = [appRules[@"disableIMessageDL"] boolValue];
            if ([appRules[@"spoofUA"] respondsToSelector:@selector(boolValue)])            spoofUARule        = [appRules[@"spoofUA"] boolValue];
        }
    }

    applyDisableJIT         = globalTweakEnabled && (globalDisableJIT        || (currentProcessRestricted && disableJIT));
    applyDisableJIT15       = globalTweakEnabled && (globalDisableJIT15      || (currentProcessRestricted && disableJIT15));
    applyDisableJS          = globalTweakEnabled && (globalDisableJS         || (currentProcessRestricted && disableJS));
    applyDisableMedia       = globalTweakEnabled && (globalDisableMedia      || (currentProcessRestricted && disableMedia));
    applyDisableRTC         = globalTweakEnabled && (globalDisableRTC        || (currentProcessRestricted && disableRTC));
    applyDisableFileAccess  = globalTweakEnabled && (globalDisableFileAccess || (currentProcessRestricted && disableFileAccess));
    applyDisableIMessageDL  = globalTweakEnabled && (globalDisableIMessageDL || (currentProcessRestricted && disableIMessageDL));
    shouldSpoofUA = NO;
    if (globalTweakEnabled) {
        if (globalUASpoofingEnabled && customUAString && customUAString.length > 0) {
            shouldSpoofUA = YES;
        } else if (currentProcessRestricted && spoofUARule && customUAString && customUAString.length > 0) {
            shouldSpoofUA = YES;
        }
    }

    if (currentProcessRestricted) {
        ADSLog(@"[STATUS] Protection ACTIVE. JS:%d JIT:%d Media:%d RTC:%d iMsgDL:%d",
               applyDisableJS, applyDisableJIT, applyDisableMedia, applyDisableRTC,
               applyDisableIMessageDL);
    } else {
        ADSLog(@"[STATUS] Process unrestricted — tweak dormant.");
    }
}

static void reloadPrefsNotification(CFNotificationCenterRef center __unused, void *observer __unused, CFStringRef name __unused, const void *object __unused, CFDictionaryRef userInfo __unused) {
    prefsLoaded = NO;
    loadPrefs();
}

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

%hook _WKProcessPoolConfiguration
- (void)setJITEnabled:(BOOL)enabled {
    if (enabled && (applyDisableJIT || applyDisableJIT15)) return;
    %orig;
}
%end

%hookf(JSValueRef, JSEvaluateScript, JSContextRef ctx, JSStringRef script, JSObjectRef thisObject, JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception) {
    if (applyDisableJS) {
        if (ctx && exception) {
            JSStringRef msg = JSStringCreateWithUTF8CString("Script execution blocked by AntiDarkSword");
            *exception = JSValueMakeString(ctx, msg);
            JSStringRelease(msg);
        }
        return NULL;
    }
    return %orig(ctx, script, thisObject, sourceURL, startingLineNumber, exception);
}

// =========================================================
// iMESSAGE UI-LAYER MITIGATIONS
// =========================================================

%hook IMFileTransfer
- (BOOL)isAutoDownloadable {
    if (applyDisableIMessageDL) return NO;
    return %orig;
}
- (BOOL)canAutoDownload {
    if (applyDisableIMessageDL) return NO;
    return %orig;
}
%end

%hook CKAttachmentMessagePartChatItem
- (BOOL)_needsPreviewGeneration {
    if (applyDisableIMessageDL) return NO;
    return %orig;
}
%end

%hook UIWebView
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    if (applyDisableJS) return @"";
    return %orig;
}
%end

// =========================================================
// IN-APP SETTINGS OVERLAY
// =========================================================

static BOOL ads_ui_gesture_installed = NO;

static UIWindow *ads_ui_key_window(void) {
    if (@available(iOS 13, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
}

static UIViewController *ads_ui_top_vc(UIViewController *root) {
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

static NSArray<NSDictionary *> *ads_ui_setting_rows(void) {
    NSInteger major = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@{@"title": @"Spoof User Agent", @"detail": @"Masks the real browser fingerprint", @"key": @"spoofUA", @"enabled": @YES}];
    if (major >= 16) [rows addObject:@{@"title": @"Block JIT / Lockdown Mode", @"detail": @"Enables WebKit lockdown mode (iOS 16+)", @"key": @"disableJIT", @"enabled": @YES}];
    else if (major >= 15) [rows addObject:@{@"title": @"Block JIT", @"detail": @"Disables JIT via pool config (iOS 15)", @"key": @"disableJIT15", @"enabled": @YES}];
    else [rows addObject:@{@"title": @"Block JIT", @"detail": @"Not available on iOS 14 and below", @"key": @"disableJIT15", @"enabled": @NO}];
    [rows addObject:@{@"title": @"Block JavaScript", @"detail": @"Prevents JS execution in WebViews", @"key": @"disableJS", @"enabled": @YES}];
    [rows addObject:@{@"title": @"Block Media Autoplay", @"detail": @"Stops drive-by audio/video loading", @"key": @"disableMedia", @"enabled": @YES}];
    [rows addObject:@{@"title": @"Block WebGL / WebRTC", @"detail": @"Disables GPU and peer-connection APIs", @"key": @"disableRTC", @"enabled": @YES}];
    [rows addObject:@{@"title": @"Block file:// Access", @"detail": @"Prevents local file exfiltration", @"key": @"disableFileAccess", @"enabled": @YES}];
    [rows addObject:@{@"title": @"Block iMessage Downloads", @"detail": @"Blocks auto-download of iMessage attachments", @"key": @"disableIMessageDL", @"enabled": @YES}];
    return rows;
}

static void ads_ui_write_prefs(NSDictionary *prefs) {
    CFStringRef appID = CFSTR("com.eolnmsuk.antidarkswordprefs");
    for (NSString *key in prefs) {
        CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)(prefs[key]), appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    NSString *path = ads_prefs_path();
    NSString *dir  = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [prefs writeToFile:path atomically:YES];
}

@interface ADSUISettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView             *tableView;
@property (nonatomic, strong) NSMutableDictionary     *pendingRules;
@property (nonatomic, strong) NSMutableDictionary     *pendingPrefs;
@property (nonatomic, copy)   NSString                *currentBundleID;
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic)         BOOL                     jsLocked;
@end

@implementation ADSUISettingsViewController

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.currentBundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    self.rows = ads_ui_setting_rows();

    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:ads_prefs_path()];
    if (!existing) {
        CFArrayRef kl = CFPreferencesCopyKeyList(CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (kl) {
            CFDictionaryRef d = CFPreferencesCopyMultiple(kl, CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (d) existing = (__bridge_transfer NSDictionary *)d;
            CFRelease(kl);
        }
    }
    self.pendingPrefs = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];

    NSString *rulesKey = [NSString stringWithFormat:@"TargetRules_%@", self.currentBundleID];
    NSDictionary *savedRules = self.pendingPrefs[rulesKey];
    self.pendingRules = [savedRules isKindOfClass:[NSDictionary class]] ? [savedRules mutableCopy] : [NSMutableDictionary dictionary];

    id savedJS = self.pendingRules[@"disableJS"];
    self.jsLocked = savedJS ? [savedJS boolValue] : [self isOnForKey:@"disableJS" masterOn:[self isMasterRuleEnabled]];
    return self;
}

- (BOOL)isGlobalTweakEnabled {
    id val = self.pendingPrefs[@"enabled"];
    return val ? [val boolValue] : NO;
}

- (BOOL)isPresetApp {
    NSInteger autoProtectLevel = [self.pendingPrefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)] ? [self.pendingPrefs[@"autoProtectLevel"] integerValue] : 1;
    NSString *target = self.currentBundleID;
    NSArray *tier1 = @[@"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.mobilenotes", @"com.apple.iBooks", @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks", @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"];
    NSArray *tier2 = @[@"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line", @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.google.GoogleMobile", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios", @"pinterest", @"com.tumblr.tumblr", @"com.facebook.Facebook", @"com.atebits.Tweetie2", @"com.burbn.instagram", @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn", @"com.reddit.Reddit", @"com.google.ios.youtube", @"tv.twitch", @"com.google.gemini", @"com.openai.chat", @"com.deepseek.chat", @"com.github.stormbreaker.prod", @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza", @"com.squareup.cash", @"net.kortina.labs.Venmo", @"com.yourcompany.PPClient", @"com.robinhood.release.Robinhood", @"com.vilcsak.bitcoin2", @"com.sixdays.trust", @"io.metamask.MetaMask", @"app.phantom.phantom", @"com.chase", @"com.bankofamerica.BofAMobileBanking", @"com.wellsfargo.net.mobilebanking", @"com.citi.citimobile", @"com.capitalone.enterprisemobilebanking", @"com.americanexpress.amelia", @"com.fidelity.iphone", @"com.schwab.mobile", @"com.etrade.mobilepro.iphone", @"com.discoverfinancial.mobile", @"com.usbank.mobilebanking", @"com.monzo.ios", @"com.revolut.iphone", @"com.binance.dev", @"com.kraken.invest", @"com.barclays.ios.bmb", @"com.ally.auto", @"com.navyfederal.navyfederal.mydata", @"com.1debit.ChimeProdApp"];
    if ([tier1 containsObject:target]) return YES;
    if (autoProtectLevel >= 2 && [tier2 containsObject:target]) return YES;
    return NO;
}

- (BOOL)isMasterRuleEnabled {
    id intendedState = self.pendingPrefs[@"_intendedMasterState"];
    if (intendedState) return [intendedState boolValue];
    
    if (![self isGlobalTweakEnabled]) return NO;
    
    NSArray *customDaemons = self.pendingPrefs[@"activeCustomDaemonIDs"] ?: self.pendingPrefs[@"customDaemonIDs"] ?: @[];
    if ([customDaemons containsObject:self.currentBundleID]) return YES;
    
    NSString *restrictKey = [NSString stringWithFormat:@"restrictedApps-%@", self.currentBundleID];
    if (self.pendingPrefs[restrictKey] != nil) {
        return [self.pendingPrefs[restrictKey] boolValue];
    }
    
    NSDictionary *restrictedAppsDict = self.pendingPrefs[@"restrictedApps"];
    if ([restrictedAppsDict isKindOfClass:[NSDictionary class]] && [restrictedAppsDict[self.currentBundleID] boolValue]) return YES;
    
    NSArray *disabledPresets = self.pendingPrefs[@"disabledPresetRules"] ?: @[];
    if ([self isPresetApp] && ![disabledPresets containsObject:self.currentBundleID]) return YES;
    
    return NO;
}

- (BOOL)isGlobalOverrideForKey:(NSString *)key {
    if ([key isEqualToString:@"spoofUA"]) return [self.pendingPrefs[@"globalUASpoofingEnabled"] boolValue];
    if ([key isEqualToString:@"disableJIT"]) return [self.pendingPrefs[@"globalDisableJIT"] boolValue];
    if ([key isEqualToString:@"disableJIT15"]) return [self.pendingPrefs[@"globalDisableJIT15"] boolValue];
    if ([key isEqualToString:@"disableJS"]) return [self.pendingPrefs[@"globalDisableJS"] boolValue];
    if ([key isEqualToString:@"disableMedia"]) return [self.pendingPrefs[@"globalDisableMedia"] boolValue];
    if ([key isEqualToString:@"disableRTC"]) return [self.pendingPrefs[@"globalDisableRTC"] boolValue];
    if ([key isEqualToString:@"disableFileAccess"]) return [self.pendingPrefs[@"globalDisableFileAccess"] boolValue];
    if ([key isEqualToString:@"disableIMessageDL"]) return [self.pendingPrefs[@"globalDisableIMessageDL"] boolValue];
    return NO;
}

- (BOOL)computeSmartDefaultForKey:(NSString *)key {
    NSString *bundleID = self.currentBundleID;
    BOOL isIOS16 = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
    if ([key isEqualToString:@"disableJIT"]) return isIOS16;
    if ([key isEqualToString:@"disableJIT15"]) return !isIOS16;
    if ([key isEqualToString:@"disableJS"]) return !isIOS16;

    NSArray *msgAndMail = @[@"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line", @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.apple.Passbook"];
    NSArray *browsers = @[@"com.apple.mobilesafari", @"com.apple.SafariViewService", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"];

    if ([msgAndMail containsObject:bundleID]) {
        if ([key isEqualToString:@"disableMedia"] || [key isEqualToString:@"disableRTC"] || [key isEqualToString:@"disableFileAccess"]) return YES;
        if ([key isEqualToString:@"disableIMessageDL"] && ([bundleID isEqualToString:@"com.apple.MobileSMS"] || [bundleID isEqualToString:@"com.apple.ActivityMessagesApp"] || [bundleID isEqualToString:@"com.apple.iMessageAppsViewService"])) return YES;
    }

    if ([browsers containsObject:bundleID]) {
        if ([key isEqualToString:@"spoofUA"]) return YES;
        NSInteger level = [self.pendingPrefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)] ? [self.pendingPrefs[@"autoProtectLevel"] integerValue] : 1;
        if (level >= 3 && ([key isEqualToString:@"disableMedia"] || [key isEqualToString:@"disableRTC"])) return YES;
    }

    return NO;
}

- (BOOL)isOnForKey:(NSString *)key masterOn:(BOOL)masterOn {
    if (![self isGlobalTweakEnabled]) return NO;
    if ([self isGlobalOverrideForKey:key]) return YES;
    if (!masterOn) return NO;

    id pending = self.pendingRules[key];
    if (pending) return [pending boolValue];

    NSDictionary *savedRules = self.pendingPrefs[[NSString stringWithFormat:@"TargetRules_%@", self.currentBundleID]];
    if (savedRules && savedRules[key] != nil) return [savedRules[key] boolValue];

    return [self computeSmartDefaultForKey:key];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *bgView = [[UIVisualEffectView alloc] initWithEffect:blur];
    bgView.frame = self.view.bounds;
    bgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:bgView];

    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedBackground:)];
    dismissTap.numberOfTouchesRequired = 1;
    [bgView addGestureRecognizer:dismissTap];

    UIView *shadowWrapper = [[UIView alloc] init];
    shadowWrapper.translatesAutoresizingMaskIntoConstraints = NO;
    shadowWrapper.backgroundColor    = [UIColor clearColor];
    shadowWrapper.layer.cornerRadius = 18;
    shadowWrapper.layer.shadowColor  = [UIColor blackColor].CGColor;
    shadowWrapper.layer.shadowOpacity = 0.45;
    shadowWrapper.layer.shadowRadius = 16;
    shadowWrapper.layer.shadowOffset = CGSizeMake(0, 6);
    [self.view addSubview:shadowWrapper];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor     = [UIColor colorWithRed:0.11 green:0.11 blue:0.13 alpha:0.97];
    card.layer.cornerRadius  = 18;
    card.layer.masksToBounds = YES;
    [shadowWrapper addSubview:card];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text          = @"AntiDarkSword";
    titleLabel.font          = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor     = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:titleLabel];

    UILabel *subLabel = [[UILabel alloc] init];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subLabel.text                      = self.currentBundleID;
    subLabel.font                      = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    subLabel.textColor                 = [UIColor colorWithWhite:0.5 alpha:1];
    subLabel.textAlignment             = NSTextAlignmentCenter;
    subLabel.adjustsFontSizeToFitWidth = YES;
    subLabel.minimumScaleFactor        = 0.7;
    [card addSubview:subLabel];

    UIView *masterRow = [[UIView alloc] init];
    masterRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:masterRow];

    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
    [masterRow addSubview:separator];

    UILabel *masterLabel = [[UILabel alloc] init];
    masterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    masterLabel.text      = @"Enable Rule";
    masterLabel.font      = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    masterLabel.textColor = [UIColor whiteColor];
    [masterRow addSubview:masterLabel];

    UISwitch *masterSwitch = [[UISwitch alloc] init];
    masterSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    masterSwitch.onTintColor = [UIColor systemGreenColor];
    masterSwitch.tag         = NSIntegerMax;

    BOOL isGlobalON = [self isGlobalTweakEnabled];
    BOOL isMasterEnabled = [self isMasterRuleEnabled];
    
    masterSwitch.on = isMasterEnabled;
    masterRow.backgroundColor = isMasterEnabled
        ? [UIColor colorWithRed:0.08 green:0.25 blue:0.12 alpha:1.0]
        : [UIColor colorWithRed:0.25 green:0.08 blue:0.08 alpha:1.0];

    if (!isGlobalON) {
        masterSwitch.enabled = NO;
        masterSwitch.on = NO;
        masterLabel.text = @"Enable Rule (Globally Disabled)";
        masterLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
        masterRow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    }
    
    [masterSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [masterRow addSubview:masterSwitch];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource      = self;
    self.tableView.delegate        = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor  = [UIColor colorWithWhite:0.22 alpha:1];
    self.tableView.separatorInset  = UIEdgeInsetsMake(0, 16, 0, 0);
    self.tableView.scrollEnabled   = YES;
    self.tableView.bounces         = NO;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 1)];
    [card addSubview:self.tableView];

    UIView *buttonBar = [[UIView alloc] init];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    buttonBar.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    [card addSubview:buttonBar];

    UIView *btnSep = [[UIView alloc] init];
    btnSep.translatesAutoresizingMaskIntoConstraints = NO;
    btnSep.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
    [buttonBar addSubview:btnSep];

    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:[UIColor colorWithWhite:0.55 alpha:1] forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont systemFontOfSize:15];
    [cancelBtn addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [buttonBar addSubview:cancelBtn];

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [saveBtn setTitle:@"Save & Restart" forState:UIControlStateNormal];
    [saveBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [saveBtn addTarget:self action:@selector(saveAndRestart) forControlEvents:UIControlEventTouchUpInside];
    [buttonBar addSubview:saveBtn];

    UIView *btnDivider = [[UIView alloc] init];
    btnDivider.translatesAutoresizingMaskIntoConstraints = NO;
    btnDivider.backgroundColor = [UIColor colorWithWhite:0.28 alpha:1];
    [buttonBar addSubview:btnDivider];

    CGFloat rowH  = 52.0;
    CGFloat maxTH = rowH * (CGFloat)self.rows.count;

    [NSLayoutConstraint activateConstraints:@[
        [shadowWrapper.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [shadowWrapper.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [shadowWrapper.widthAnchor   constraintEqualToAnchor:self.view.widthAnchor multiplier:0.88],
        [shadowWrapper.heightAnchor  constraintLessThanOrEqualToAnchor:self.view.heightAnchor multiplier:0.84],

        [card.topAnchor      constraintEqualToAnchor:shadowWrapper.topAnchor],
        [card.leadingAnchor  constraintEqualToAnchor:shadowWrapper.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:shadowWrapper.trailingAnchor],
        [card.bottomAnchor   constraintEqualToAnchor:shadowWrapper.bottomAnchor],

        [titleLabel.topAnchor      constraintEqualToAnchor:card.topAnchor constant:18],
        [titleLabel.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor constant:16],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [subLabel.topAnchor      constraintEqualToAnchor:titleLabel.bottomAnchor constant:3],
        [subLabel.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor constant:16],
        [subLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [masterRow.topAnchor      constraintEqualToAnchor:subLabel.bottomAnchor constant:14],
        [masterRow.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor],
        [masterRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [masterRow.heightAnchor   constraintEqualToConstant:52],

        [masterLabel.leadingAnchor constraintEqualToAnchor:masterRow.leadingAnchor constant:16],
        [masterLabel.centerYAnchor constraintEqualToAnchor:masterRow.centerYAnchor],

        [masterSwitch.trailingAnchor constraintEqualToAnchor:masterRow.trailingAnchor constant:-16],
        [masterSwitch.centerYAnchor  constraintEqualToAnchor:masterRow.centerYAnchor],

        [separator.leadingAnchor  constraintEqualToAnchor:masterRow.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:masterRow.trailingAnchor],
        [separator.bottomAnchor   constraintEqualToAnchor:masterRow.bottomAnchor],
        [separator.heightAnchor   constraintEqualToConstant:0.5],

        [self.tableView.topAnchor      constraintEqualToAnchor:masterRow.bottomAnchor constant:16],
        [self.tableView.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [self.tableView.heightAnchor   constraintEqualToConstant:MIN(maxTH, 382)],

        [buttonBar.topAnchor      constraintEqualToAnchor:self.tableView.bottomAnchor],
        [buttonBar.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor],
        [buttonBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [buttonBar.bottomAnchor   constraintEqualToAnchor:card.bottomAnchor],
        [buttonBar.heightAnchor   constraintEqualToConstant:54],

        [btnSep.topAnchor      constraintEqualToAnchor:buttonBar.topAnchor],
        [btnSep.leadingAnchor  constraintEqualToAnchor:buttonBar.leadingAnchor],
        [btnSep.trailingAnchor constraintEqualToAnchor:buttonBar.trailingAnchor],
        [btnSep.heightAnchor   constraintEqualToConstant:0.5],

        [cancelBtn.leadingAnchor constraintEqualToAnchor:buttonBar.leadingAnchor],
        [cancelBtn.topAnchor     constraintEqualToAnchor:buttonBar.topAnchor constant:0.5],
        [cancelBtn.bottomAnchor  constraintEqualToAnchor:buttonBar.bottomAnchor],
        [cancelBtn.widthAnchor   constraintEqualToAnchor:buttonBar.widthAnchor multiplier:0.5],

        [saveBtn.trailingAnchor constraintEqualToAnchor:buttonBar.trailingAnchor],
        [saveBtn.topAnchor      constraintEqualToAnchor:buttonBar.topAnchor constant:0.5],
        [saveBtn.bottomAnchor   constraintEqualToAnchor:buttonBar.bottomAnchor],
        [saveBtn.widthAnchor    constraintEqualToAnchor:buttonBar.widthAnchor multiplier:0.5],

        [btnDivider.centerXAnchor constraintEqualToAnchor:buttonBar.centerXAnchor],
        [btnDivider.topAnchor     constraintEqualToAnchor:buttonBar.topAnchor constant:10],
        [btnDivider.bottomAnchor  constraintEqualToAnchor:buttonBar.bottomAnchor constant:-10],
        [btnDivider.widthAnchor   constraintEqualToConstant:0.5],
    ]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ads_ui_cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ads_ui_cell"];

    NSDictionary *row = self.rows[(NSUInteger)indexPath.row];
    NSString *key = row[@"key"];

    BOOL isGlobalON = [self isGlobalTweakEnabled];
    BOOL isMasterON = [self isMasterRuleEnabled];
    BOOL isGlobalOverride = [self isGlobalOverrideForKey:key];
    
    BOOL rowEnabled = isGlobalON && isMasterON && !isGlobalOverride && [row[@"enabled"] boolValue];
    BOOL isJITRow = [key isEqualToString:@"disableJIT"] || [key isEqualToString:@"disableJIT15"];

    BOOL isOn = [self isOnForKey:key masterOn:isMasterON];
    if ([key isEqualToString:@"disableJS"]) self.jsLocked = isOn;

    if (isJITRow && self.jsLocked && !isGlobalOverride) {
        isOn = YES;
        rowEnabled = NO;
    }

    if (!isGlobalON || !isMasterON) {
        isOn = NO;
        rowEnabled = NO;
    } else if (isGlobalOverride) {
        isOn = YES;
        rowEnabled = NO;
    }

    cell.textLabel.text           = row[@"title"];
    cell.textLabel.font           = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    cell.detailTextLabel.text     = row[@"detail"];
    cell.detailTextLabel.font     = [UIFont systemFontOfSize:11];
    cell.backgroundColor          = [UIColor colorWithWhite:0.13 alpha:1];
    cell.selectionStyle           = UITableViewCellSelectionStyleNone;

    if (rowEnabled) {
        cell.textLabel.textColor       = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.48 alpha:1];
        cell.userInteractionEnabled    = YES;
    } else {
        cell.textLabel.textColor       = [UIColor colorWithWhite:0.35 alpha:1];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.30 alpha:1];
        cell.userInteractionEnabled    = NO;
    }

    UISwitch *sw;
    if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
        sw = (UISwitch *)cell.accessoryView;
    } else {
        sw = [[UISwitch alloc] init];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }
    sw.tag         = indexPath.row;
    sw.enabled     = rowEnabled;
    sw.onTintColor = rowEnabled ? [UIColor systemBlueColor] : [UIColor colorWithWhite:0.25 alpha:1];
    sw.on          = isOn;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 52; }

- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag == NSIntegerMax) {
        self.pendingPrefs[@"_intendedMasterState"] = @(sender.on);
        [UIView animateWithDuration:0.25 animations:^{
            sender.superview.backgroundColor = sender.on
                ? [UIColor colorWithRed:0.08 green:0.25 blue:0.12 alpha:1.0]
                : [UIColor colorWithRed:0.25 green:0.08 blue:0.08 alpha:1.0];
        }];
        [self.tableView reloadData];
        return;
    }

    NSString *key = self.rows[(NSUInteger)sender.tag][@"key"];
    self.pendingRules[key] = @(sender.on);
    
    if ([key isEqualToString:@"disableJS"]) {
        self.jsLocked = sender.on;
        [self.tableView reloadData];
    }
}

- (void)tappedBackground:(UITapGestureRecognizer *)tap { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)saveAndRestart {
    NSString *rulesKey = [NSString stringWithFormat:@"TargetRules_%@", self.currentBundleID];
    self.pendingPrefs[rulesKey] = [self.pendingRules copy];
    
    id intendedState = self.pendingPrefs[@"_intendedMasterState"];
    if (intendedState) {
        BOOL enable = [intendedState boolValue];
        BOOL isPreset = [self isPresetApp];

        id existingDisabled = self.pendingPrefs[@"disabledPresetRules"];
        NSMutableArray *disabled = [existingDisabled isKindOfClass:[NSArray class]] ? [existingDisabled mutableCopy] : [NSMutableArray array];

        if (isPreset) {
            if (enable) [disabled removeObject:self.currentBundleID];
            else if (![disabled containsObject:self.currentBundleID]) [disabled addObject:self.currentBundleID];
            
            self.pendingPrefs[@"disabledPresetRules"] = disabled;
            NSString *restrictKey = [NSString stringWithFormat:@"restrictedApps-%@", self.currentBundleID];
            [self.pendingPrefs removeObjectForKey:restrictKey];
        } else {
            NSString *restrictKey = [NSString stringWithFormat:@"restrictedApps-%@", self.currentBundleID];
            self.pendingPrefs[restrictKey] = @(enable);
        }
        
        [self.pendingPrefs removeObjectForKey:@"_intendedMasterState"];
    }

    ads_ui_write_prefs(self.pendingPrefs);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Settings Saved"
        message:@"Changes to WebKit configuration only take effect after a full restart. Restart now?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart Now" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { exit(0); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { [self dismissViewControllerAnimated:YES completion:nil]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface ADSUIGestureHandler : NSObject
+ (instancetype)shared;
- (void)handleTap:(UITapGestureRecognizer *)sender;
@end

@implementation ADSUIGestureHandler
+ (instancetype)shared {
    static ADSUIGestureHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}
- (void)handleTap:(UITapGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) return;
    UIWindow *win = ads_ui_key_window();
    UIViewController *top = win ? ads_ui_top_vc(win.rootViewController) : nil;
    if (!top || [top isKindOfClass:[ADSUISettingsViewController class]]) return;
    ADSUISettingsViewController *vc = [[ADSUISettingsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle   = UIModalTransitionStyleCrossDissolve;
    [top presentViewController:vc animated:YES completion:nil];
}
@end

static void ads_ui_install_gesture(UIWindow *win) {
    if (!win || ads_ui_gesture_installed) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[ADSUIGestureHandler shared] action:@selector(handleTap:)];
    tap.numberOfTapsRequired    = 2;
    tap.numberOfTouchesRequired = 3;
    tap.cancelsTouchesInView    = NO;
    tap.delaysTouchesBegan      = NO;
    tap.delaysTouchesEnded      = NO;
    [win addGestureRecognizer:tap];
    ads_ui_gesture_installed = YES;
    ADSLog(@"[INIT] AntiDarkSword three-finger double-tap gesture installed.");
}

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    ads_ui_install_gesture(self);
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
    if ([path hasSuffix:@".appex"]) return;

    BOOL isUserApp      = [path localizedCaseInsensitiveContainsString:@"/Containers/Bundle/Application/"];
    BOOL isSystemOrJBApp = [path containsString:@"/Applications/"];

    NSArray *allowedServices = @[
        @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
        @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"
    ];
    BOOL isAllowedService = [allowedServices containsObject:bundleID];

    BOOL isManualOverride = NO;
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:ads_prefs_path()];
    if (!prefs) {
        CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            CFDictionaryRef dict = CFPreferencesCopyMultiple(keyList, CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (dict) prefs = (__bridge_transfer NSDictionary *)dict;
            CFRelease(keyList);
        }
    }
    if (prefs) {
        NSArray *customDaemons = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"] ?: @[];
        if ([customDaemons containsObject:bundleID] || [customDaemons containsObject:processName]) isManualOverride = YES;
        if (!isManualOverride && bundleID.length > 0) {
            NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", bundleID];
            if ([prefs[prefKey] boolValue]) isManualOverride = YES;
            else {
                NSDictionary *restrictedApps = prefs[@"restrictedApps"];
                if ([restrictedApps isKindOfClass:[NSDictionary class]] && [restrictedApps[bundleID] boolValue])
                    isManualOverride = YES;
            }
        }
    }

    if (!isUserApp && !isSystemOrJBApp && !isAllowedService && !isManualOverride) return;
    loadPrefs();
    ADSLog(@"[INIT] AntiDarkSwordUI loaded into: %@", processName);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)reloadPrefsNotification,
        CFSTR("com.eolnmsuk.antidarkswordprefs/saved"),
        NULL, CFNotificationSuspensionBehaviorCoalesce);
}
