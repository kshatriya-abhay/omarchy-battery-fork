/*
 * Report the Cosmic Byte Aether mouse battery from its vendor hidraw interface.
 * Runs for the life of the shell and prints a JSON line whenever the reading
 * changes:
 *   {"pct":N,"state":"discharging",...}     on the 2.4 GHz dongle
 *   {"pct":null,"state":"charging",...}     on the cable
 *   {"absent":true}                         neither is attached
 *
 * Protocol, from the Cosmic Byte Orbit web configurator (AetherDriver.js):
 *   - the config interface is the hidraw node of VID 0x248A, PID 0x5B49
 *     (wired) or 0x5B4A (2.4 GHz dongle), whose descriptor uses usage page
 *     0xFF05 and report ID 0x09;
 *   - SET_FEATURE 09 81 01 00 00 00 00 00 00 makes the mouse push its state;
 *   - the state arrives as input report 09 <battery%> <stage|poll> ...
 * The mouse answers at most once every 5 s and ignores requests in between,
 * so a request is re-sent until a reply arrives. On the cable the firmware
 * reports 100 whatever the real charge, so the wired PID alone means
 * "charging" and the mouse is never asked.
 *
 * Kept cheap: hotplug comes from inotify on /dev, not polling. On the dongle
 * the battery is read every READ_INTERVAL_MS, and only once the mouse has
 * shown it's awake by sending input, so a sleeping mouse is never asked.
 * Once asked, the mouse keeps pushing its state every 5 s on its own, so the
 * config node is open only while a reading is taken; between readings the
 * process holds no device open and is blocked in poll().
 */

#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/hidraw.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <time.h>
#include <unistd.h>

#define AETHER_VENDOR_ID 0x248a
#define AETHER_WIRED_ID 0x5b49
#define AETHER_DONGLE_ID 0x5b4a
#define CONFIG_USAGE_PAGE 0xff05
#define STATE_REPORT_ID 0x09

#define READ_INTERVAL_MS (5 * 60 * 1000) /* battery moves slowly */
#define RETRY_MS (30 * 1000)             /* after a query got no reply, or a
                                            first reading after connecting */
#define QUERY_TIMEOUT_MS 6000            /* longer than the 5 s reply interval */
#define RESEND_MS 1000                   /* the mouse only answers on its 5 s tick */
#define SCAN_SETTLE_MS 300               /* let udev finish nodes and ACLs */
#define OPEN_RETRY_MS 2000               /* config node present but not openable yet */
#define MAX_INPUTS 4

#ifdef AETHER_TRACE
#define TRACE(...) (fprintf(stderr, "[%lld] ", (long long)monotonic_ms()), \
                    fprintf(stderr, __VA_ARGS__), fputc('\n', stderr))
#else
#define TRACE(...) ((void)0)
#endif

enum phase {
    IDLE,          /* waiting for the next reading to be due */
    WAIT_ACTIVITY, /* due: waiting for the mouse to send any input */
    QUERYING       /* request sent, waiting for the state report */
};

static struct {
    int wired;
    int config_number;     /* hidraw number of the dongle's config node, or -1 */
    int config_fd;         /* open only while QUERYING */
    int input_numbers[MAX_INPUTS];
    int input_count;
    int input_fds[MAX_INPUTS]; /* open only while waiting for activity */
    enum phase phase;
    int64_t due;           /* IDLE: when the next reading is due */
    int64_t query_deadline;
    int64_t next_resend;
    int64_t scan_at;       /* pending rescan, or -1 */
    int pct;               /* last dongle reading, or -1 */
    int settled;           /* a reading after the first since connecting */
    char last_line[256];
} aether;

