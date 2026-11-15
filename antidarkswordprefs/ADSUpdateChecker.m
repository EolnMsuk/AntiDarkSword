#import "ADSUpdateChecker.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString * const ADSLatestRelease = @"https://api.github.com/repos/EolnMsuk/AntiDarkSword/releases/latest";
static NSUInteger const ADSResponseLimit = 64 * 1024;
static NSArray<NSString *> *ADSVersionParts(NSString *version);

NSString *ADSInstalledPreferencesVersion(Class owningClass) {
    id value = [[NSBundle bundleForClass:owningClass] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [value isKindOfClass:NSString.class] && ADSVersionParts(value) ? value : nil;
}

// Compare decimal components by length and then digits, with no integer overflow.
// A published vX.Y.Z-bN release has the same project version as X.Y.Z.
static NSArray<NSString *> *ADSVersionParts(NSString *version) {
    if (![version isKindOfClass:NSString.class] || version.length > 128) return nil;
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:
            @"^v?((?:0|[1-9][0-9]*))\\.((?:0|[1-9][0-9]*))\\.((?:0|[1-9][0-9]*))(?:-b[0-9]+)?$" options:0 error:nil];
    });
    NSTextCheckingResult *match = [pattern firstMatchInString:version options:0 range:NSMakeRange(0, version.length)];
    if (!match || !NSEqualRanges(match.range, NSMakeRange(0, version.length))) return nil;
    return @[[version substringWithRange:[match rangeAtIndex:1]],
             [version substringWithRange:[match rangeAtIndex:2]],
             [version substringWithRange:[match rangeAtIndex:3]]];
}

static NSComparisonResult ADSCompareParts(NSArray<NSString *> *a, NSArray<NSString *> *b) {
    for (NSUInteger i = 0; i < 3; i++) {
        if (a[i].length != b[i].length) return a[i].length < b[i].length ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult result = [a[i] compare:b[i] options:NSLiteralSearch];
        if (result != NSOrderedSame) return result;
    }
    return NSOrderedSame;
}

static BOOL ADSAPIURL(NSURL *url) {
    // Refuse cross-service redirects, credentials, ports, queries or alternate paths.
    return [url.absoluteString isEqualToString:ADSLatestRelease];
}

static BOOL ADSCanPresent(UIViewController *controller) {
    if (!controller.isViewLoaded || !controller.view.window || controller.presentedViewController ||
        controller.isBeingDismissed || controller.isMovingFromParentViewController ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    if (controller.navigationController && controller.navigationController.topViewController != controller) return NO;
    if (@available(iOS 13.0, *)) {
        if (controller.view.window.windowScene.activationState != UISceneActivationStateForegroundActive) return NO;
    }
    return YES;
}

@interface ADSUpdateChecker () <NSURLSessionDataDelegate>
@end

@implementation ADSUpdateChecker {
    dispatch_queue_t _queue;
    NSURLSession *_session;
    NSURLSessionDataTask *_task;
    NSMutableData *_body;
    NSString *_failure;
    NSString *_installed;
    __weak UIViewController *_presenter;
    NSMutableArray<dispatch_block_t> *_finished;
}

+ (instancetype)sharedChecker {
    static ADSUpdateChecker *checker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ checker = [self new]; });
    return checker;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.eolnmsuk.antidarksword.updates", DISPATCH_QUEUE_SERIAL);
        _finished = [NSMutableArray array];
        NSOperationQueue *delegates = [NSOperationQueue new];
        delegates.maxConcurrentOperationCount = 1;
        delegates.underlyingQueue = _queue;
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = 15;
        config.timeoutIntervalForResource = 20;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.URLCache = nil;
        config.HTTPCookieStorage = nil;
        config.HTTPShouldSetCookies = NO;
        config.URLCredentialStorage = nil;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:delegates];
    }
    return self;
}

