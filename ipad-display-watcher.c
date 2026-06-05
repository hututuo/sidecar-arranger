/*
 * iPad Display Watcher
 *
 * Polls CoreGraphics display state every 3 seconds. When a new non-built-in,
 * non-known display appears, it asks where the iPad/Sidecar display should sit
 * relative to the built-in MacBook display.
 *
 * Privacy note: this program only reads display IDs, geometry, vendor IDs and
 * model IDs. It does not inspect windows, files, clipboard contents, screens,
 * camera, microphone, keyboard input, or network traffic.
 */

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ctype.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAX_DISPLAYS 32

static const struct {
    uint32_t vendor;
    uint32_t model;
} default_known_monitors[] = {
    { 19491, 9571 },  /* G4Q */
};

static CGDirectDisplayID promptedID = 0;
static uint32_t lastDisplayCount = 0;
static bool dialogOpen = false;
static unsigned int displayListFailures = 0;

static const char *home_dir(void) {
    const char *home = getenv("HOME");
    if (home && home[0]) return home;

    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_dir && pw->pw_dir[0]) return pw->pw_dir;
    return NULL;
}

static char *trim(char *s) {
    while (isspace((unsigned char)*s)) s++;
    if (*s == '\0') return s;

    char *end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end)) {
        *end = '\0';
        end--;
    }
    return s;
}

static bool config_path(char path[PATH_MAX]) {
    const char *override = getenv("IPAD_DISPLAY_WATCHER_CONFIG");
    if (override && override[0]) {
        snprintf(path, PATH_MAX, "%s", override);
        return true;
    }

    const char *home = home_dir();
    if (!home || !home[0]) return false;
    snprintf(path, PATH_MAX, "%s/.config/ipad-display-watcher/known-monitors.txt", home);
    return true;
}

static bool parse_monitor_line(char *line, uint32_t *vendor, uint32_t *model) {
    char *comment = strchr(line, '#');
    if (comment) *comment = '\0';

    char *s = trim(line);
    if (!s[0]) return false;

    unsigned int v = 0, m = 0;
    if (sscanf(s, "%u:%u", &v, &m) == 2 || sscanf(s, "%u %u", &v, &m) == 2) {
        *vendor = (uint32_t)v;
        *model = (uint32_t)m;
        return true;
    }
    return false;
}

static bool is_config_known_monitor(uint32_t vendor, uint32_t model) {
    char path[PATH_MAX];
    if (!config_path(path)) return false;

    FILE *fp = fopen(path, "r");
    if (!fp) return false;

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        uint32_t v = 0, m = 0;
        if (parse_monitor_line(line, &v, &m) && v == vendor && m == model) {
            fclose(fp);
            return true;
        }
    }
    fclose(fp);
    return false;
}

static bool is_known_monitor(CGDirectDisplayID did) {
    uint32_t v = CGDisplayVendorNumber(did);
    uint32_t m = CGDisplayModelNumber(did);

    for (size_t i = 0; i < sizeof(default_known_monitors) / sizeof(default_known_monitors[0]); i++) {
        if (default_known_monitors[i].vendor == v && default_known_monitors[i].model == m) {
            return true;
        }
    }
    return is_config_known_monitor(v, m);
}

static bool should_prompt(CGDirectDisplayID did) {
    if (CGDisplayIsBuiltin(did)) return false;
    if (is_known_monitor(did)) return false;
    return true;
}

static bool get_display_list(CGDirectDisplayID displays[MAX_DISPLAYS], uint32_t *count) {
    *count = 0;
    return CGGetActiveDisplayList(MAX_DISPLAYS, displays, count) == kCGErrorSuccess;
}

static bool display_count(uint32_t *count) {
    CGDirectDisplayID displays[MAX_DISPLAYS];
    return get_display_list(displays, count);
}

static CGDirectDisplayID find_promptable_secondary(void) {
    CGDirectDisplayID displays[MAX_DISPLAYS];
    uint32_t n = 0;
    if (!get_display_list(displays, &n)) return 0;

    CGDirectDisplayID mainDisplay = CGMainDisplayID();
    for (uint32_t i = 0; i < n; i++) {
        if (displays[i] != mainDisplay && should_prompt(displays[i])) {
            return displays[i];
        }
    }
    return 0;
}

