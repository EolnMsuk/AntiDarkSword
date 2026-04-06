// AntiDarkSwordDaemon/Tweak.x
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

// =========================================================
// PRIVATE IMESSAGE INTERFACES
// =========================================================
@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

@interface CKAttachmentMessagePartChatItem : NSObject
- (BOOL)_needsPreviewGeneration;
@end

#define PREFS_PATH @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

static _Atomic BOOL currentProcessRestricted = NO;
static BOOL globalTweakEnabled = NO;
static BOOL globalUASpoofingEnabled = NO;
static NSString *customUAString = @"";
static BOOL shouldSpoofUA = NO;

// App-Specific Granular Features for Daemons
static BOOL globalDisableIMessageDL = NO;
static BOOL disableIMessageDL = NO;
static BOOL applyDisableIMessageDL = NO;

static void loadPrefs() {
    NSDictionary *prefs = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:ROOTFUL_PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:ROOTFUL_PREFS_PATH];
    }
    
    // Fallback via IPC CFPreferences
    if (!prefs || ![prefs isKindOfClass:[NSDictionary class]]) {
        CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            CFDictionaryRef dict = CFPreferencesCopyMultiple(keyList, CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (dict) {
                prefs = (__bridge_transfer NSDictionary *)dict;
            }
            CFRelease(keyList);
        }
    }

    NSInteger autoProtectLevel = 1;
    NSArray *activeCustomDaemonIDs = @[];
    NSArray *disabledPresetRules = @[];
    NSMutableArray *restrictedAppsArray = [NSMutableArray array];

    if (prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        id restrictedAppsRaw = prefs[@"restrictedApps"];
        if ([restrictedAppsRaw isKindOfClass:[NSDictionary class]]) {
            for (id key in [restrictedAppsRaw allKeys]) {
                if ([key isKindOfClass:[NSString class]] && [restrictedAppsRaw[key] respondsToSelector:@selector(boolValue)]) {
                    if ([restrictedAppsRaw[key] boolValue]) {
                        [restrictedAppsArray addObject:key];
                    }
                }
            }
        } else if ([restrictedAppsRaw isKindOfClass:[NSArray class]]) {
            for (id item in restrictedAppsRaw) {
                if ([item isKindOfClass:[NSString class]]) {
                    [restrictedAppsArray addObjectsFromArray:restrictedAppsRaw];
                }
            }
        }

        for (id key in [prefs allKeys]) {
            if ([key isKindOfClass:[NSString class]] && [key hasPrefix:@"restrictedApps-"]) {
                if ([prefs[key] respondsToSelector:@selector(boolValue)]) {
                    NSString *appID = [(NSString *)key substringFromIndex:@"restrictedApps-".length];
                    if ([prefs[key] boolValue]) {
                        if (![restrictedAppsArray containsObject:appID]) {
                            [restrictedAppsArray addObject:appID];
                        }
                    }
                }
            }
        }

        globalTweakEnabled = [prefs[@"enabled"] respondsToSelector:@selector(boolValue)] ? [prefs[@"enabled"] boolValue] : NO;
        globalUASpoofingEnabled = [prefs[@"globalUASpoofingEnabled"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalUASpoofingEnabled"] boolValue] : NO;
        globalDisableIMessageDL = [prefs[@"globalDisableIMessageDL"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableIMessageDL"] boolValue] : NO;

        autoProtectLevel = [prefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)] ? [prefs[@"autoProtectLevel"] integerValue] : 1;
        
        id customDaemonIDsRaw = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"];
        if ([customDaemonIDsRaw isKindOfClass:[NSArray class]]) {
            activeCustomDaemonIDs = customDaemonIDsRaw;
        }

        id disabledPresetRaw = prefs[@"disabledPresetRules"];
        if ([disabledPresetRaw isKindOfClass:[NSArray class]]) {
            disabledPresetRules = disabledPresetRaw;
        }
        
        id presetUARaw = prefs[@"selectedUAPreset"];
        NSString *presetUA = [presetUARaw isKindOfClass:[NSString class]] ? presetUARaw : nil;
        if (!presetUA || [presetUA isEqualToString:@"NONE"]) {
            presetUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
        }
        
        id manualUARaw = prefs[@"customUAString"];
        NSString *manualUA = [manualUARaw isKindOfClass:[NSString class]] ? manualUARaw : @"";
        if ([presetUA isEqualToString:@"CUSTOM"]) {
            NSString *trimmedUA = [manualUA stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!trimmedUA || trimmedUA.length == 0) {
                customUAString = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
            } else {
                customUAString = trimmedUA;
            }
        } else {
            customUAString = presetUA;
        }
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isTargetRestricted = NO;
    NSString *matchedID = nil;
    
    if (bundleID && [activeCustomDaemonIDs containsObject:bundleID]) {
        isTargetRestricted = YES;
        matchedID = bundleID;
    } else if (processName && [activeCustomDaemonIDs containsObject:processName]) {
        isTargetRestricted = YES;
        matchedID = processName;
    }

    if (!isTargetRestricted) {
        if (bundleID && [restrictedAppsArray containsObject:bundleID]) {
            isTargetRestricted = YES;
            matchedID = bundleID;
        } else if (processName && [restrictedAppsArray containsObject:processName]) {
            isTargetRestricted = YES;
            matchedID = processName;
        }
        
        if (!isTargetRestricted && globalTweakEnabled) {
            NSArray *tier1 = @[
                @"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail",
                @"com.apple.mobilecal", @"com.apple.mobilenotes", @"com.apple.iBooks",
                @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks", 
                @"com.apple.Maps", @"com.apple.weather",
                @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
                @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
                @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"
            ];
            NSArray *tier2 = @[
                @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail",
                @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", 
                @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", 
                @"com.tencent.xin", @"com.viber", @"jp.naver.line", @"net.whatsapp.WhatsApp", 
                @"com.hammerandchisel.discord",
                @"com.google.GoogleMobile", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", 
                @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios",
                @"pinterest", @"com.tumblr.tumblr", @"com.facebook.Facebook", @"com.atebits.Tweetie2", 
                @"com.burbn.instagram", @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn", 
                @"com.reddit.Reddit", @"com.google.ios.youtube", @"tv.twitch",
                @"com.google.gemini", @"com.openai.chat", @"com.deepseek.chat", @"com.github.stormbreaker.prod",
                @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza",
                @"com.squareup.cash", @"net.kortina.labs.Venmo", @"com.yourcompany.PPClient", 
                @"com.robinhood.release.Robinhood", @"com.vilcsak.bitcoin2", @"com.sixdays.trust", 
                @"io.metamask.MetaMask", @"app.phantom.phantom", @"com.chase", 
                @"com.bankofamerica.BofAMobileBanking", @"com.wellsfargo.net.mobilebanking", 
                @"com.citi.citimobile", @"com.capitalone.enterprisemobilebanking", 
                @"com.americanexpress.amelia", @"com.fidelity.iphone", @"com.schwab.mobile", 
                @"com.etrade.mobilepro.iphone", @"com.discoverfinancial.mobile", @"com.usbank.mobilebanking", 
                @"com.monzo.ios", @"com.revolut.iphone", @"com.binance.dev", @"com.kraken.invest", 
                @"com.barclays.ios.bmb", @"com.ally.auto", @"com.navyfederal.navyfederal.mydata"
            ];
            NSArray *tier3 = @[
                @"com.apple.imagent", @"imagent", @"mediaserverd", @"networkd", @"apsd", @"identityservicesd"
            ];
            
            NSString *targetMatch = nil;
            if (bundleID) {
                if ([tier1 containsObject:bundleID]) targetMatch = bundleID;
                else if (autoProtectLevel >= 2 && [tier2 containsObject:bundleID]) targetMatch = bundleID;
                else if (autoProtectLevel >= 3 && [tier3 containsObject:bundleID]) targetMatch = bundleID;
            }
            if (!targetMatch && processName) {
                if ([tier1 containsObject:processName]) targetMatch = processName;
                else if (autoProtectLevel >= 2 && [tier2 containsObject:processName]) targetMatch = processName;
                else if (autoProtectLevel >= 3 && [tier3 containsObject:processName]) targetMatch = processName;
            }
            
            if (targetMatch && ![disabledPresetRules containsObject:targetMatch]) {
                isTargetRestricted = YES;
                matchedID = targetMatch;
            }
        }
    }
    
    currentProcessRestricted = (globalTweakEnabled && isTargetRestricted);
    BOOL spoofUARule = YES;
    disableIMessageDL = NO;

    NSArray *daemons = @[
        @"com.apple.appstored", @"com.apple.itunesstored",
        @"com.apple.imagent", @"imagent", @"com.apple.mediaserverd", @"mediaserverd",
        @"com.apple.networkd", @"networkd", @"com.apple.apsd", @"apsd",
        @"com.apple.identityservicesd", @"identityservicesd", @"com.apple.nsurlsessiond",
        @"com.apple.cfnetwork"
    ];
    
    // Baseline setting overrides for Daemon defaults
    if (matchedID) {
        if ([daemons containsObject:matchedID]) {
            spoofUARule = NO;
        }
        if ([matchedID isEqualToString:@"com.apple.imagent"] || [matchedID isEqualToString:@"imagent"]) {
            disableIMessageDL = YES; 
        }
    } else if (processName) {
        if ([processName containsString:@"daemon"] || [processName hasSuffix:@"d"]) {
            spoofUARule = NO;
        }
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
    loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}

// =========================================================
// NATIVE HTTP HEADER SPOOFING 
// =========================================================

%hook NSMutableURLRequest
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (shouldSpoofUA) {
        if ([field caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
            return %orig(customUAString, field);
        }
    }
    %orig;
}
%end

// =========================================================
// GLOBAL NSUSERDEFAULTS SPOOFING
// =========================================================

%hook NSUserDefaults
- (id)objectForKey:(NSString *)defaultName {
    if (shouldSpoofUA) {
        if ([defaultName isEqualToString:@"UserAgent"] || [defaultName isEqualToString:@"User-Agent"]) {
            return customUAString;
        }
    }
    return %orig;
}

- (NSString *)stringForKey:(NSString *)defaultName {
    if (shouldSpoofUA) {
        if ([defaultName isEqualToString:@"UserAgent"] || [defaultName isEqualToString:@"User-Agent"]) {
            return customUAString;
        }
    }
    return %orig;
}
%end

// =========================================================
// NATIVE IMESSAGE MITIGATIONS (BLASTPASS / FORCEDENTRY)
// =========================================================

%hook IMFileTransfer
- (BOOL)isAutoDownloadable {
    if (applyDisableIMessageDL) {
        return NO;
    }
    return %orig;
}
- (BOOL)canAutoDownload {
    if (applyDisableIMessageDL) {
        return NO;
    }
    return %orig;
}
%end

%hook CKAttachmentMessagePartChatItem
- (BOOL)_needsPreviewGeneration {
    if (applyDisableIMessageDL) {
        return NO;
    }
    return %orig;
}
%end
