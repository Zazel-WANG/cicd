# 变更日志

## 2026-06-25 — Phase 2 OS 镜像 CI/CD：首次构建成功 + 去重修复

### 成果
- **os-builder Docker 镜像**：`workspace/os-build/Dockerfile`，Ubuntu 20.04 + LubanCat SDK 全构建依赖
- **首次全编成功**：3.6GB `update.img` 产出，经 Jenkins `os-main` Pipeline 全链路验证

### Jenkins Job 配置

| Job | 类型 | Gitea 仓库 | 分支 | Jenkinsfile | 触发 |
|------|------|------|------|------|------|
| `os-main` | Pipeline | `wangzhongqi/kernel` | `*/main` | `Jenkinsfile` | pollSCM `H 12,17 * * *` + webhook |
| `os-feature` | Multibranch | `wangzhongqi/kernel` | `feature/*` | `Jenkinsfile-feature` | webhook (push → indexing) |

### 核心设计
- **零噪音**：pollSCM 只在 kernel.git 有新 commit 时触发 → 无 commit = 无构建记录
- **增量智能**：`ci-build.sh` 内 `repo sync` 检测全部 8 个仓库变更，manifest 未变则 `exit 0`
- **双轨**：feature push → webhook → os-feature Multibranch 扫描 + 增量构建；main → 定时 check 全编

### 修复项
- kernel.git `Jenkinsfile` 去重（同一 pipeline 写了两遍）
- 定时从 `H 12,20` → `H 12,17`（下午 5 点）
- kernel.git 无 webhook → 新增 2 个（gitea-webhook/post + os-feature/indexing）
- `ci-build.sh` 拉回 cicd 本地版本控制

### 关键教训
- Linux SDK 源码**绝不经过 Windows 文件系统**（CRLF/symlink/权限损坏）
- `repo sync -c --no-repo-verify` 首次从 Gitea 拉 8 个仓库耗时较长

### 文件
- `workspace/os-build/`：Dockerfile + Jenkinsfile-main + Jenkinsfile-feature + ci-build.sh + sync-repos.sh

## 2026-06-17 — embed-hello: AI 交叉编译流水线（来自 embed-hello 侧，Claude 提交）

### 架构决策
- **Route B 落地**：embed-hello 首个采用项目自包含构建镜像模式
  - `workspace/Dockerfile.build` — embed-hello-builder 镜像（Ubuntu 22.04 + aarch64 gcc + 板提取 sysroot）
  - `workspace/scripts/sysroot-populate.sh` — 从鲁班猫 SSH 拉取 GStreamer/X11/glib/RKNN 交叉编译依赖
  - Jenkinsfile 用 `sh + docker run` 执行构建，无需 Docker Pipeline 插件

### Jenkins 容器变更
- Debian `docker.io` 包不含 CLI → 从宿主机 `docker cp /usr/bin/docker jenkins:/usr/local/bin/` 复制 Docker CLI 二进制（v29.1.3）
- `docker-compose.yml` 新增 `group_add: "124"`（docker 组 GID 映射）

### 最终验证
- Build #32-#35 全部 SUCCESS，5 个 AI 二进制（ai-query/infer/gst/x11/full）自动部署到 `/home/cat/deploy-dev/ai/`
- 清理后代码仓库瘦身 ~45MB（旧构建历史 + 临时脚本 + 本地 sysroot 副本）
- `rknn_api.h` 统一为 SDK 697 行版，消除本地 804 行版本不一致隐患

### 关键教训
1. **sysroot 传递依赖链**：GStreamer → libunwind → liblzma / libdw → libbz2，X11 → libXdmcp → libbsd → libmd。手动列举脆弱，应考虑 `readelf -d` 递归自动化
2. **glibc linker scripts 保护**：板子 libc.so.6 是 ELF binary，会覆盖交叉编译器的 linker script → Dockerfile 需 `apt reinstall libc6-dev-arm64-cross`
3. **Docker mount 路径**：Jenkins 容器内路径 ≠ 宿主机路径，`-v` 必须用宿主机路径（`/var/jenkins_home` → `/data/jenkins`）
4. **网络拓扑**：Jenkins 容器在 10.0.0.x 网段，无法直连 192.168.137.x（鲁班猫），部署需经 Windows 跳板
5. **Docker CLI 获取**：Debian trixie 的 `docker.io` 包不提供 `/usr/bin/docker`，需从宿主机直接复制或用 Docker 官方静态二进制

