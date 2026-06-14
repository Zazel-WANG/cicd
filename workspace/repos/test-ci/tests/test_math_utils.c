#include <stdio.h>
#include <stdlib.h>
#include "../src/math_utils.h"

/* 简易测试框架——不依赖任何外部库 */
static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) do { \
    tests_run++; \
    printf("  [TEST] %s ... ", name); \
} while(0)

#define CHECK(cond) do { \
    if (cond) { \
        printf("PASS\n"); \
        tests_passed++; \
    } else { \
        printf("FAIL (%s:%d)\n", __FILE__, __LINE__); \
        tests_failed++; \
    } \
} while(0)

/* ===== 测试用例 ===== */

void test_add() {
    TEST("add 正常情况");
    CHECK(add(2, 3) == 5);

    TEST("add 负数");
    CHECK(add(-1, 1) == 0);

    TEST("add 零值");
    CHECK(add(0, 0) == 0);

    TEST("add 大数");
    CHECK(add(1000000, 2000000) == 3000000);
}

void test_multiply() {
    TEST("multiply 正常情况");
    CHECK(multiply(3, 4) == 12);

    TEST("multiply 乘零");
    CHECK(multiply(100, 0) == 0);

    TEST("multiply 负数×负数");
    CHECK(multiply(-3, -5) == 15);
}

void test_divide() {
    TEST("divide 正常除法");
    CHECK(divide(10, 2) == 5);

    TEST("divide 除数为 0");
    CHECK(divide(10, 0) == 0);   // 期望返回 0

    TEST("divide 整数截断");
    CHECK(divide(7, 2) == 3);    // 整数除法，截断
}

void test_factorial() {
    TEST("factorial n=0");
    CHECK(factorial(0) == 1);

    TEST("factorial n=1");
    CHECK(factorial(1) == 1);

    TEST("factorial n=5");
    CHECK(factorial(5) == 120);

    TEST("factorial 负数输入");
    CHECK(factorial(-3) == -1);  // 错误输入返回 -1
}

int main(void) {
    printf("\n=== Math Utils 单元测试 ===\n\n");

    test_add();
    test_multiply();
    test_divide();
    test_factorial();

    printf("\n===========================\n");
    printf("  总计: %d  通过: %d  失败: %d\n",
           tests_run, tests_passed, tests_failed);
    printf("===========================\n");

    /* 有失败 → 返回非 0（Jenkins 通过返回码判定成功/失败） */
    return tests_failed > 0 ? 1 : 0;
}
