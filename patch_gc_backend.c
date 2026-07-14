#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum mode {
    MODE_PATCH,
    MODE_CHECK,
};

static void print_bytes(const unsigned char *bytes, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        fprintf(stderr, "%s%02x", i ? " " : "", bytes[i]);
    }
    fputc('\n', stderr);
}

int main(int argc, char **argv) {
    static const unsigned char expected[8] = {
        0xff, 0xc3, 0x00, 0xd1, 0xf4, 0x4f, 0x01, 0xa9
    };
    static const unsigned char replacement[8] = {
        0x00, 0x00, 0x80, 0x52, 0xc0, 0x03, 0x5f, 0xd6
    }; /* mov w0, #0; ret */

    if (argc != 4 ||
        (strcmp(argv[1], "--patch") != 0 &&
         strcmp(argv[1], "--check") != 0)) {
        fprintf(stderr,
                "usage: %s <--patch|--check> "
                "<thin-arm64-libGeronimo> <file-offset>\n",
                argv[0]);
        return 2;
    }

    enum mode mode = strcmp(argv[1], "--check") == 0 ? MODE_CHECK
                                                       : MODE_PATCH;

    char *end = NULL;
    errno = 0;
    uint64_t offset = strtoull(argv[3], &end, 0);
    if (errno || !end || *end != '\0') {
        fprintf(stderr, "invalid offset: %s\n", argv[3]);
        return 2;
    }

    FILE *file = fopen(argv[2], mode == MODE_CHECK ? "rb" : "r+b");
    if (!file) {
        fprintf(stderr, "open: %s\n", strerror(errno));
        return 1;
    }
    if (fseeko(file, (off_t)offset, SEEK_SET) != 0) {
        fprintf(stderr, "seek: %s\n", strerror(errno));
        fclose(file);
        return 1;
    }

    unsigned char actual[8];
    if (fread(actual, 1, sizeof(actual), file) != sizeof(actual)) {
        fprintf(stderr, "could not read 8 bytes at 0x%llx\n",
                (unsigned long long)offset);
        fclose(file);
        return 1;
    }
    if (memcmp(actual, replacement, sizeof(actual)) == 0) {
        printf("GCDeviceInit already patched at 0x%llx\n",
               (unsigned long long)offset);
        fclose(file);
        return 0;
    }
    if (mode == MODE_CHECK &&
        memcmp(actual, expected, sizeof(actual)) == 0) {
        fprintf(stderr, "GCDeviceInit is not patched at 0x%llx\n",
                (unsigned long long)offset);
        fclose(file);
        return 3;
    }
    if (memcmp(actual, expected, sizeof(actual)) != 0) {
        fprintf(stderr,
                "refusing patch: unexpected instructions at 0x%llx\n",
                (unsigned long long)offset);
        fprintf(stderr, "actual bytes: ");
        print_bytes(actual, sizeof(actual));
        fclose(file);
        return 1;
    }
    if (fseeko(file, (off_t)offset, SEEK_SET) != 0 ||
        fwrite(replacement, 1, sizeof(replacement), file) !=
            sizeof(replacement)) {
        fprintf(stderr, "write: %s\n", strerror(errno));
        fclose(file);
        return 1;
    }
    if (fclose(file) != 0) {
        fprintf(stderr, "close: %s\n", strerror(errno));
        return 1;
    }

    printf("patched GCDeviceInit at 0x%llx: return false\n",
           (unsigned long long)offset);
    return 0;
}
