/* 简易嵌入式测试框架 —— 零外部依赖
 *
 * 用法:
 *   #include "test_utils.h"
 *   TEST("描述") CHECK(condition)
 *
 * main() 返回失败数，Jenkins 通过返回码判 pass/fail
 */

#ifndef TEST_UTILS_H
#define TEST_UTILS_H

#include <stdio.h>

static int _tests_run = 0;
static int _tests_passed = 0;
static int _tests_failed = 0;

#define TEST(name) do { \
    _tests_run++; \
    printf("  [TEST] %s ... ", name); \
} while(0)

#define CHECK(cond) do { \
    if (cond) { \
        printf("PASS\n"); \
        _tests_passed++; \
    } else { \
        printf("FAIL (%s:%d)\n", __FILE__, __LINE__); \
        _tests_failed++; \
    } \
} while(0)

#define TEST_SUMMARY() do { \
    printf("\n===========================\n"); \
    printf("  总计: %d  通过: %d  失败: %d\n", \
           _tests_run, _tests_passed, _tests_failed); \
    printf("===========================\n"); \
} while(0)

#endif