- (void)checkForController:(UIViewController *)controller installedVersion:(NSString *)version
                 finished:(dispatch_block_t)finished {
    NSCAssert(NSThread.isMainThread, @"Update checks must originate from the settings UI");
    __weak UIViewController *weakController = controller;
    dispatch_async(_queue, ^{
        if (self->_task) {
            self->_presenter = weakController;
            if (finished) [self->_finished addObject:[finished copy]];
            return;
        }
        self->_presenter = weakController;
        if (finished) [self->_finished addObject:[finished copy]];
        self->_installed = [version copy];
        if (!ADSVersionParts(version)) {
            [self finishWithError:@"The installed AntiDarkSword preferences version is unavailable or invalid." tag:nil url:nil newer:NO];
            return;
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:ADSLatestRelease]];
        [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
        [request setValue:[@"AntiDarkSword-Preferences/" stringByAppendingString:version] forHTTPHeaderField:@"User-Agent"];
        self->_body = [NSMutableData data];
        self->_failure = nil;
        self->_task = [self->_session dataTaskWithRequest:request];
        [self->_task resume]; // only the explicit Updates action calls this method
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // The fixed canonical endpoint needs no redirect. Refuse even self-loops
    // rather than turning one logical check into repeated HTTP requests.
    if (task == _task) _failure = @"The release service attempted to redirect the request. No redirected request was sent.";
    completionHandler(nil);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (task != _task) { completionHandler(NSURLSessionResponseCancel); return; }
    if (![response isKindOfClass:NSHTTPURLResponse.class] || !ADSAPIURL(response.URL))
        _failure = @"Unexpected response from the release service.";
    else if (((NSHTTPURLResponse *)response).statusCode != 200)
        _failure = [NSString stringWithFormat:@"GitHub returned HTTP %ld. Try again later.", (long)((NSHTTPURLResponse *)response).statusCode];
    else if (response.expectedContentLength > (int64_t)ADSResponseLimit)
        _failure = @"The release response is too large.";
    completionHandler(_failure ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (task != _task) return;
    if (data.length > ADSResponseLimit - _body.length) {
        _failure = @"The release response is too large.";
        [task cancel];
    } else if (!_failure) [_body appendData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (task != _task) return; // obsolete/cancelled task callbacks never touch a newer request
    if (_failure || error) {
        [self finishWithError:_failure ?: [NSString stringWithFormat:@"Unable to check for updates: %@", error.localizedDescription]
                         tag:nil url:nil newer:NO];
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:_body options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
        [self finishWithError:@"GitHub returned invalid release metadata." tag:nil url:nil newer:NO]; return;
    }
    NSDictionary *release = json;
    id draft = release[@"draft"], prerelease = release[@"prerelease"];
    NSString *tag = release[@"tag_name"];
    id link = release[@"html_url"];
    BOOL booleans = draft && prerelease && CFGetTypeID((__bridge CFTypeRef)draft) == CFBooleanGetTypeID() &&
        CFGetTypeID((__bridge CFTypeRef)prerelease) == CFBooleanGetTypeID();
    NSArray *remote = ADSVersionParts(tag), *local = ADSVersionParts(_installed);
    NSString *expected = remote ? [@"https://github.com/EolnMsuk/AntiDarkSword/releases/tag/" stringByAppendingString:tag] : nil;
    if (!booleans || [draft boolValue] || [prerelease boolValue] || !remote || !local ||
        ![link isKindOfClass:NSString.class] || ![link isEqualToString:expected]) {
        [self finishWithError:@"No comparable, valid stable release was returned by the official repository." tag:nil url:nil newer:NO]; return;
    }
    [self finishWithError:nil tag:tag url:[NSURL URLWithString:link]
                   newer:ADSCompareParts(local, remote) == NSOrderedAscending];
}

- (void)finishWithError:(NSString *)error tag:(NSString *)tag url:(NSURL *)url newer:(BOOL)newer {
    __weak UIViewController *presenter = _presenter;
    NSArray<dispatch_block_t> *finished = [_finished copy];
    NSString *installed = _installed;
    [_finished removeAllObjects];
    _task = nil; _body = nil; _failure = nil; _presenter = nil; _installed = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (dispatch_block_t done in finished) done();
        UIViewController *controller = presenter;
        if (!ADSCanPresent(controller)) return;
        NSString *title = error ? @"Update Check Failed" : newer ? @"Update Available" : @"Up to Date";
        NSString *message = error ?: [NSString stringWithFormat:@"Installed: %@\nLatest stable release: %@", installed, tag ?: @"Unavailable"];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        if (newer && url) {
            [alert addAction:[UIAlertAction actionWithTitle:@"View Release" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:newer ? @"Cancel" : @"OK" style:UIAlertActionStyleCancel handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}
@end
