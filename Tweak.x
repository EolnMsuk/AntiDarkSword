#import <WebKit/WebKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

/**
 * Forward declare iOS 14+ properties to ensure the compiler succeeds 
 * across build environments utilizing older iOS SDKs.
 */
@interface WKWebpagePreferences (AntiDarkSword)
@property (nonatomic, assign) BOOL allowsContentJavaScript;
@end

/**
 * Define the preference bundle identifier used by the settings pane.
 */
#define PREF_DOMAIN CFSTR("com.eolnmsuk.antidarksword")

/**
 * Helper function to synchronously read the whitelist preferences.
 * By utilizing CFPreferencesCopyAppValue, we force a read that bypasses
 * standard NSUserDefaults caching, ensuring accurate state after a respring.
 */
static NSArray* getWhitelistedApps() {
    CFArrayRef appList = (CFArrayRef)CFPreferencesCopyAppValue(CFSTR("WhitelistedApps"), PREF_DOMAIN);
    if (appList && CFGetTypeID(appList) == CFArrayGetTypeID()) {
        NSArray *nsAppList = (__bridge NSArray *)appList;
        // The bridged array is autoreleased or manually retained based on ARC context,
        // we return a copy to ensure immutability.
        NSArray *returnValue = [nsAppList copy];
        CFRelease(appList);
        return returnValue;
    }
    if (appList) {
        CFRelease(appList);
    }
    // Return an empty array if the preference is missing or invalid.
    return @;
}

/**
 * Define a discrete hooking group for modular initialization.
 * These hooks will ONLY be applied if the current app is unwhitelisted.
 */
%group EnforceJavaScriptBlock

// ==============================================================================
// HOOK 1: WKWebViewConfiguration
// Intercept the configuration object before the WKWebView is instantiated.
// ==============================================================================
%hook WKWebViewConfiguration

- (instancetype)init {
    WKWebViewConfiguration *config = %orig;
    if (config) {
        // Step A: Address legacy iOS versions (iOS 13 and below)
        if () {
            WKPreferences *prefs = [config preferences];
            if () {
              ;
            }
        }

        // Step B: Address modern iOS versions (iOS 14 - 18+)
        // Overrides the defaultWebpagePreferences to block JS natively.
        if (@available(iOS 14.0, *)) {
            if () {
                WKWebpagePreferences *webPrefs =;
                if () {
                  ;
                }
            }
        }
    }
    return config;
}

%end

// ==============================================================================
// HOOK 2: WKWebpagePreferences (iOS 14+)
// Aggressively prevent the host application from dynamically re-enabling 
// JavaScript during navigation lifecycle events.
// ==============================================================================
%hook WKWebpagePreferences

- (void)setAllowsContentJavaScript:(BOOL)allowed {
    // Discard the application's requested state and force NO (blocked).
    %orig(NO);
}

- (BOOL)allowsContentJavaScript {
    // Force the getter to always return NO to satisfy any internal WebKit state checks.
    return NO;
}

%end

// ==============================================================================
// HOOK 3: WKPreferences (Legacy API)
// Ensure older code paths or specific internal Apple frameworks that still 
// rely on the legacy API cannot re-enable JavaScript.
// ==============================================================================
%hook WKPreferences

- (void)setJavaScriptEnabled:(BOOL)enabled {
    // Discard the application's requested state and force NO (blocked).
    %orig(NO);
}

- (BOOL)javaScriptEnabled {
    return NO;
}

%end

// ==============================================================================
// HOOK 4: WKWebView
// Secondary intervention point to intercept deep-linked content and 
// background loading mechanisms that might bypass configuration init.
// ==============================================================================
%hook WKWebView

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    // Perform a secondary enforcement check on the configuration object 
    // immediately prior to view instantiation.
    if (configuration) {
        if (@available(iOS 14.0, *)) {
            if () {
                setAllowsContentJavaScript:NO];
            }
        }
        if () {
            [[configuration preferences] setJavaScriptEnabled:NO];
        }
    }
    
    return %orig(frame, configuration);
}

%end

%end // End of EnforceJavaScriptBlock Group

// ==============================================================================
// CONSTRUCTOR: Initialization Logic
// Determines the runtime environment and applies the whitelist logic.
// ==============================================================================
%ctor {
    @autoreleasepool {
        // 1. Retrieve the bundle identifier of the current process
        NSString *currentBundleID = bundleIdentifier];
        if (!currentBundleID) return;

        // 2. Fetch the user's whitelist settings from the preference daemon
        NSArray *whitelistedApps = getWhitelistedApps();

        // 3. Evaluate the whitelist condition.
        // If the current app is NOT in the whitelist, we must block JavaScript.
        BOOL isWhitelisted =;

        if (!isWhitelisted) {
            // The application is unwhitelisted. Initialize the defensive hooks.
            // This ensures Safari, Messages, Mail, etc., are blocked unless 
            // the user explicitly adds them to the whitelist in settings.
            %init(EnforceJavaScriptBlock);
        }
    }
}
