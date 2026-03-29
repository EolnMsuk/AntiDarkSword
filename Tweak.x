#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

static BOOL tweakEnabled = YES;
static NSArray *restrictedApps = nil;
static NSString *customRestrictedApps = @"";

// Define preference paths for both rootless and rootful jailbreaks
#define PREFS_PATH_ROOTLESS @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"
#define PREFS_PATH_ROOTFUL @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

// Read directly from the plist file to bypass NSUserDefaults sandboxing blocks
static void loadPrefs() {
    NSDictionary *prefs = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH_ROOTLESS]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH_ROOTLESS];
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH_ROOTFUL]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH_ROOTFUL];
    }

    if (prefs) {
        tweakEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        restrictedApps = prefs[@"restrictedApps"] ?: @[];
        customRestrictedApps = prefs[@"customRestrictedApps"] ?: @"";
    } else {
        // Safe defaults if prefs haven't been generated yet
        tweakEnabled = YES;
        restrictedApps = @[];
        customRestrictedApps = @"";
    }
}

// Check if the current app is allowed to run JavaScript
static BOOL isAppWhitelisted() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return YES; 
    
    // 1. Check if the app was explicitly toggled OFF in AltList
    if (restrictedApps && [restrictedApps containsObject:bundleID]) {
        return NO;
    }
    
    // 2. Check if the app was manually typed into the Advanced text box
    if (customRestrictedApps && customRestrictedApps.length > 0) {
        if ([customRestrictedApps containsString:bundleID]) {
            return NO;
        }
    }
    
    // By default, apps are allowed
    return YES;
}

// Constructor to load prefs and listen for changes
%ctor {
    loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}

// Intercept Initialization
%hook WKWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if (tweakEnabled && !isAppWhitelisted()) {
        if ([configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        }
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) {
            configuration.preferences.javaScriptEnabled = NO;
        }
    }
    return %orig(frame, configuration);
}
%end

// Intercept Late Configuration Changes (Crucial for Safari)
%hook WKWebpagePreferences
- (void)setAllowsContentJavaScript:(BOOL)allowed {
    // Force NO if the app is restricted, even if the app tries to pass YES
    if (tweakEnabled && !isAppWhitelisted() && allowed) {
        return %orig(NO);
    }
    %orig;
}
%end

%hook WKPreferences
- (void)setJavaScriptEnabled:(BOOL)enabled {
    // Force NO if the app is restricted, even if the app tries to pass YES
    if (tweakEnabled && !isAppWhitelisted() && enabled) {
        return %orig(NO);
    }
    %orig;
}
%end

// Global JavaScriptCore Kill-Switch
%hookf(JSValueRef, JSEvaluateScript, JSContextRef ctx, JSStringRef script, JSObjectRef thisObject, JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception) {
    if (tweakEnabled && !isAppWhitelisted()) {
        return NULL;
    }
    return %orig(ctx, script, thisObject, sourceURL, startingLineNumber, exception);
}
