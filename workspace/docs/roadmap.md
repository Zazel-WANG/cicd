# 鲁班猫 CI/CD 平台 —— 任务路线图

> 最后更新：2026.6.11，Phase 4 + 两个技术债全部完成

## 已完成

| 任务 | 内容 | 状态 |
|------|------|------|
| Phase 1 | 基础设施：Docker + Gitea + Jenkins + Webhook | ✅ |
| Phase 2 | 交叉编译流水线（aarch64-gcc + Jenkinsfile 三阶段） | ✅ |
| Phase 3 | 部署链路：Jenkins → 笔记本中转 → 鲁班猫 | ✅ |
| Phase 4a | QEMU 单元测试（14 用例，返回值驱动） | ✅ |
| Phase 4b | 真机执行测试（返回值回传 Jenkins） | ✅ 2026.6.12 |
| NOTIFY2 | Toast 通知修复（阶段定位 + 中文不乱码） | ✅ 2026.6.12 |
| TIMEZONE | Jenkins 时区修复（UTC+8） | ✅ 2026.6.12 |
| Phase 4c | 真正 HIL（外设参与，摄像头/NPU/屏幕） | 🔮 远期 |
| DEBT-1 | 修复 StrictModes no → icacls /grant:r 正确配 ACL | ✅ |
| NOTIFY | 失败通知：Windows Toast 弹窗，Jenkins post 触发 | ✅ |
| DEBT-2 | 修复 Jenkins Dockerfile：固化交叉编译工具链 | ✅ |

## 剩余任务

### 🟡 中期（开始写真实项目前）

| ID | 任务 | 现状 | 目标 |
|----|------|------|------|
| TEMPLATE | **项目模板** | hello.c 单文件 | ✅ 已完成 |
| VERSION | **构建产物版本化** | 覆盖 /tmp/hello | ✅ 已完成：hello-<hash> 归档 + symlink + 保留 2 版 |
| BRANCH | **多分支流水线** | master→main 混乱 | ✅ 已完成：Multibranch Pipeline + feature 不部署 |
| DOCS | **操作文档** | 分散在多个 md | 单份 README：架构图 + 快速启动 + 常见坑 |

### 🟢 远期（AI 项目开发时）

| ID | 任务 | 现状 | 目标 |
|----|------|------|------|
| DEPS | **依赖管理** | 无外部库 | OpenCV + NPU SDK + camera lib |
| DTS | **设备树/驱动测试** | 没用外设 | 屏幕、摄像头板上验证 |
| DOCS | **操作文档** | 分散 | 单份 README：架构图 + 启动 + 常见坑 |

## 建议推进顺序

```
✅ 全部完成 ──► 下一步: 开始写 AI 项目代码
```

### 开始 AI 项目前建议补的

| ID | 任务 | 说明 |
|----|------|------|
| DOCS | 操作文档 | 架构图 + 快速启动 + 常见坑，一份 README 收拢 |
| 分支清理 | 删掉 feature/test-branch | 测试分支，已完成使命 |

### 🟢 远期（AI 项目开发时）

| ID | 任务 |
|----|------|
| DEPS | 依赖管理（OpenCV + NPU SDK + camera lib） |
| DTS | 设备树/驱动测试（屏幕、摄像头板上验证） |
| HIL | 真正硬件在环测试（外设参与） |

## 架构可迁移性分析

迁移到卫星 OS 内网环境时：

**不变**：Docker 编排、Gitea+Jenkins、Jenkinsfile 阶段骨架、Skills 知识库

**取决于目标环境**：板卡网络位置、部署方式、测试判定方式

**迁移时必改**：
- `Jenkins.Dockerfile`：交叉编译链（aarch64-linux-gnu-gcc → 板卡对应工具链）
- `Makefile`：ARCH 参数、CFLAGS、链接方式
- `Jenkinsfile`：Deploy 阶段的 SCP 路径、目标 IP
- `deploy-to-lubancat.ps1`：重命名，参数化目标
