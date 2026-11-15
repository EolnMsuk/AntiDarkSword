#include <CoreFoundation/CoreFoundation.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>

static void term(int signum) {
    // exit() is not async-signal-safe; _exit() bypasses atexit handlers and stdio
    // flushing, which is the only safe call path from a signal handler.
    _exit(0);
}

int main(int argc, char *argv[], char *envp[]) {
    // Use practically zero CPU cycles while maintaining a process ID.
    // Handle all common termination signals for a clean exit.
    struct sigaction sig;
    sig.sa_handler = term;
    sigemptyset(&sig.sa_mask);
    sig.sa_flags = 0;
    sigaction(SIGTERM, &sig, NULL);
    sigaction(SIGINT,  &sig, NULL);
    sigaction(SIGHUP,  &sig, NULL);

    CFRunLoopRun();
    return 0;
}