static int64_t monotonic_ms(void)
{
    struct timespec now;

    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int hidraw_number(const char *name)
{
    const char *cursor;
    int number = 0;

    if (strncmp(name, "hidraw", 6) != 0 || name[6] == '\0')
        return -1;
    for (cursor = name + 6; *cursor; cursor++) {
        if (*cursor < '0' || *cursor > '9')
            return -1;
        number = number * 10 + *cursor - '0';
    }
    return number;
}

/* Read HID_ID=bus:vendor:product from sysfs, so no device node is opened. */
static int read_ids(int number, unsigned int *vendor, unsigned int *product)
{
    char path[96];
    char line[128];
    FILE *file;
    int found = 0;

    snprintf(path, sizeof(path), "/sys/class/hidraw/hidraw%d/device/uevent", number);
    file = fopen(path, "re");
    if (!file)
        return 0;
    while (!found && fgets(line, sizeof(line), file))
        found = sscanf(line, "HID_ID=%*x:%x:%x", vendor, product) == 2;
    fclose(file);
    return found;
}

/* Walk the report descriptor's short items looking for a Usage Page item. */
static int has_usage_page(int number, unsigned int wanted)
{
    char path[96];
    uint8_t descriptor[HID_MAX_DESCRIPTOR_SIZE];
    size_t size;
    size_t i = 0;
    FILE *file;

    snprintf(path, sizeof(path), "/sys/class/hidraw/hidraw%d/device/report_descriptor",
             number);
    file = fopen(path, "re");
    if (!file)
        return 0;
    size = fread(descriptor, 1, sizeof(descriptor), file);
    fclose(file);

    while (i < size) {
        uint8_t prefix = descriptor[i];
        size_t length = prefix & 3;
        unsigned int value = 0;
        size_t j;

        if (length == 3)
            length = 4;
        if (prefix == 0xfe) /* long item: skip its data */
            length = 2 + (i + 1 < size ? descriptor[i + 1] : 0);
        if (i + 1 + length > size)
            break;
        for (j = 0; j < length && j < 4; j++)
            value |= (unsigned int)descriptor[i + 1 + j] << (8 * j);
        if ((prefix & 0xfc) == 0x04 && value == wanted)
            return 1;
        i += 1 + length;
    }
    return 0;
}

static int open_hidraw(int number)
{
    char path[32];

    snprintf(path, sizeof(path), "/dev/hidraw%d", number);
    return open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
}

/* Print a line only when it differs from the last one. */
static void emit(void)
{
    char line[256];

    if (aether.wired)
        snprintf(line, sizeof(line), "{\"pct\":null,\"state\":\"charging\",\"charging\":true,"
                 "\"id\":\"cosmic-byte-aether\",\"type\":\"mouse\","
                 "\"model\":\"Cosmic Byte Aether\"}");
    else if (aether.config_number >= 0 && aether.pct >= 0)
        snprintf(line, sizeof(line), "{\"pct\":%d,\"state\":\"discharging\",\"charging\":false,"
                 "\"id\":\"cosmic-byte-aether\",\"type\":\"mouse\","
                 "\"model\":\"Cosmic Byte Aether\"}", aether.pct);
    else if (aether.config_number >= 0)
        return; /* dongle attached, no reading yet: keep what the shell shows */
    else
        snprintf(line, sizeof(line), "{\"absent\":true}");

    if (strcmp(line, aether.last_line) == 0)
        return;
    strcpy(aether.last_line, line);
    printf("%s\n", line);
    fflush(stdout);
}

static void close_inputs(void)
{
    int i;

    for (i = 0; i < MAX_INPUTS; i++) {
        if (aether.input_fds[i] >= 0)
            close(aether.input_fds[i]);
        aether.input_fds[i] = -1;
    }
}

static void send_request(void)
{
    static const uint8_t request[] = {STATE_REPORT_ID, 0x81, 0x01, 0, 0, 0, 0, 0, 0};

    TRACE("request");
    ioctl(aether.config_fd, HIDIOCSFEATURE(sizeof(request)), request);
    aether.next_resend = monotonic_ms() + RESEND_MS;
}

static void finish_query(int64_t wait_ms)
{
    TRACE("idle for %lld s, holding no device open", (long long)wait_ms / 1000);
    if (aether.config_fd >= 0)
        close(aether.config_fd);
    aether.config_fd = -1;
    aether.phase = IDLE;
    aether.due = monotonic_ms() + wait_ms;
}

static void start_query(void)
{
    close_inputs(); /* stop receiving every mouse movement */
    if (aether.config_fd < 0)
        aether.config_fd = open_hidraw(aether.config_number);
    if (aether.config_fd < 0) {
        finish_query(OPEN_RETRY_MS); /* udev may not have set the ACL yet */
        return;
    }
    aether.phase = QUERYING;
    aether.query_deadline = monotonic_ms() + QUERY_TIMEOUT_MS;
    send_request();
}

static void wait_for_activity(void)
{
    int opened = 0;
    int i;

    close_inputs();
    for (i = 0; i < aether.input_count; i++) {
        aether.input_fds[i] = open_hidraw(aether.input_numbers[i]);
        opened += aether.input_fds[i] >= 0;
    }
    TRACE("waiting for activity on %d node(s)", opened);
    if (opened)
        aether.phase = WAIT_ACTIVITY;
    else
        start_query(); /* can't see activity: ask now */
}

static void forget_dongle(void)
{
    close_inputs();
    finish_query(0);
    aether.config_number = -1;
    aether.pct = -1;
    aether.settled = 0;
}

static void scan(void)
{
    DIR *directory = opendir("/dev");
    struct dirent *entry;
    int config_number = -1;

    TRACE("scan");
    aether.wired = 0;
    aether.input_count = 0;
    aether.scan_at = -1;
    if (!directory)
        return;

    while ((entry = readdir(directory))) {
        unsigned int vendor, product;
        int number = hidraw_number(entry->d_name);

        if (number < 0 || !read_ids(number, &vendor, &product)
            || vendor != AETHER_VENDOR_ID)
            continue;
        if (product == AETHER_WIRED_ID)
            aether.wired = 1;
        else if (product != AETHER_DONGLE_ID)
            continue;
        else if (has_usage_page(number, CONFIG_USAGE_PAGE))
            config_number = number;
        else if (aether.input_count < MAX_INPUTS)
            aether.input_numbers[aether.input_count++] = number;
    }
    closedir(directory);

    /* The cable wins: the mouse is charging and never needs asking. */
    if (aether.wired)
        config_number = -1;

    if (config_number != aether.config_number) {
        forget_dongle();
        aether.config_number = config_number;
        if (config_number >= 0)
            wait_for_activity(); /* new dongle: read as soon as the mouse is awake */
    } else if (aether.phase == WAIT_ACTIVITY) {
        wait_for_activity(); /* input nodes may have changed */
    }
    emit();
}

/* Drain one hidraw fd; returns the last battery % seen, or -1. */
static int drain(int fd, int *gone)
{
    uint8_t report[64];
    ssize_t length;
    int pct = -1;

    while ((length = read(fd, report, sizeof(report))) > 0) {
        /* Command echoes share report ID 9; only byte <= 100 is state. */
        if (length >= 2 && report[0] == STATE_REPORT_ID && report[1] <= 100)
            pct = report[1];
    }
    *gone = length == 0 || (length < 0 && errno != EAGAIN && errno != EINTR);
    return pct;
}

static int inotify_has_hidraw(int fd)
{
    char buffer[4096] __attribute__((aligned(__alignof__(struct inotify_event))));
    ssize_t length;
    int found = 0;

    while ((length = read(fd, buffer, sizeof(buffer))) > 0) {
        char *cursor = buffer;

        while (cursor < buffer + length) {
            struct inotify_event *event = (struct inotify_event *)cursor;

            if (event->len && strncmp(event->name, "hidraw", 6) == 0)
                found = 1;
            cursor += sizeof(*event) + event->len;
        }
    }
    return found;
}

int main(void)
{
    int notify_fd;
    int i;

    /* Exit with the shell even if it dies without closing our stdout. */
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() == 1)
        return 0;

    notify_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (notify_fd < 0 || inotify_add_watch(notify_fd, "/dev",
                                           IN_CREATE | IN_DELETE | IN_ATTRIB) < 0)
        return 2;

    aether.config_number = -1;
    aether.config_fd = -1;
    aether.pct = -1;
    for (i = 0; i < MAX_INPUTS; i++)
        aether.input_fds[i] = -1;
    scan();

    for (;;) {
        struct pollfd polls[2 + MAX_INPUTS];
        int count = 0;
        int config_index = -1;
        int input_base;
        int64_t now = monotonic_ms();
        int64_t wake = -1;
        int timeout;
        int gone = 0;
        int pct;

        polls[count++] = (struct pollfd){.fd = notify_fd, .events = POLLIN};
        if (aether.config_fd >= 0) {
            config_index = count;
            polls[count++] = (struct pollfd){.fd = aether.config_fd, .events = POLLIN};
        }
        input_base = count;
        if (aether.phase == WAIT_ACTIVITY)
            for (i = 0; i < MAX_INPUTS; i++)
                if (aether.input_fds[i] >= 0)
                    polls[count++] = (struct pollfd){.fd = aether.input_fds[i],
                                                     .events = POLLIN};

        if (aether.scan_at >= 0)
            wake = aether.scan_at;
        if (aether.config_number >= 0 && aether.phase == IDLE
            && (wake < 0 || aether.due < wake))
            wake = aether.due;
        if (aether.phase == QUERYING) {
            int64_t query_wake = aether.next_resend < aether.query_deadline
                ? aether.next_resend : aether.query_deadline;
            if (wake < 0 || query_wake < wake)
                wake = query_wake;
        }
        timeout = wake < 0 ? -1 : (wake > now ? (int)(wake - now) : 0);

        if (poll(polls, count, timeout) < 0) {
            if (errno == EINTR)
                continue;
            return 2;
        }
        now = monotonic_ms();

        if ((polls[0].revents & POLLIN) && inotify_has_hidraw(notify_fd)
            && aether.scan_at < 0)
            aether.scan_at = now + SCAN_SETTLE_MS;

        if (config_index >= 0 && polls[config_index].revents) {
            pct = drain(aether.config_fd, &gone);
            if (gone || (polls[config_index].revents & (POLLERR | POLLHUP | POLLNVAL))) {
                forget_dongle();
                aether.scan_at = now + SCAN_SETTLE_MS;
            } else if (pct >= 0) {
                /* The first report after the link comes up can be a placeholder
                 * (seen: 50 on a full battery), so check again soon. */
                aether.pct = pct;
                finish_query(aether.settled ? READ_INTERVAL_MS : RETRY_MS);
                aether.settled = 1;
                emit();
            }
        }

        if (aether.phase == WAIT_ACTIVITY) {
            int active = 0;

            for (i = input_base; i < count; i++) {
                int j;

                if (polls[i].revents & POLLIN) {
                    drain(polls[i].fd, &gone);
                    active = 1;
                }
                /* Unplugged: close it now, or poll() spins until the rescan. */
                if (gone || (polls[i].revents & (POLLERR | POLLHUP | POLLNVAL)))
                    for (j = 0; j < MAX_INPUTS; j++)
                        if (aether.input_fds[j] == polls[i].fd) {
                            close(polls[i].fd);
                            aether.input_fds[j] = -1;
                        }
                gone = 0;
            }
            if (active)
                start_query();
        } else if (aether.phase == QUERYING) {
            if (now >= aether.query_deadline) {
                finish_query(RETRY_MS);
            } else if (now >= aether.next_resend) {
                send_request();
            }
        } else if (aether.phase == IDLE && aether.config_number >= 0 && now >= aether.due) {
            wait_for_activity();
        }

        if (aether.scan_at >= 0 && now >= aether.scan_at)
            scan();
    }
}