static bool is_active(CGDirectDisplayID target) {
    CGDirectDisplayID displays[MAX_DISPLAYS];
    uint32_t n = 0;
    if (!get_display_list(displays, &n)) return false;

    for (uint32_t i = 0; i < n; i++) {
        if (displays[i] == target) return true;
    }
    return false;
}

static int set_pos(CGDirectDisplayID target, int32_t x, int32_t y) {
    CGDisplayConfigRef cfg = NULL;
    if (CGBeginDisplayConfiguration(&cfg) != kCGErrorSuccess) return 1;

    if (CGConfigureDisplayOrigin(cfg, target, x, y) != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(cfg);
        return 1;
    }

    return CGCompleteDisplayConfiguration(cfg, kCGConfigurePermanently) == kCGErrorSuccess ? 0 : 1;
}

static int move_display(CGDirectDisplayID target, const char *pos) {
    CGDirectDisplayID displays[MAX_DISPLAYS];
    uint32_t n = 0;
    if (!get_display_list(displays, &n) || n < 2) return 1;

    CGDirectDisplayID mac = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (CGDisplayIsBuiltin(displays[i])) {
            mac = displays[i];
            break;
        }
    }
    if (!mac || !target || mac == target) return 1;

    CGRect macBounds = CGDisplayBounds(mac);
    int32_t mX = (int32_t)macBounds.origin.x;
    int32_t mY = (int32_t)macBounds.origin.y;
    int32_t mW = (int32_t)macBounds.size.width;
    int32_t mH = (int32_t)macBounds.size.height;
    int32_t tW = (int32_t)CGDisplayBounds(target).size.width;
    int32_t tH = (int32_t)CGDisplayBounds(target).size.height;

    if (!strcmp(pos, "left")) return set_pos(target, mX - tW, mY);
    if (!strcmp(pos, "right")) return set_pos(target, mX + mW, mY);
    if (!strcmp(pos, "below")) return set_pos(target, mX, mY + mH);
    if (!strcmp(pos, "above")) {
        /*
         * macOS may snap the iPad X coordinate when placing it above. Moving it
         * left first preserves the intended X coordinate, then only Y changes.
         */
        if (set_pos(target, mX - tW, mY) != 0) return 1;
        CGRect r = CGDisplayBounds(target);
        return set_pos(target, (int32_t)r.origin.x, mY - tH);
    }
    return 1;
}

static void run_osascript(const char *script) {
    pid_t pid = fork();
    if (pid == 0) {
        int nullfd = open("/dev/null", O_WRONLY);
        if (nullfd >= 0) {
            dup2(nullfd, STDOUT_FILENO);
            dup2(nullfd, STDERR_FILENO);
            close(nullfd);
        }
        execl("/usr/bin/osascript", "osascript", "-e", script, (char *)NULL);
        _exit(127);
    }
    if (pid > 0) {
        int status = 0;
        waitpid(pid, &status, 0);
    }
}

static void notify_result(bool ok) {
    run_osascript(ok
        ? "display notification \"已排列\" with title \"iPad 排列\""
        : "display notification \"失败\" with title \"iPad 排列\"");
}

static bool dialog_path(char path[PATH_MAX]) {
    const char *override = getenv("IPAD_DIALOG");
    if (override && override[0]) {
        snprintf(path, PATH_MAX, "%s", override);
        return true;
    }

    const char *home = home_dir();
    if (!home || !home[0]) return false;
    snprintf(path, PATH_MAX, "%s/.local/bin/ipad-dialog", home);
    return true;
}

static bool valid_dialog_output(const char *s) {
    return !strcmp(s, "left") || !strcmp(s, "right") ||
           !strcmp(s, "above") || !strcmp(s, "below") ||
           !strcmp(s, "cancel");
}

