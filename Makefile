CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O2
BUILD_DIR := .build
PATCHER := $(BUILD_DIR)/patch_gc_backend
HAPTIC_PATCHER := $(BUILD_DIR)/patch_haptics
HAPTIC_BRIDGE := $(BUILD_DIR)/libGFNSteamHIDHaptics.dylib
HAPTIC_TEST := $(BUILD_DIR)/test_haptic_bridge

.PHONY: all check test syntax install-app uninstall-app build-app verify-app clean

all: check

$(PATCHER): patch_gc_backend.c
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@

$(HAPTIC_PATCHER): patch_haptics.c
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@

$(HAPTIC_BRIDGE): haptic_bridge.c haptic_bridge.h
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -arch arm64 -dynamiclib haptic_bridge.c \
		-framework IOKit -framework CoreFoundation -pthread -o $@

$(HAPTIC_TEST): haptic_bridge.c haptic_bridge.h tests/test_haptic_bridge.c
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) haptic_bridge.c tests/test_haptic_bridge.c \
		-framework IOKit -framework CoreFoundation -pthread -o $@

syntax:
	zsh -n build.zsh verify.zsh install.zsh uninstall.zsh \
		reset-gfn-container.zsh lib/app-transaction.zsh \
		tests/test_patcher.zsh tests/test_haptic_patcher.zsh \
		tests/test_reset_container.zsh tests/test_installers.zsh \
		tests/test_app_transaction.zsh

test: $(PATCHER) $(HAPTIC_PATCHER) $(HAPTIC_BRIDGE) $(HAPTIC_TEST)
	zsh tests/test_patcher.zsh $(PATCHER)
	zsh tests/test_haptic_patcher.zsh $(HAPTIC_PATCHER)
	$(HAPTIC_TEST)
	zsh tests/test_reset_container.zsh ./reset-gfn-container.zsh
	zsh tests/test_installers.zsh ./install.zsh ./uninstall.zsh
	zsh tests/test_app_transaction.zsh ./lib/app-transaction.zsh

check: syntax test

install-app:
	./install.zsh

uninstall-app:
	./uninstall.zsh

build-app:
	./build.zsh

verify-app:
	./verify.zsh

clean:
	rm -rf $(BUILD_DIR)
