#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

static BOOL tweakEnabled = YES;
static NSArray *restrictedApps = nil;
static NSString *customRestrictedApps = @"";

// Read from the preferences using NSUserDefaults to bypass caching issues
static void loadPrefs() {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    
    if (prefs) {
        tweakEnabled = [prefs objectForKey:@"enabled"] ? [prefs boolForKey:@"enabled"] : YES;
        restrictedApps = [prefs arrayForKey:@"restrictedApps"] ?: @[];
        customRestrictedApps = [prefs stringForKey:@"customRestrictedApps"] ?: @"";
    }
}

// Check if the current app is allowed to run JavaScript
static BOOL isAppWhitelisted() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return YES; 
    
    // 1. Check if the app was explicitly toggled OFF in AltList (meaning it is restricted)
    // When defaultApplicationSwitchValue is true, AltList saves the disabled apps.
    if (restrictedApps && [restrictedApps containsObject:bundleID]) {
        return NO;
    }
    
    // 2. Check if the app was manually typed into the Advanced text box to be restricted
    if (customRestrictedApps && ![customRestrictedApps isEqualToString:@""]) {
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

%hookf(JSValueRef, JSEvaluateScript, JSContextRef ctx, JSStringRef script, JSObjectRef thisObject, JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception) {
    if (tweakEnabled && !isAppWhitelisted()) {
        return NULL;
    }
    return %orig(ctx, script, thisObject, sourceURL, startingLineNumber, exception);
}