static char *ask_position(void) {
    static char buf[16];
    buf[0] = '\0';

    char path[PATH_MAX];
    if (!dialog_path(path)) return NULL;

    int fds[2];
    if (pipe(fds) != 0) return NULL;

    pid_t pid = fork();
    if (pid == 0) {
        close(fds[0]);
        dup2(fds[1], STDOUT_FILENO);
        close(fds[1]);
        execl(path, path, (char *)NULL);
        _exit(127);
    }

    close(fds[1]);
    if (pid < 0) {
        close(fds[0]);
        return NULL;
    }

    ssize_t len = read(fds[0], buf, sizeof(buf) - 1);
    close(fds[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    if (len <= 0) return NULL;
    buf[len] = '\0';
    buf[strcspn(buf, "\r\n")] = '\0';

    if (!valid_dialog_output(buf)) return NULL;
    return buf;
}

static void check(void) {
    uint32_t curCount = 0;
    if (!display_count(&curCount)) {
        if (displayListFailures++ == 0) {
            fprintf(stderr, "[CHECK] display list unavailable\n");
            fflush(stderr);
        }
        return;
    }

    if (displayListFailures > 0) {
        fprintf(stderr, "[CHECK] display list restored after %u failures\n", displayListFailures);
        displayListFailures = 0;
    }

    CGDirectDisplayID cur = find_promptable_secondary();

    if (curCount < lastDisplayCount) {
        fprintf(stderr, "[CHECK] count dropped %u->%u\n", lastDisplayCount, curCount);
        promptedID = 0;
    }
    lastDisplayCount = curCount;

    if (promptedID != 0 && !is_active(promptedID)) {
        fprintf(stderr, "[CHECK] 0x%x gone, reset\n", promptedID);
        promptedID = 0;
    }

    if (cur == 0) return;
    if (cur == promptedID) return;

    fprintf(stderr, "[CHECK] display 0x%x (prev=0x%x count=%u)\n", cur, promptedID, curCount);
    fflush(stderr);

    promptedID = cur;
    if (dialogOpen) return;

    dialogOpen = true;
    char *pos = ask_position();
    dialogOpen = false;

    if (!pos || !strcmp(pos, "cancel")) return;

    int result = move_display(cur, pos);
    notify_result(result == 0);
}

static void timer_cb(CFRunLoopTimerRef timer, void *info) {
    (void)timer;
    (void)info;
    check();
}

int main(int argc, char **argv) {
    if (argc == 2) {
        if (!strcmp(argv[1], "--count")) {
            uint32_t n = 0;
            if (!display_count(&n)) return 1;
            printf("%u\n", n);
            return 0;
        }

        if (!strcmp(argv[1], "--config-path")) {
            char path[PATH_MAX];
            if (!config_path(path)) return 1;
            printf("%s\n", path);
            return 0;
        }

        if (!strcmp(argv[1], "--list")) {
            CGDirectDisplayID displays[MAX_DISPLAYS];
            uint32_t n = 0;
            if (!get_display_list(displays, &n)) return 1;

            CGDirectDisplayID mainDisplay = CGMainDisplayID();
            for (uint32_t i = 0; i < n; i++) {
                CGRect b = CGDisplayBounds(displays[i]);
                printf("0x%x %s %.0fx%.0f vendor=%u model=%u builtin=%d prompt=%d\n",
                    displays[i],
                    displays[i] == mainDisplay ? "MAIN" : "SEC",
                    b.size.width,
                    b.size.height,
                    CGDisplayVendorNumber(displays[i]),
                    CGDisplayModelNumber(displays[i]),
                    CGDisplayIsBuiltin(displays[i]),
                    should_prompt(displays[i]));
            }
            return 0;
        }

        if (!strcmp(argv[1], "left") || !strcmp(argv[1], "right") ||
            !strcmp(argv[1], "above") || !strcmp(argv[1], "below")) {
            return move_display(find_promptable_secondary(), argv[1]);
        }

        fprintf(stderr, "Usage: %s [left|right|above|below|--count|--list|--config-path]\n", argv[0]);
        return 2;
    }

    if (!display_count(&lastDisplayCount)) {
        lastDisplayCount = 0;
    }
    fprintf(stderr, "[START] pid=%d displays=%u\n", getpid(), lastDisplayCount);
    fprintf(stderr, "[READY] every 3s\n");
    fflush(stderr);

    check();

    CFRunLoopTimerContext ctx = { 0 };
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + 3.0,
        3.0,
        0,
        0,
        timer_cb,
        &ctx);

    if (timer) {
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopDefaultMode);
        CFRelease(timer);
    }

    CFRunLoopRun();
    return 0;
}
