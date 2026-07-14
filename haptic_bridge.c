#define _DARWIN_C_SOURCE

#include "haptic_bridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/hid/IOHIDManager.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define STEAM_VENDOR_ID 0x28de
#define STEAM_TRITON_PRODUCT_ID 0x1304
#define GFN_RUMBLE_MAX_LEVEL 30
#define TRITON_RUMBLE_RESEND_MS 40
#define MAX_HID_INTERFACES 16

struct bridge_state {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    bool active;
    bool stop_pending;
    uint16_t low;
    uint16_t high;
    uint64_t deadline_ms;
};

struct bridge_devices {
    IOHIDManagerRef manager;
    IOHIDDeviceRef devices[MAX_HID_INTERFACES];
    size_t count;
};

static struct bridge_state state = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .changed = PTHREAD_COND_INITIALIZER,
};

static uint64_t monotonic_ms(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
        return 0;
    }
    return (uint64_t)value.tv_sec * 1000U + (uint64_t)value.tv_nsec / 1000000U;
}

uint16_t gfn_map_rumble_level(int level) {
    if (level <= 0) {
        return 0;
    }
    if (level >= GFN_RUMBLE_MAX_LEVEL) {
        return UINT16_MAX;
    }
    return (uint16_t)(((uint32_t)level * UINT16_MAX +
                       GFN_RUMBLE_MAX_LEVEL / 2) /
                      GFN_RUMBLE_MAX_LEVEL);
}

void gfn_build_triton_rumble_report(
    uint16_t low_frequency,
    uint16_t high_frequency,
    uint8_t report[GFN_TRITON_RUMBLE_REPORT_SIZE]) {
    static const uint8_t empty[GFN_TRITON_RUMBLE_REPORT_SIZE] = {0};
    memcpy(report, empty, sizeof(empty));
    report[0] = 0x80;
    report[4] = (uint8_t)(low_frequency & 0xffU);
    report[5] = (uint8_t)(low_frequency >> 8U);
    report[7] = (uint8_t)(high_frequency & 0xffU);
    report[8] = (uint8_t)(high_frequency >> 8U);
}

static int number_property(IOHIDDeviceRef device, CFStringRef key) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    int result = 0;
    if (value != NULL && CFGetTypeID(value) == CFNumberGetTypeID()) {
        (void)CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &result);
    }
    return result;
}

static void close_devices(struct bridge_devices *devices) {
    for (size_t i = 0; i < devices->count; ++i) {
        IOHIDDeviceClose(devices->devices[i], kIOHIDOptionsTypeNone);
        CFRelease(devices->devices[i]);
    }
    devices->count = 0;
    if (devices->manager != NULL) {
        IOHIDManagerClose(devices->manager, kIOHIDOptionsTypeNone);
        CFRelease(devices->manager);
        devices->manager = NULL;
    }
}

static bool open_devices(struct bridge_devices *devices) {
    close_devices(devices);

    devices->manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (devices->manager == NULL) {
        return false;
    }

    int vendor = STEAM_VENDOR_ID;
    int product = STEAM_TRITON_PRODUCT_ID;
    CFNumberRef vendor_number = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberIntType, &vendor);
    CFNumberRef product_number = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberIntType, &product);
    if (vendor_number == NULL || product_number == NULL) {
        if (vendor_number != NULL) {
            CFRelease(vendor_number);
        }
        if (product_number != NULL) {
            CFRelease(product_number);
        }
        close_devices(devices);
        return false;
    }

    const void *keys[] = {
        CFSTR(kIOHIDVendorIDKey),
        CFSTR(kIOHIDProductIDKey),
    };
    const void *values[] = {vendor_number, product_number};
    CFDictionaryRef matching = CFDictionaryCreate(
        kCFAllocatorDefault, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(vendor_number);
    CFRelease(product_number);
    if (matching == NULL) {
        close_devices(devices);
        return false;
    }

    IOHIDManagerSetDeviceMatching(devices->manager, matching);
    CFRelease(matching);
    if (IOHIDManagerOpen(devices->manager, kIOHIDOptionsTypeNone) !=
        kIOReturnSuccess) {
        close_devices(devices);
        return false;
    }

    CFSetRef set = IOHIDManagerCopyDevices(devices->manager);
    if (set == NULL) {
        close_devices(devices);
        return false;
    }
    CFIndex count = CFSetGetCount(set);
    const void **items = calloc((size_t)count, sizeof(*items));
    if (items == NULL) {
        CFRelease(set);
        close_devices(devices);
        return false;
    }
    CFSetGetValues(set, items);
    for (CFIndex i = 0; i < count && devices->count < MAX_HID_INTERFACES; ++i) {
        IOHIDDeviceRef device = (IOHIDDeviceRef)items[i];
        if (number_property(device, CFSTR(kIOHIDMaxOutputReportSizeKey)) <
            GFN_TRITON_RUMBLE_REPORT_SIZE) {
            continue;
        }
        if (IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
            continue;
        }
        CFRetain(device);
        devices->devices[devices->count++] = device;
    }
    free(items);
    CFRelease(set);
    return devices->count > 0;
}

