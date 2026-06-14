#include <stdio.h>
#include "src/math_utils.h"

int main(void) {
    printf("Hello from LubanCat RK3588! ARM64 CI/CD works!\n");

    /* 调用 math_utils，验证库链接正常 */
    int test_result = factorial(5);
    printf("factorial(5) = %d (expected: 120)\n", test_result);

    if (test_result == 120) {
        printf("Math check PASS!\n");
        return 0;
    } else {
        printf("Math check FAIL!\n");
        return 1;
    }
}
