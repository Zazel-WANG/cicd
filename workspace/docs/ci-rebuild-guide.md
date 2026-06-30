# 嵌入式 CI/CD 平台 — 重建完全指南

> **用途**: 为新嵌入式项目（如麒麟卫星 OS）搭建 CI/CD 平台时，按本文档可完整复现
> **日期**: 2026-06-30
> **验证**: 鲁班猫 RK3588 OS 镜像构建已验证通过（15 天，40+ 次构建）

---

## 一、架构总览

```
┌─────────────────────────────────────────────────────┐
│ 主机 (Ubuntu Server 22.04+)                         │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Gitea    │  │ Jenkins  │  │ os-builder       │  │
│  │ :3000    │  │ :8080    │  │ (Docker 镜像)    │  │
│  │ git 仓库 │  │ Pipeline │  │ 交叉编译工具链   │  │
│  └────┬─────┘  └────┬─────┘  └────────┬─────────┘  │
│       │              │                │             │
│  webhook ──────────→ │                │             │
│       │         cron 12:00/17:00      │             │
│       │              │                │             │
│       │         ┌────┴────┐           │             │
│       │         │ Check   │           │             │
│       │         │ changes │           │             │
│       │         └────┬────┘           │             │
│       │              │                │             │
│       │         ┌────┴────┐           │             │
│       │         │ Build   │←──────────┘             │
│       │         │ docker  │  -v /data/os-workspace  │
│       │         │ run     │  --user 1000:1000       │
│       │         └────┬────┘  --privileged           │
│       │              │                               │
│       │         ┌────┴────┐                          │
│       │         │ Archive │                          │
│       │         │ update  │                          │
│       │         │ .img    │                          │
│       │         └─────────┘                          │
│                                                     │
│  /data/os-workspace/         ← main 全 SDK (33G)    │
│  /data/os-workspace-feature/ ← feature 内核 (8.3G)  │
└─────────────────────────────────────────────────────┘
```

