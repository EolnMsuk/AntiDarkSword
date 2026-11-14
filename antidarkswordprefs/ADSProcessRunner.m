#import "ADSProcessRunner.h"
#include <spawn.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>

extern char **environ;
static char ADSCommandCountKey;

static double ADSMonotonicTime(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
}

static BOOL ADSWaitUntil(pid_t pid, double deadline, int *status, int *failure) {
    while (ADSMonotonicTime() < deadline) {
        pid_t result = waitpid(pid, status, WNOHANG);
        if (result == pid) return YES;
        if (result < 0 && errno != EINTR) { *failure = errno; return NO; }
        struct timespec pause = {0, 20 * 1000 * 1000};
        nanosleep(&pause, NULL);
    }
    return NO;
}

void ADSRunCommand(NSString *executable, const char * const *arguments, UIViewController *presenter) {
    NSCAssert(NSThread.isMainThread, @"Process controls must start on the UI thread");
    NSString *program = [executable copy];
    NSMutableArray<NSString *> *copy = [NSMutableArray arrayWithObject:program];
    for (NSUInteger i = 1; arguments && arguments[i]; i++) {
        NSString *value = [NSString stringWithUTF8String:arguments[i]];
        if (!value) return;
        [copy addObject:value];
    }
    NSArray<NSString *> *argvStrings = [copy copy];
    BOOL idempotentUnload = [program.lastPathComponent isEqualToString:@"launchctl"] &&
        argvStrings.count > 1 && [argvStrings[1] isEqualToString:@"unload"];
    NSUInteger pending = [objc_getAssociatedObject(presenter, &ADSCommandCountKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(presenter, &ADSCommandCountKey, @(pending), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    presenter.view.userInteractionEnabled = NO;
    __weak UIViewController *weakPresenter = presenter;
    static dispatch_queue_t commands;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ commands = dispatch_queue_create("com.eolnmsuk.antidarksword.process-controls", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(commands, ^{
        int failure = 0, status = 0;
        NSString *failureDetail = nil;
        char **argv = calloc(argvStrings.count + 1, sizeof(char *));
        pid_t pid = 0;
        if (!argv) failure = ENOMEM;
        else {
            for (NSUInteger i = 0; i < argvStrings.count; i++) argv[i] = (char *)argvStrings[i].UTF8String;
            failure = posix_spawn(&pid, program.fileSystemRepresentation, NULL, NULL, argv, environ);
            free(argv);
        }
        if (!failure) {
            BOOL exited = ADSWaitUntil(pid, ADSMonotonicTime() + 5, &status, &failure);
            if (!exited && !failure) {
                kill(pid, SIGTERM);
                exited = ADSWaitUntil(pid, ADSMonotonicTime() + 1, &status, &failure);
                if (!exited && !failure) {
                    kill(pid, SIGKILL);
                    exited = ADSWaitUntil(pid, ADSMonotonicTime() + 1, &status, &failure);
                }
                failure = ETIMEDOUT;
                if (!exited) {
                    // Reap a delayed kernel exit without another blocking wait.
                    dispatch_source_t reaper = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid, DISPATCH_PROC_EXIT, commands);
                    if (reaper) {
                        dispatch_source_set_event_handler(reaper, ^{
                            waitpid(pid, NULL, WNOHANG);
                            dispatch_source_set_event_handler(reaper, nil);
                            dispatch_source_cancel(reaper);
                        });
                        dispatch_resume(reaper);
                    }
                }
            } else if (exited && !WIFEXITED(status)) {
                failure = EIO;
                failureDetail = [NSString stringWithFormat:@"Command terminated by signal %d.", WTERMSIG(status)];
            } else if (exited && WEXITSTATUS(status) != 0 && !idempotentUnload) {
                failure = EIO;
                failureDetail = [NSString stringWithFormat:@"Command exited with status %d.", WEXITSTATUS(status)];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *controller = weakPresenter;
            if (!controller) return;
            NSUInteger count = [objc_getAssociatedObject(controller, &ADSCommandCountKey) unsignedIntegerValue];
            count = count ? count - 1 : 0;
            objc_setAssociatedObject(controller, &ADSCommandCountKey, @(count), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            controller.view.userInteractionEnabled = count == 0;
            if (!failure || !controller.view.window || controller.presentedViewController || controller.isBeingDismissed ||
                UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            if (controller.navigationController && controller.navigationController.topViewController != controller) return;
            NSString *detail = failureDetail ?: [NSString stringWithUTF8String:strerror(failure)];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Process Control Failed"
                message:[NSString stringWithFormat:@"%@: %@", program.lastPathComponent, detail]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [controller presentViewController:alert animated:YES completion:nil];
        });
    });
}
