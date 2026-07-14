CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O2
BUILD_DIR := .build
PATCHER := $(BUILD_DIR)/patch_gc_backend

.PHONY: all check test syntax build-app verify-app clean

all: check

$(PATCHER): patch_gc_backend.c
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@

syntax:
	zsh -n build.zsh verify.zsh tests/test_patcher.zsh

test: $(PATCHER)
	zsh tests/test_patcher.zsh $(PATCHER)

check: syntax test

build-app:
	./build.zsh

verify-app:
	./verify.zsh

clean:
	rm -rf $(BUILD_DIR)