**双通道触发**:
| 通道 | 分支 | 触发方式 | 构建类型 | 耗时 |
|------|------|------|------|------|
| main | main | cron 12:00/17:00 + git ls-remote 变更检测 | 全编 (uboot→kernel→rootfs→updateimg) | ~8.5min |
| feature | feature/* | Gitea webhook push | 增量编译 (仅 kernel make) | ~3min |

---

## 二、硬件需求

| 项目 | 最低 | 推荐 |
|------|------|------|
| CPU | 4 核 | 8 核 (RK3588 编译并行 -j4) |
| 内存 | 8GB | 16GB |
| 磁盘 | **150GB** | 250GB+ |
| 磁盘说明 | OS SDK 源码 ~33G + Docker 镜像 ~12G + Git 仓库 ~8G + 每次全编 img ~3.6G | |

---

## 三、依赖清单

### 3.1 主机软件

```bash
# Ubuntu Server 22.04+
apt install -y docker.io docker-compose-v2 git curl \
    qemu-user-static binfmt-support openssh-server
```

### 3.2 Docker 服务

| 服务 | 镜像 | 端口 | 用途 |
|------|------|------|------|
| Gitea | `gitea/gitea:latest` | 3000 (HTTP), 2222 (SSH) | Git 仓库 + Webhook |
| Jenkins | `lubancat-jenkins:latest` (自定义) | 8080 (Web), 50000 (Agent) | CI Pipeline |
| os-builder | `os-builder:latest` (自定义) | — | ARM64 交叉编译容器 |

### 3.3 用户需要提供

| 项目 | 说明 | 示例 |
|------|------|------|
| SDK 源码 tarball | 芯片厂商 SDK (uboot + kernel + rootfs + 工具链) | LubanCat SDK ~33G |
| 交叉工具链 | ARM64/aarch64 工具链 (gcc-arm-10.3-*) | `prebuilts/gcc/linux-x86/aarch64/` |
| Jenkins 初始密码 | `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` | |
| Gitea 管理员账号 | 首次访问 localhost:3000 创建 | wangzhongqi |
| Jenkins 管理员账号 | 首次访问 localhost:8080 创建 | wangzhongqi |
| Jenkins API Token | `http://jenkins:8080/user/<user>/configure` → API Token | 用于 Webhook URL |

---

## 四、参考代码位置

```
E:\AI-helper\projects\cicd\workspace\
├── docker-compose.yml          # Gitea + Jenkins 服务编排
├── Jenkins.Dockerfile          # Jenkins 自定义镜像 (交叉编译工具)
├── os-build/
│   ├── Dockerfile              # os-builder 构建镜像
│   ├── Jenkinsfile-main        # main 分支 Pipeline (参考)
│   └── Jenkinsfile-feature     # feature 分支 Pipeline (参考)
└── docs/
    ├── phase1-tutorial.md      # 原始搭建教程
    └── phase3-recovery.md      # 凭证速查 + 故障恢复
```

**注意**: Jenkinsfile 的正式版本在 **kernel 仓库根目录**（Gitea: `wangzhongqi/kernel.git` 的 `Jenkinsfile`），不在 cicd 仓库。cicd 仓库的 `Jenkinsfile-main` 是参考副本。

---

## 五、搭建步骤

### Step 1: 主机环境准备

```bash
# 安装 Docker
apt install -y docker.io docker-compose-v2
systemctl enable docker

# 安装 QEMU (rootfs 构建需要)
apt install -y qemu-user-static binfmt-support

# 创建数据目录
mkdir -p /data/{gitea,jenkins,os-workspace,os-workspace-feature,os-images}
```

### Step 2: 解压 SDK

```bash
# ⚠️ 必须在 Linux 上解压，Windows 会损坏 symlink/权限/换行
tar xf SDK.tar.gz -C /data/os-workspace/
# 验证: ls /data/os-workspace/build.sh 应存在
```

### Step 3: 构建 Docker 镜像

```bash
# os-builder (交叉编译环境)
cd cicd/workspace/os-build/
docker build -t os-builder:latest -f Dockerfile .

# Jenkins (自定义版)
cd cicd/workspace/
docker build -t lubancat-jenkins:latest -f Jenkins.Dockerfile .
```

### Step 4: 启动 Gitea + Jenkins

```bash
cd cicd/workspace/
docker compose up -d gitea
# 等 Gitea 启动后:
docker compose up -d
```

### Step 5: 配置 Gitea

1. 访问 `http://<主机IP>:3000`，创建管理员账号
2. 创建组织/用户 `wangzhongqi`
3. 新建仓库 `kernel.git`（先创建空仓库，稍后 push 源码）
4. 生成 API Token: Settings → Applications → Generate Token → 复制保存
5. 将 kernel 源码 push 到仓库

### Step 6: 配置 Jenkins

1. 访问 `http://<主机IP>:8080`，输入初始密码
2. 安装推荐插件 + 手动安装: `Gitea`、`Pipeline`、`Git`
3. 创建管理员账号
4. 生成 API Token: Dashboard → 用户名 → Configure → API Token

### Step 7: 创建 Jenkins Job

#### 7.1 os-main (定时全编)

- **类型**: Pipeline
- **定义**: Pipeline script from SCM
- **SCM**: Git `http://<主机IP>:3000/wangzhongqi/kernel.git`
- **分支**: `*/main`
- **脚本路径**: `Jenkinsfile`
- **轻量级 checkout**: ❌ 不勾选

#### 7.2 os-feature (快速增量)

- **类型**: Multibranch Pipeline
- **Branch Source**: Gitea
- **Server**: `http://gitea:3000`（容器名，非主机 IP）
- **Owner**: wangzhongqi
- **Repository**: kernel
- **Behaviors**: Filter by name → `feature/*`
- **脚本路径**: `Jenkinsfile-feature`

### Step 8: 配置 Gitea Webhook

在 Gitea kernel 仓库 Settings → Webhooks → Add:

| Webhook | URL | 用途 |
|---------|-----|------|
| Gitea Plugin | `http://jenkins:8080/gitea-webhook/post` | 通用 |
| os-feature | `http://<user>:<API_TOKEN>@jenkins:8080/job/os-feature/indexing` | feature 分支触发 |

