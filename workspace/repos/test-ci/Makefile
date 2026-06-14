# 鲁班猫交叉编译 Makefile
# 用法:
#   make ARCH=arm64          交叉编译 ARM64
#   make test ARCH=arm64     编译 + 运行单元测试
#   make verify ARCH=arm64   验证二进制格式
#   make clean

CC         ?= gcc
ARCH       ?= native
BUILD_DIR  := build
TARGET     := hello
TEST_TARGET := test_math_utils

# 源文件
MAIN_SRC   := hello.c
LIB_SRC    := src/math_utils.c
TEST_SRC   := tests/test_math_utils.c

CFLAGS     += -Wall -Wextra -O2

ifeq ($(ARCH),arm64)
    CC := aarch64-linux-gnu-gcc
    CFLAGS += -march=armv8-a -static
endif

.PHONY: all clean verify test

all: $(BUILD_DIR)/$(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# 库目标文件
$(BUILD_DIR)/math_utils.o: $(LIB_SRC) src/math_utils.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

# 主程序
$(BUILD_DIR)/$(TARGET): $(MAIN_SRC) $(BUILD_DIR)/math_utils.o | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc -o $@ $(MAIN_SRC) $(BUILD_DIR)/math_utils.o

# 测试程序
$(BUILD_DIR)/$(TEST_TARGET): $(TEST_SRC) $(BUILD_DIR)/math_utils.o | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc -o $@ $(TEST_SRC) $(BUILD_DIR)/math_utils.o

# 编译 + 运行测试
test: $(BUILD_DIR)/$(TEST_TARGET)
	@echo "=== 运行单元测试 ==="
ifeq ($(ARCH),arm64)
	qemu-aarch64 $(BUILD_DIR)/$(TEST_TARGET)
else
	$(BUILD_DIR)/$(TEST_TARGET)
endif
	@echo "=== 单元测试通过 ==="

verify: $(BUILD_DIR)/$(TARGET)
	@echo "=== Binary Info ==="
	file $(BUILD_DIR)/$(TARGET)
	@echo "=== Expected: ELF 64-bit LSB executable, ARM aarch64 ==="

clean:
	rm -rf $(BUILD_DIR)
