#pragma once
#import <Foundation/Foundation.h>
#include <unistd.h>
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#include <roothide.h>
#endif

// Jailbreak-install files only; mobile preferences belong to the original root.
static inline NSString *ADSJailbreakPath(NSString *path) {
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
    return jbroot(path); // typed NSString overload; no caller-owned C buffer
#elif defined(THEOS_PACKAGE_SCHEME_ROOTLESS)
    if ([path hasPrefix:@"/var/jb/"]) return path;
    return [@"/var/jb" stringByAppendingString:path];
#else
    return path;
#endif
}

static inline NSString *ADSBootstrapArgument(NSString *path) {
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
    return rootfs(path); // bootstrap commands consume jbroot-based paths
#else
    return path;
#endif
}

static inline NSString *ADSMobilePreferencesPath(void) {
    return @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist";
}

static inline NSString *ADSLaunchctlPath(void) {
    NSString *path = ADSJailbreakPath(@"/usr/bin/launchctl");
    if (access(path.fileSystemRepresentation, X_OK) == 0) return path;
    // Search only inside the selected environment, never infer a new prefix.
    return ADSJailbreakPath(@"/bin/launchctl");
}