**⚠️ main 分支不需要 webhook**。main 只通过 cron 定时触发。

### Step 9: 初始化 feature workspace

```bash
# feature 需要独立的 kernel 工作目录（含 .o 文件）
cp -a /data/os-workspace/kernel /data/os-workspace-feature/
```

### Step 10: 验证

```bash
# 手动触发 main 构建
curl -X POST http://<user>:<API_TOKEN>@jenkins:8080/job/os-main/build

# 等待构建完成 (~8.5min 首次)，检查:
# - Jenkins os-main 页面: 9/9 stages 绿色
# - /data/os-workspace/rockdev/update.img 存在 (~3.6G)
# - /data/os-workspace/output/ 有新 img
```

---

## 六、Jenkinsfile 核心逻辑

### 6.1 main 分支 (`Jenkinsfile`)

```groovy
pipeline {
    agent any
    options { skipDefaultCheckout() }
    triggers { cron('0 12,17 * * *') }  // 每天 12:00, 17:00

    environment {
        KERNEL_REPO = 'http://10.0.0.1:3000/wangzhongqi/kernel.git'
    }

    stages {
        stage('Check changes') {
            steps {
                script {
                    // git ls-remote 对比上次构建 commit
                    // 无变更 → env.SHOULD_BUILD = 'false'
                    // 有变更 → 记录新 commit → env.SHOULD_BUILD = 'true'
                }
            }
        }
        stage('Build') {
            when { expression { env.SHOULD_BUILD == 'true' } }
            steps {
                sh 'docker run --rm --user 1000:1000 --privileged \
                    -v /data/os-workspace:/workspace \
                    os-builder:latest /workspace/ci-build.sh'
            }
        }
    }
    post {
        always {
            // 磁盘检查 + 旧镜像清理 (保留最新 3 个)
            sh '''
                USAGE=$(df -h /data | tail -1 | awk '{print $5}' | tr -d "%")
                if [ "${USAGE}" -gt 90 ]; then
                    echo "WARNING: Disk usage at ${USAGE}%"
                fi
                cd /data/os-workspace/output
                ls -1t lubancat-*.img | tail -n +4 | xargs -r rm
            '''
        }
    }
}
```

### 6.2 feature 分支 (`Jenkinsfile-feature`)

```groovy
pipeline {
    agent any
    stages {
        stage('Incremental Build') {
            steps {
                sh '''
                    docker run --rm --user 1000:1000 \
                        -v /data/os-workspace-feature:/workspace \
                        -v /data/os-workspace/prebuilts:/workspace/prebuilts:ro \
                        -v "${WORKSPACE}:/src:ro" \
                        os-builder:latest bash -c "
                            rsync -a /src/ /workspace/
                            cd /workspace
                            test -f .config || make ARCH=arm64 xxx_defconfig
                            make ARCH=arm64 -j4
                        "
                '''
            }
        }
    }
}
```

### 6.3 ci-build.sh (全编脚本)

```bash
#!/bin/bash
set -eo pipefail
cd /workspace

echo "=== build ==="
./build.sh BoardConfig-YourBoard.mk
./build.sh  # uboot → kernel → rootfs → updateimg

echo "=== archive ==="
VER=$(date +%Y%m%d-%H%M)
mkdir -p /workspace/output
cp rockdev/update.img /workspace/output/your-os-${VER}.img
echo "BUILD OK: your-os-${VER}.img"
```

### 6.4 Dockerfile (os-builder)

```dockerfile
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive

# 工具链 + 构建依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ssh make gcc libssl-dev liblz4-tool u-boot-tools curl \
    expect g++ patchelf chrpath gawk texinfo diffstat binfmt-support \
    qemu-user-static live-build bison flex fakeroot cmake \
    gcc-multilib g++-multilib unzip device-tree-compiler \
    python3-pip python2 libncurses5-dev python3-pyelftools \
    dpkg-dev pigz file bc rsync build-essential sudo \
    openssh-client ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 创建 builder 用户 (UID 1000, 与主机一致)
RUN useradd -u 1000 -m -s /bin/bash builder && \
    usermod -aG disk builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder

RUN ln -sf /usr/bin/python3 /usr/bin/python
WORKDIR /workspace
```

