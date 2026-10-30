# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Gamunu Balagalla

# Plain make build of the HPLIP hpcups filter for macOS.
# Usage: make            (builds build/hpcups)
#        make ARCHS="arm64 x86_64"   (universal, needs a universal libjpeg.a)

CC      ?= cc
CXX     ?= c++
ARCHS   ?= arm64
ARCHFLAGS := $(foreach a,$(ARCHS),-arch $(a))
MINVER  ?= 26.0

# Static libjpeg so the filter has no runtime dependency outside the system.
JPEG_PREFIX ?= $(shell pkg-config --variable=prefix libjpeg 2>/dev/null || echo /opt/homebrew)
JPEG_INC    ?= $(JPEG_PREFIX)/include
JPEG_LIB    ?= $(JPEG_PREFIX)/lib/libjpeg.a

DEFS    := -DDISABLE_IMAGEPROCESSOR -DAPDK_LITTLE_ENDIAN -D_GNU_SOURCE -DCONFDIR='"/etc/hp"'
COMMON  := $(ARCHFLAGS) -mmacosx-version-min=$(MINVER) -O2 -g0 -w \
           -Isrc/hpcups -Isrc/common -Isrc/compat -Isrc/jbigkit -I$(JPEG_INC) $(DEFS)
CFLAGS  := $(COMMON)
CXXFLAGS := $(COMMON) -std=gnu++14
LDLIBS  := $(JPEG_LIB) -lcups -lz

CPP_SRCS := $(wildcard src/hpcups/*.cpp)
# jccolor.c holds HP's patched colour converter and needs libjpeg 6b private
# headers. src/compat/hp_csc.c redoes its table math for the JetReady path.
C_SRCS   := $(filter-out src/hpcups/jccolor.c,$(wildcard src/hpcups/*.c)) src/common/hplip_utils.c src/compat/hp_csc.c \
            src/compat/hp_jbig.c $(wildcard src/jbigkit/*.c)
OBJS     := $(patsubst src/%.cpp,build/obj/%.o,$(CPP_SRCS)) \
            $(patsubst src/%.c,build/obj/%.o,$(C_SRCS))

all: build/hpcups

build/hpcups: $(OBJS)
	$(CXX) $(ARCHFLAGS) -mmacosx-version-min=$(MINVER) -o $@ $(OBJS) $(LDLIBS)

build/obj/%.o: src/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $< -o $@

build/obj/%.o: src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

app:
	scripts/build-app.sh

# One installer with the driver and the app. Version: see scripts/version.sh.
pkg: build/hpcups
	scripts/build-pkg.sh

build/csc-check: tests/csc-check.c src/compat/hp_csc.c src/compat/hp_csc.h
	@mkdir -p build
	$(CC) $(CFLAGS) -o $@ tests/csc-check.c src/compat/hp_csc.c

test: build/hpcups build/csc-check
	build/csc-check
	scripts/test-local.sh

clean:
	rm -rf build

.PHONY: all app pkg test clean