static bool send_report(
    struct bridge_devices *devices,
    uint16_t low,
    uint16_t high) {
    if (devices->count == 0 && !open_devices(devices)) {
        return false;
    }

    uint8_t report[GFN_TRITON_RUMBLE_REPORT_SIZE];
    gfn_build_triton_rumble_report(low, high, report);
    bool sent = false;
    for (size_t i = 0; i < devices->count; ++i) {
        IOReturn result = IOHIDDeviceSetReport(
            devices->devices[i], kIOHIDReportTypeOutput, report[0], report,
            sizeof(report));
        if (result == kIOReturnSuccess) {
            sent = true;
        }
    }
    if (!sent) {
        close_devices(devices);
    }
    return sent;
}

static void *rumble_worker(void *unused) {
    (void)unused;
    struct bridge_devices devices = {0};

    for (;;) {
        pthread_mutex_lock(&state.lock);
        while (!state.active && !state.stop_pending) {
            pthread_cond_wait(&state.changed, &state.lock);
        }
        bool stop = state.stop_pending;
        uint16_t low = state.low;
        uint16_t high = state.high;
        uint64_t deadline = state.deadline_ms;
        state.stop_pending = false;
        pthread_mutex_unlock(&state.lock);

        if (stop) {
            (void)send_report(&devices, 0, 0);
            continue;
        }

        (void)send_report(&devices, low, high);
        struct timespec pause = {
            .tv_sec = 0,
            .tv_nsec = TRITON_RUMBLE_RESEND_MS * 1000000L,
        };
        nanosleep(&pause, NULL);

        pthread_mutex_lock(&state.lock);
        if (state.active && monotonic_ms() >= deadline &&
            state.deadline_ms == deadline) {
            state.active = false;
            state.stop_pending = true;
            pthread_cond_signal(&state.changed);
        }
        pthread_mutex_unlock(&state.lock);
    }
    return NULL;
}

__attribute__((visibility("default"))) int HIDSetRumbleTypeSine(
    int controller_id,
    int left,
    int right,
    int left_trigger,
    int right_trigger,
    int duration_ms) {
    (void)left_trigger;
    (void)right_trigger;
    if (controller_id != 0) {
        return 0;
    }

    uint16_t low = gfn_map_rumble_level(left);
    uint16_t high = gfn_map_rumble_level(right);
    pthread_mutex_lock(&state.lock);
    state.low = low;
    state.high = high;
    if (low == 0 && high == 0) {
        state.active = false;
        state.stop_pending = true;
    } else {
        if (duration_ms <= 0) {
            duration_ms = 1000;
        } else if (duration_ms > 60000) {
            duration_ms = 60000;
        }
        state.active = true;
        state.stop_pending = false;
        state.deadline_ms = monotonic_ms() + (uint64_t)duration_ms;
    }
    pthread_cond_signal(&state.changed);
    pthread_mutex_unlock(&state.lock);
    return 1;
}

static bool is_main_geforce_now_process(void) {
    char path[PATH_MAX];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) {
        return false;
    }
    const char *name = strrchr(path, '/');
    name = name == NULL ? path : name + 1;
    return strcmp(name, "GeForceNOW") == 0;
}

__attribute__((constructor)) static void install_haptic_bridge(void) {
    if (!is_main_geforce_now_process()) {
        return;
    }

    pthread_t worker;
    if (pthread_create(&worker, NULL, rumble_worker, NULL) != 0) {
        fputs("GFN Steam HID haptic worker could not start\n", stderr);
        return;
    }
    pthread_detach(worker);
}
