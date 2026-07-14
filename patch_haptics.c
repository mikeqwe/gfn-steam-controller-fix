#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FUNCTION_SIZE 64
#define STUB_INSTRUCTION_COUNT 16

enum mode {
    MODE_PATCH,
    MODE_CHECK,
};

static const uint8_t original_is_rumble_supported[FUNCTION_SIZE] = {
    0xfd, 0x7b, 0xbf, 0xa9, 0xfd, 0x03, 0x00, 0x91,
    0xc8, 0x76, 0x00, 0xb0, 0x08, 0x01, 0x31, 0x91,
    0x09, 0x24, 0x80, 0x52, 0x08, 0x20, 0x29, 0x9b,
    0x08, 0xc1, 0x40, 0x39, 0xc8, 0x00, 0x00, 0x34,
    0xba, 0x1c, 0x00, 0x94, 0x1f, 0x00, 0x00, 0x71,
    0xe0, 0x07, 0x9f, 0x1a, 0xfd, 0x7b, 0xc1, 0xa8,
    0xc0, 0x03, 0x5f, 0xd6, 0x00, 0x00, 0x80, 0x52,
    0xfd, 0x7b, 0xc1, 0xa8, 0xc0, 0x03, 0x5f, 0xd6,
};

static const uint8_t original_set_rumble_state[FUNCTION_SIZE] = {
    0xfd, 0x7b, 0xbf, 0xa9, 0xfd, 0x03, 0x00, 0x91,
    0xc8, 0x76, 0x00, 0xb0, 0x08, 0x01, 0x31, 0x91,
    0x09, 0x24, 0x80, 0x52, 0x08, 0x20, 0x29, 0x9b,
    0x08, 0xc1, 0x40, 0x39, 0xc8, 0x00, 0x00, 0x34,
    0x70, 0x1c, 0x00, 0x94, 0x1f, 0x00, 0x00, 0x71,
    0xe0, 0x07, 0x9f, 0x1a, 0xfd, 0x7b, 0xc1, 0xa8,
    0xc0, 0x03, 0x5f, 0xd6, 0x00, 0x00, 0x80, 0x52,
    0xfd, 0x7b, 0xc1, 0xa8, 0xc0, 0x03, 0x5f, 0xd6,
};

static bool parse_u64(const char *value, uint64_t *result) {
    char *end = NULL;
    errno = 0;
    unsigned long long parsed = strtoull(value, &end, 0);
    if (errno != 0 || end == NULL || *end != '\0') {
        return false;
    }
    *result = (uint64_t)parsed;
    return true;
}

static void write_u32_le(uint8_t *target, uint32_t value) {
    target[0] = (uint8_t)value;
    target[1] = (uint8_t)(value >> 8U);
    target[2] = (uint8_t)(value >> 16U);
    target[3] = (uint8_t)(value >> 24U);
}

static bool encode_adrp_x1(
    uint64_t instruction_address,
    uint64_t target_address,
    uint32_t *instruction) {
    int64_t source_page = (int64_t)(instruction_address & ~0xfffULL);
    int64_t target_page = (int64_t)(target_address & ~0xfffULL);
    int64_t page_delta = (target_page - source_page) >> 12;
    if (page_delta < -(1LL << 20) || page_delta >= (1LL << 20)) {
        return false;
    }
    uint32_t immediate = (uint32_t)page_delta & 0x1fffffU;
    *instruction = 0x90000001U |
                   ((immediate & 3U) << 29U) |
                   ((immediate >> 2U) << 5U);
    return true;
}

static bool encode_bl(
    uint64_t instruction_address,
    uint64_t target_address,
    uint32_t *instruction) {
    int64_t delta = (int64_t)target_address - (int64_t)instruction_address;
    if ((delta & 3) != 0 || delta < -(1LL << 27) || delta >= (1LL << 27)) {
        return false;
    }
    uint32_t immediate = (uint32_t)(delta >> 2) & 0x03ffffffU;
    *instruction = 0x94000000U | immediate;
    return true;
}

static bool build_rumble_stub(
    uint64_t function_address,
    uint64_t dlsym_stub_address,
    uint64_t bridge_name_address,
    uint8_t output[FUNCTION_SIZE]) {
    uint32_t instructions[STUB_INSTRUCTION_COUNT] = {
        0xa9bc7bfdU, /* stp x29, x30, [sp, #-0x40]! */
        0x910003fdU, /* mov x29, sp */
        0xa90107e0U, /* stp x0, x1, [sp, #0x10] */
        0xa9020fe2U, /* stp x2, x3, [sp, #0x20] */
        0xa90317e4U, /* stp x4, x5, [sp, #0x30] */
        0x92800020U, /* mov x0, #-2 (RTLD_DEFAULT) */
        0,
        0x91000021U | ((uint32_t)(bridge_name_address & 0xfffU) << 10U),
        0,
        0xaa0003e8U, /* mov x8, x0 */
        0xa94107e0U, /* ldp x0, x1, [sp, #0x10] */
        0xa9420fe2U, /* ldp x2, x3, [sp, #0x20] */
        0xa94317e4U, /* ldp x4, x5, [sp, #0x30] */
        0xd63f0100U, /* blr x8 */
        0xa8c47bfdU, /* ldp x29, x30, [sp], #0x40 */
        0xd65f03c0U, /* ret */
    };
    if (!encode_adrp_x1(function_address + 0x18,
                        bridge_name_address, &instructions[6]) ||
        !encode_bl(function_address + 0x20,
                   dlsym_stub_address, &instructions[8])) {
        return false;
    }
    for (size_t i = 0; i < STUB_INSTRUCTION_COUNT; ++i) {
        write_u32_le(output + i * sizeof(uint32_t), instructions[i]);
    }
    return true;
}

