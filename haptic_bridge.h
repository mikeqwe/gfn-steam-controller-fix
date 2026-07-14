#ifndef GFN_STEAM_HID_HAPTIC_BRIDGE_H
#define GFN_STEAM_HID_HAPTIC_BRIDGE_H

#include <stdint.h>

#define GFN_TRITON_RUMBLE_REPORT_SIZE 10

uint16_t gfn_map_rumble_level(int level);
void gfn_build_triton_rumble_report(
    uint16_t low_frequency,
    uint16_t high_frequency,
    uint8_t report[GFN_TRITON_RUMBLE_REPORT_SIZE]);
int HIDSetRumbleTypeSine(
    int controller_id,
    int left,
    int right,
    int left_trigger,
    int right_trigger,
    int duration_ms);

#endif
