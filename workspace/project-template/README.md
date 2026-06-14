# 鲁班猫项目模板

## 快速开始

```bash
# 1. 复制模板
cp -r project-template my-project
cd my-project

# 2. 改项目名
#     编辑 Makefile 第一行: PROJECT := 你的项目名

# 3. 写代码
#     src/      放源码
#     include/  放头文件
#     tests/    放测试

# 4. 本地编译测试（需要交叉编译器）
make clean && make test

# 5. 推到 Gitea → Jenkins 自动构建
git init && git remote add origin ssh://git@10.0.0.1:2222/wangzhongqi/my-project.git
git add -A && git commit -m "init" && git push origin master:main
```

## 目录约定

| 目录 | 放什么 | 规则 |
|------|--------|------|
| `src/` | 所有 .c 源码 | `main.c` 是入口，其余是库 |
| `include/` | 所有 .h 头文件 | 和 src 一一对应 |
| `tests/` | 测试代码 | 文件名 `test_<模块>.c`，一个文件一个 `main()` |

## Make 目标

| 命令 | 做什么 |
|------|--------|
| `make` | 编译主程序 |
| `make test` | 编译 + 运行测试 |
| `make test ARCH=arm64` | 交叉编译测试 + qemu 模拟执行 |
| `make verify ARCH=arm64` | 检查 ARM64 二进制格式 |
| `make clean` | 清理 |

## 测试框架

`tests/test_utils.h` 提供 TEST/CHECK 宏，零外部依赖。
每个 `tests/test_*.c` 文件独立编译和运行。
Jenkins 通过返回码判 pass/fail（0=过，非 0=挂）。

## CI/CD 流水线

```
git push → Jenkins 自动触发:
  1. Cross Compile (aarch64)
  2. Unit Test (qemu-aarch64)
  3. Verify Binary (file 检查)
  4. Deploy to LubanCat (SCP → 笔记本 → 鲁班猫)
  5. 成功/失败 弹 Windows Toast 通知
```