static bool read_at(FILE *file, uint64_t offset, uint8_t output[FUNCTION_SIZE]) {
    return fseeko(file, (off_t)offset, SEEK_SET) == 0 &&
           fread(output, 1, FUNCTION_SIZE, file) == FUNCTION_SIZE;
}

static bool write_at(
    FILE *file,
    uint64_t offset,
    const uint8_t input[FUNCTION_SIZE]) {
    return fseeko(file, (off_t)offset, SEEK_SET) == 0 &&
           fwrite(input, 1, FUNCTION_SIZE, file) == FUNCTION_SIZE;
}

int main(int argc, char **argv) {
    if (argc != 8 ||
        (strcmp(argv[1], "--patch") != 0 &&
         strcmp(argv[1], "--check") != 0)) {
        fprintf(stderr,
                "usage: %s <--patch|--check> <thin-arm64-libGeronimo> "
                "<is-rumble-file-offset> <set-rumble-file-offset> "
                "<set-rumble-vm-address> <dlsym-stub-vm-address> "
                "<bridge-name-vm-address>\n",
                argv[0]);
        return 2;
    }

    enum mode mode = strcmp(argv[1], "--check") == 0 ? MODE_CHECK
                                                       : MODE_PATCH;
    uint64_t is_offset;
    uint64_t set_offset;
    uint64_t set_address;
    uint64_t dlsym_address;
    uint64_t name_address;
    if (!parse_u64(argv[3], &is_offset) ||
        !parse_u64(argv[4], &set_offset) ||
        !parse_u64(argv[5], &set_address) ||
        !parse_u64(argv[6], &dlsym_address) ||
        !parse_u64(argv[7], &name_address)) {
        fputs("invalid numeric argument\n", stderr);
        return 2;
    }

    uint8_t patched_is[FUNCTION_SIZE];
    memcpy(patched_is, original_is_rumble_supported, sizeof(patched_is));
    static const uint8_t return_true[] = {
        0x20, 0x00, 0x80, 0x52, /* mov w0, #1 */
        0xc0, 0x03, 0x5f, 0xd6, /* ret */
    };
    memcpy(patched_is, return_true, sizeof(return_true));

    uint8_t patched_set[FUNCTION_SIZE];
    if (!build_rumble_stub(set_address, dlsym_address,
                           name_address, patched_set)) {
        fputs("could not encode haptic bridge stub\n", stderr);
        return 1;
    }

    FILE *file = fopen(argv[2], mode == MODE_CHECK ? "rb" : "r+b");
    if (file == NULL) {
        fprintf(stderr, "open: %s\n", strerror(errno));
        return 1;
    }
    uint8_t actual_is[FUNCTION_SIZE];
    uint8_t actual_set[FUNCTION_SIZE];
    if (!read_at(file, is_offset, actual_is) ||
        !read_at(file, set_offset, actual_set)) {
        fputs("could not read haptic functions\n", stderr);
        fclose(file);
        return 1;
    }

    bool is_patched = memcmp(actual_is, patched_is, FUNCTION_SIZE) == 0;
    bool set_patched = memcmp(actual_set, patched_set, FUNCTION_SIZE) == 0;
    if (is_patched && set_patched) {
        puts("haptic capability and rumble bridge already patched");
        fclose(file);
        return 0;
    }
    if (mode == MODE_CHECK &&
        memcmp(actual_is, original_is_rumble_supported, FUNCTION_SIZE) == 0 &&
        memcmp(actual_set, original_set_rumble_state, FUNCTION_SIZE) == 0) {
        fputs("haptic bridge is not patched\n", stderr);
        fclose(file);
        return 3;
    }
    if (memcmp(actual_is, original_is_rumble_supported, FUNCTION_SIZE) != 0 ||
        memcmp(actual_set, original_set_rumble_state, FUNCTION_SIZE) != 0) {
        fputs("refusing haptic patch: unexpected function bytes\n", stderr);
        fclose(file);
        return 1;
    }
    if (!write_at(file, is_offset, patched_is) ||
        !write_at(file, set_offset, patched_set) ||
        fclose(file) != 0) {
        fprintf(stderr, "write: %s\n", strerror(errno));
        return 1;
    }
    puts("patched haptic capability and rumble bridge");
    return 0;
}