### 可复用模式
- `sysroot-populate.sh` → 任何需要目标板原生库的交叉编译项目
- `Dockerfile.build` + `sh docker run` → 项目自包含构建环境，Jenkins 只提供 Docker socket

## 2026-06-16 — 部署脚本项目化 + Gitea 插件 401 修复（来自 embed-hello 侧）

### 跨项目问题暴露
- **Toast 通知出现幽灵文本** "SCP部署阶段也需cd到子目录"：根因是 embed-hello 的 Jenkinsfile 指向 `cicd\workspace\deploy\notify-build.ps1`，但 SCP 的 build-status.txt 落在 `embed-hello\workspace\build\`，两路径不一致 → 脚本一直读 cicd 的旧文件
- **跨项目耦合风险**：cicd 的 deploy 脚本被其他项目引用，改 cicd 路径会误伤

### 架构决策
- **每个嵌入式项目自包含 deploy 脚本**：`<project>/workspace/deploy/` 下放自己的 `notify-build.ps1`
- **cicd 的 deploy/ 脚本定位为模板**，不作为其他项目的运行时依赖
- **embed-hello** 已执行此方案：复制脚本 → 改路径为自项目 → Jenkinsfile 指向本地

### Gitea 通知修复
- Gitea 插件 (v273) 与 Gitea 1.26.2 不兼容，commit status API 始终 401
- 方案：Jenkinsfile `post` 中用 `withCredentials([string(credentialsId: 'gitea-api-token', ...)])` + `curl` 直接调 Gitea API
- Jenkins 凭据中新增 `gitea-api-token`（Secret text），token 不入代码，GitHub public 安全

### cicd 自身检查清单（见 .hot/recovery.md 交接区）

## 2026-06-15 — 嵌套仓库落地 + Gitea 双 remote + 路径重构
- **Git 仓库**：cicd 从父仓库拆分，成为独立 git 仓库，路径 `E:\AI-helper\projects\cicd\`
- **双 remote**：
  - `origin` → `git@github.com:Zazel-WANG/cicd.git`（public，面试展示）
  - `gitea` → `ssh://git@10.0.0.1:2222/wangzhongqi/cicd.git`（触发 Jenkins CI/CD）
- **分支**：`master→main` 统一
- **Jenkins 配置**：
  - `cicd`（原 project-template）Multibranch Pipeline → 仓库改为 `http://gitea:3000/wangzhongqi/cicd.git`，Jenkinsfile 路径 `workspace/project-template/Jenkinsfile`
  - `test-pipeline` → 仓库同上，Jenkinsfile 路径 `workspace/repos/test-ci/Jenkinsfile`，已禁用
  - Webhook 3 个：gitea-webhook/post + project-template/main/build + test-pipeline/build（test-pipeline webhook 可删）
- **路径修正**：所有 `CICD_patform→projects/cicd`，Jenkinsfile 内 `make` 和 `scp` 需 `cd workspace/project-template/`（仓库根目录无 Makefile）
- **验证**：cicd 多分支流水线编译→测试→验证→部署鲁班猫→Toast 通知，全链路通过

## 2026-06-14 — 项目重定位
- 项目角色明确：基础设施维护（Docker/Jenkins/Gitea），不管理具体嵌入式项目
- 新嵌入式项目在 `projects/` 下独立初始化，用 AI_PROJECT_INIT.md
- project-template 归档为参考，不再作为活项目
- E:\AI-helper\ git init，系统仓库推 Gitea 私有做远程备份
