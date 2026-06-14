#include "test_utils.h"
#include "hello.h"
#include <string.h>

void test_hello_compiles(void) {
    TEST("hello 函数可调用");
    hello();
    CHECK(1);

}

int main(void) {
    printf("\n=== Hello 单元测试 ===\n\n");

    test_hello_compiles();

    TEST_SUMMARY();
    return _tests_failed > 0 ? 1 : 0;
}