---

## 七、关键注意事项

### 7.1 pollSCM 陷阱

**不要使用 `pollSCM`**。Pipeline 类型 job + `CpsScmFlowDefinition` 存在已知缺陷（JENKINS-46431），SCMTrigger 永远返回 0ms。用 `cron + git ls-remote` 替代。

### 7.2 磁盘管理

- 每个全编 img ~3.6GB
- **必须加自动清理**: `post{always}` 中 `ls -1t *.img | tail -n +4 | xargs -r rm`
- Jenkins 容器需挂载 `/data` 以访问输出目录

### 7.3 Shell 转义

- Jenkinsfile 中 **不要通过 ssh heredoc 写文件**——多层转义极易出错
- 用 `git push` 或 `scp` 上传文件
- `sh '''...'''` 中的 `$` 和 `\` 仍需谨慎: 使用 `df -h | awk '{print $5}'` 而非 `df --output=pcent`（alpine 不支持）

### 7.4 UID/GID 一致性

- 主机 embedsys: UID 1000
- Jenkins 容器 jenkins: UID 1000
- os-builder builder: UID 1000 + disk 组 + NOPASSWD sudo
- Docker socket: 容器内用户需在 docker 组（GID 通常 = 124）

### 7.5 多分支隔离

- main 和 feature **必须有独立 workspace**，不能共享同一目录
- feature 增量编译依赖首次全编的 `.o` 文件

---

## 八、故障速查

| 症状 | 根因 | 解决方案 |
|------|------|------|
| Jenkins job 不触发 | Webhook 未配或 cron 未注册 | 检查 Webhook URL + `triggers{cron(...)}` |
| `losetup: Permission denied` | 容器用户不在 disk 组 | Dockerfile 加 `usermod -aG disk builder` |
| `df: No such file or directory` | Jenkins 容器无 `/data` 挂载 | docker-compose 加 `- /data:/data` |
| `No space left on device` | 磁盘满 | 清理旧 img + 启用自动清理 |
| cron 不触发 | PipelineTriggersJobProperty 未持久化 | 手动跑一次 pipeline 注册 trigger |
| Groovy parse error (awk `$5`) | `sh '''...'''` 中 `$` 被 Groovy 插值 | 用 `awk '{print $5}'` 单引号保护 |

---

## 九、凭证清单

| 凭证 | 位置 | 用途 |
|------|------|------|
| Gitea 账号 | 首次访问创建 | Git 仓库管理 |
| Gitea API Token | Settings → Applications | Webhook + CI 通知 |
| Jenkins 账号 | 首次访问创建 | Job 管理 |
| Jenkins API Token | User → Configure → API Token | Webhook URL + 手动触发 |
| Gitea 仓库 URL | `http://<host>:3000/<user>/<repo>.git` | Jenkins SCM 配置 |
| 主机 IP | 私有子网 `10.0.0.1` | 所有服务访问 |

---

## 十、迁移到新项目 checklist

```
□ 主机: Ubuntu Server 22.04+, Docker + QEMU
□ SDK: 芯片厂商提供的完整 SDK (uboot/kernel/rootfs/工具链)
□ SDK 必须在 Linux 上解压
□ Docker 镜像: os-builder (交叉编译) + lubancat-jenkins
□ Docker Compose: Gitea + Jenkins 服务编排
□ Gitea: 创建仓库 + 生成 API Token
□ Jenkins: 创建 Pipeline + Multibranch Pipeline jobs
□ Gitea Webhook: os-feature indexing (main 不用)
□ Jenkinsfile: 放在目标仓库根目录
□ ci-build.sh: 放在 workspace 根目录
□ 初始化 feature workspace: cp 首次全编产物
□ 磁盘监控: post{always} + docker-compose /data 挂载
□ 验证: 手动触发 → 全编通过 → cron 自动触发通过
```
