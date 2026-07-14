#include "../haptic_bridge.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

int main(void) {
    assert(gfn_map_rumble_level(-1) == 0);
    assert(gfn_map_rumble_level(0) == 0);
    assert(gfn_map_rumble_level(15) == 32768);
    assert(gfn_map_rumble_level(30) == UINT16_MAX);
    assert(gfn_map_rumble_level(100) == UINT16_MAX);

    uint8_t actual[GFN_TRITON_RUMBLE_REPORT_SIZE];
    const uint8_t expected[GFN_TRITON_RUMBLE_REPORT_SIZE] = {
        0x80, 0x00, 0x00, 0x00, 0x34,
        0x12, 0x00, 0xcd, 0xab, 0x00,
    };
    gfn_build_triton_rumble_report(0x1234, 0xabcd, actual);
    assert(memcmp(actual, expected, sizeof(expected)) == 0);
    return 0;
}
