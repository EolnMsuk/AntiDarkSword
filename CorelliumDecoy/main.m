#include <CoreFoundation/CoreFoundation.h>
#include <unistd.h>
#include <signal.h>

void term(int signum) {
    // Clean exit
    exit(0);
}

int main(int argc, char *argv[], char *envp[]) {
    // Use practically zero CPU cycles while maintaining a process ID
    struct sigaction sig;
    sig.sa_handler = term;
    sigemptyset(&sig.sa_mask);
    sig.sa_flags = 0;
    sigaction(SIGTERM, &sig, NULL);
    
    CFRunLoopRun();
    return 0;
}
