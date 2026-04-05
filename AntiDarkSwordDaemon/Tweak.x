#import <Foundation/Foundation.h>

// =========================================================
// PRIVATE IMESSAGE INTERFACES (DAEMON LEVEL)
// =========================================================
@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

// Rootless Path
#define PREFS_PATH @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

static _Atomic BOOL currentProcessRestricted = NO;
static BOOL globalTweakEnabled = NO;
static BOOL globalDisableIMessageDL = NO;
static BOOL disableIMessageDL = NO;
static BOOL applyDisableIMessageDL = NO;

static void loadPrefs() {
    NSDictionary *prefs = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    }
    
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

    if (prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        globalTweakEnabled = [prefs[@"enabled"] respondsToSelector:@selector(boolValue)] ? [prefs[@"enabled"] boolValue] : NO;
        globalDisableIMessageDL = [prefs[@"globalDisableIMessageDL"] respondsToSelector:@selector(boolValue)] ? [prefs[@"globalDisableIMessageDL"] boolValue] : NO;
        autoProtectLevel = [prefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)] ? [prefs[@"autoProtectLevel"] integerValue] : 1;
        
        id customDaemonIDsRaw = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"];
        if ([customDaemonIDsRaw isKindOfClass:[NSArray class]]) {
            activeCustomDaemonIDs = customDaemonIDsRaw;
        }
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isTargetRestricted = NO;
    BOOL isPresetMatch = NO;
    NSString *matchedID = nil;
    
    if (bundleID && [activeCustomDaemonIDs containsObject:bundleID]) {
        isTargetRestricted = YES;
        matchedID = bundleID;
    } else if (processName && [activeCustomDaemonIDs containsObject:processName]) {
        isTargetRestricted = YES;
        matchedID = processName;
    }

    if (!isTargetRestricted && globalTweakEnabled) {
        NSArray *tier3 = @[
            @"com.apple.imagent", @"imagent", @"mediaserverd", @"networkd", @"apsd", @"identityservicesd"
        ];
        
        if (autoProtectLevel >= 3) {
            if (bundleID && [tier3 containsObject:bundleID]) {
                isTargetRestricted = YES;
                matchedID = bundleID;
                isPresetMatch = YES;
            } else if (processName && [tier3 containsObject:processName]) {
                isTargetRestricted = YES;
                matchedID = processName;
                isPresetMatch = YES;
            }
        }
    }
    
    currentProcessRestricted = (globalTweakEnabled && isTargetRestricted);
    disableIMessageDL = NO;

    if (currentProcessRestricted && isPresetMatch) {
        if ([matchedID containsString:@"imagent"]) {
            disableIMessageDL = YES;
        }
    }

    if (currentProcessRestricted && matchedID && prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", matchedID];
        NSDictionary *appRules = prefs[dictKey];
        if (appRules && [appRules isKindOfClass:[NSDictionary class]]) {
            if ([appRules[@"disableIMessageDL"] respondsToSelector:@selector(boolValue)]) {
                disableIMessageDL = [appRules[@"disableIMessageDL"] boolValue];
            }
        }
    }

    applyDisableIMessageDL = globalTweakEnabled && (globalDisableIMessageDL || (currentProcessRestricted && disableIMessageDL));
}

%ctor {
    loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}

// =========================================================
// NATIVE IMESSAGE MITIGATIONS (BACKGROUND DAEMON)
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
