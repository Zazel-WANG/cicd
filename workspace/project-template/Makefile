# ============================================================
# 项目模板 Makefile
# ============================================================
# 换项目名只需改下面一行:
PROJECT   := hello
# ============================================================

CC        ?= gcc
ARCH      ?= native
VERSION   ?= dev
BUILD_DIR := build
INCLUDE   := include

CFLAGS    += -Wall -Wextra -O2 -I$(INCLUDE)

ifeq ($(ARCH),arm64)
    CC := aarch64-linux-gnu-gcc
    CFLAGS += -march=armv8-a -static
endif

# 自动收集源文件
SRCS      := $(wildcard src/*.c) $(wildcard src/**/*.c)
OBJS      := $(SRCS:%.c=$(BUILD_DIR)/%.o)
TEST_SRCS := $(wildcard tests/test_*.c)
TEST_BINS := $(TEST_SRCS:tests/%.c=$(BUILD_DIR)/%)

# 第一个源文件不含 main → 从 OBJS 中剔除
OBJS      := $(filter-out $(BUILD_DIR)/src/main.o,$(OBJS))

.PHONY: all clean test verify

all: $(BUILD_DIR)/$(PROJECT)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)/src

$(BUILD_DIR)/src/%.o: src/%.c | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

# 版本化二进制: hello-abc1234
$(BUILD_DIR)/$(PROJECT)-$(VERSION): $(BUILD_DIR)/src/main.o $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

# 软链接: hello → hello-abc1234
$(BUILD_DIR)/$(PROJECT): $(BUILD_DIR)/$(PROJECT)-$(VERSION)
	ln -sf $(PROJECT)-$(VERSION) $@

$(BUILD_DIR)/%: tests/%.c $(OBJS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I. -Itests -o $@ $< $(OBJS)

test: $(TEST_BINS)
	@echo "=== 运行单元测试 ==="
	@fail=0; \
	for t in $(TEST_BINS); do \
		echo "--- $$(basename $$t) ---"; \
		if [ "$(ARCH)" = "arm64" ]; then \
			qemu-aarch64 $$t || fail=1; \
		else \
			$$t || fail=1; \
		fi; \
	done; \
	if [ $$fail -ne 0 ]; then \
		echo "=== 测试失败 ==="; exit 1; \
	else \
		echo "=== 测试通过 ==="; \
	fi

verify: $(BUILD_DIR)/$(PROJECT)-$(VERSION)
	@echo "=== Binary Info ==="
	file $(BUILD_DIR)/$(PROJECT)-$(VERSION)

clean:
	rm -rf $(BUILD_DIR)
