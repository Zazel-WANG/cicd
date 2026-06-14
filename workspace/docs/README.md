# 鲁班猫嵌入式 CI/CD 平台 —— 操作与维护文档

> 最后更新：2026.6.12
> 状态：全链路就绪（Phase 1-4 + TEMPLATE + VERSION + BRANCH）

---

## 一、系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        鲁班猫 CI/CD 平台                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  鲁班猫 RK3588              笔记本 (Windows)         主机 (Ubuntu Server 22.04) │
│  ARM64, NPU                 10.0.0.2               10.0.0.1                  │
│  IP: 192.168.137.100        SSH 中转 + 部署代理     Docker: Gitea + Jenkins  │
│      │                          │                       │                    │
│      │    USB 共享网络          │     网线直连          │                    │
│      └────── cat ──────────────┘  10.0.0.0/24 ─────────┘                    │
│                                                          │                    │
│  ┌──────────────────┐     ┌──────────────────┐    ┌──────────────────┐      │
│  │  /home/cat/deploy │     │  deploy/*.ps1    │    │  gitea :3000     │      │
│  │  hello-abc1234   │     │  artifacts/      │    │  jenkins :8080   │      │
│  └──────────────────┘     └──────────────────┘    └──────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**数据流**：`git push → Gitea Webhook → Jenkins → 交叉编译 → QEMU 测试 → SCP 笔记本 → 笔记本 SCP 鲁班猫 → 执行 → Toast 通知`

**三台机器互访关系**：

| 从 → 到 | 笔记本 | 主机 | 鲁班猫 |
|---------|--------|------|--------|
| 笔记本  | -      | SSH (10.0.0.1, embedsys) | SSH (192.168.137.100, cat) |
| 主机    | SSH (10.0.0.2, HUAWEI) | - | ❌ 不通（无直连链路） |
| 鲁班猫  | ❌ | ❌ | - |

---

## 二、目录结构

```
E:\AI-helper\CICD_patform\
├── CLAUDE.md                        # 项目总纲（AI 读取）
├── CHANGELOG.md                     # 变更日志
├── skills/                          # 知识库
│   ├── ci-cd-pipeline/SKILL.md      # CI/CD 流水线知识
│   ├── embedded-cross-compile/SKILL.md
│   └── cross-domain/
│       ├── project-context/SKILL.md # 硬件环境 + 用户约束
│       ├── prompt-templates/SKILL.md
│       └── workflow/SKILL.md
├── workspace/
│   ├── docs/                        # 文档（本文件在此）
│   │   ├── README.md                # ← 你正在看的
│   │   ├── roadmap.md               # 任务路线图
│   │   ├── phase3-recovery.md       # 重启恢复指南
│   │   ├── phase1-tutorial.md       # Phase 1 教学文档
│   │   ├── ci-cd-foundation-learning.md
│   │   └── network-fundamentals.md
│   ├── deploy/                      # 部署脚本
│   │   ├── deploy-to-lubancat.ps1   # 笔记本→鲁班猫 SCP + 执行
│   │   ├── notify-build.ps1         # Windows Toast 弹窗通知
│   │   └── fix-network-profile.ps1  # 开机自修复（网络+sshd）
│   ├── repos/                       # 本地 git 仓库
│   │   ├── test-ci/                 # 测试项目（14 用例）
│   │   └── project-template/        # 项目模板
│   ├── docker-compose.yml           # Docker 服务编排
│   └── project-template/            # 模板（独立 git 仓库）
└── references/                      # 参考资料
    ├── datasheets/                   # 芯片手册
    ├── manuals/                      # 工具手册
    ├── specs/                        # 规范
    └── notes/                        # 踩坑笔记
```

---

## 三、网络拓扑

```
鲁班猫 RK3588 ──USB共享──→ 笔记本(Win) ──网线(10.0.0.x)──→ 主机(Ubuntu Server)
    ARM64                  10.0.0.2             私有子网      10.0.0.1
    IP: 192.168.137.100     WiFi: 192.168.118.152               WiFi: 192.168.119.242
    用户: cat               用户: HUAWEI                        有线: 172.30.192.251
                                                                 用户: embedsys
```

| 接口 | IP | 用途 |
|------|-----|------|
| 主机 USB 网口 | `10.0.0.1/24` | 直连笔记本，代码推送 + SCP 部署 |
| 主机 WiFi | `192.168.119.242` | 外网（apt install / docker pull） |
| 主机 有线 | `172.30.192.251` | 公司内网 |
| 笔记本 有线 | `10.0.0.2/24` | 直连主机，私有子网 |
| 笔记本 WiFi | DHCP | 外网（GitHub / 日常） |
| 笔记本 USB | `192.168.137.1` | 共享网络给鲁班猫 |
| 鲁班猫 | `192.168.137.100` | 固定 IP，通过笔记本 USB 共享上网 |

> ⚠️ **笔记本是唯一三通节点**（外网 + 主机 + 鲁班猫），所有部署流量经它中转。
> 公司 WiFi 有 VLAN 隔离，不同子网间无法直连——所以必须走网线私有子网 `10.0.0.x`。

---

## 四、服务清单

| 服务 | 位置 | 地址 | 账号 |
|------|------|------|------|
| Gitea | 主机 Docker | `http://10.0.0.1:3000` | `wangzhongqi` |
| Gitea SSH | 主机 Docker | `ssh://git@10.0.0.1:2222` | — |
| Jenkins | 主机 Docker | `http://10.0.0.1:8080` | `wangzhongqi` |
| 鲁班猫 SSH | 鲁班猫 | `192.168.137.100:22` | `cat` |
| 主机 SSH | 主机 | `10.0.0.1:22` | `embedsys` |

**容器管理命令**（在主机上）：
```bash
docker ps                          # 看状态
cd ~/cicd && docker compose up -d  # 启动所有服务
docker compose restart jenkins     # 单独重启 Jenkins
docker compose logs jenkins        # 看 Jenkins 日志
```

---

## 五、CI/CD 流水线

### 完整链路

```
git push (笔记本)
  → Gitea Webhook (主机)
    → Jenkins Multibranch Pipeline (主机 Docker)
      → Cross Compile (aarch64-gcc + -static)
      → Unit Test (qemu-aarch64 模拟 ARM64)
      → Verify Binary (file 检查)
      → Deploy to LubanCat  ← main 分支才执行
        → SCP 二进制 → 笔记本
          → 笔记本 SCP → 鲁班猫 /home/cat/deploy/
            → chmod +x → 运行 → 返回值回传
      → Toast 弹窗 (Windows 通知)
```

### 分支策略

| 分支 | 编译 | 测试 | 验证 | 部署 | 用途 |
|------|------|------|------|------|------|
| `main` | ✅ | ✅ | ✅ | ✅ 部署 | 稳定版本，板子跑的就是它 |
| `feature/*` | ✅ | ✅ | ✅ | ❌ 不部署 | 开发分支，只检查不推到板子 |

### 产物版本化

鲁班猫上：
```
/home/cat/deploy/
  hello → hello-2f5dad6        ← 软链接指向当前版本
  hello-2f5dad6                 ← 当前（704KB）
  hello-ac9db82                 ← 上一版（保留用于回滚）
  （更旧的自动清理，只保留 2 个）
```

回滚命令：`ssh cat@192.168.137.100 "ln -sf hello-ac9db82 /home/cat/deploy/hello"`

---

## 六、🚹 只有你能做的事

> 这些操作需要物理接触硬件、Web UI 交互、或 GUI 操作。AI 无法代劳。

### 🖥️ 笔记本（Windows）

| 操作 | 步骤 | 频率 |
|------|------|------|
| **修复网络 Profile** | 管理员 PowerShell: `Set-NetConnectionProfile -InterfaceAlias "以太网 2" -NetworkCategory Private` | 重启后（有开机脚本自动修，但偶尔失效） |
| **手动启动 sshd** | `Start-Service sshd` | 极少（开机脚本已守护） |
| **检查任务计划程序** | `taskschd.msc` → 确认 `FixNetworkProfile` 状态 Ready | 偶尔确认 |
| **Windows 更新后检查** | 更新后可能重置 sshd 启动类型和网络 Profile | 每次大更新后 |
| **ICS 共享设置** | 网络连接 → WLAN → 属性 → 共享 → 共享给以太网 3 | 极少（重启后 ICS 偶发失效） |

### 🖥️ Jenkins Web UI（`http://10.0.0.1:8080`）

| 操作 | 步骤 | 频率 |
|------|------|------|
| **新建 Multibranch Pipeline** | New Item → 输名字 → 选 Multibranch Pipeline → 配 Git 源 | 新项目时 |
| **管理凭据** | Manage Jenkins → Credentials → 添加/修改 | 凭据过期或新增 |
| **手动扫描分支** | 进入项目 → Scan Multibranch Pipeline Now | feature 分支 push 后未自动发现时 |
| **查看构建日志** | 点构建号 → Console Output | 排查失败时 |

### 🖥️ Gitea Web UI（`http://10.0.0.1:3000`）

| 操作 | 步骤 | 频率 |
|------|------|------|
| **创建新仓库** | 右上角 + → New Repository | 新项目时 |
| **配置 Webhook** | 仓库 → Settings → Webhooks → 填 URL | 新仓库或迁移 Jenkins 任务时 |
| **Webhook URL 格式** | `http://wangzhongqi:APIToken@jenkins:8080/job/<任务名>/job/<分支名>/build?token=lubancat` | — |
| **创建 Pull Request** | 仓库 → Pull Requests → New | 合并 feature 到 main 时 |
| **查看分支列表** | 仓库 → Branches | 日常 |

### 🔌 物理硬件

| 操作 | 说明 |
|------|------|
| **鲁班猫上电/断电** | USB 线拔插或电源开关 |
| **网线插拔** | 笔记本 ↔ 主机直连网线 |
| **USB 网卡插拔** | 主机侧 USB 转 RJ45 适配器 |
| **鲁班猫 USB 共享线** | 笔记本 ↔ 鲁班猫 USB 线 |

### 🔑 凭据与安全

| 项目 | 说明 |
|------|------|
| Jenkins API Token | `http://10.0.0.1:8080/user/wangzhongqi/configure` → API Token |
| Gitea 密码 | 自己管理 |
| SSH 密钥初始分发 | 新机器加入时需要手动把公钥写到目标机器的 `authorized_keys` |
| 桌面 `credentials.md` | 所有敏感信息汇总文件 |

---

## 七、AI 可以直接做的事

> 以下操作 AI 可独立完成，无需你手动介入。

| 类别 | 操作 | 示例 |
|------|------|------|
| 代码 | 编辑源码、脚本、配置 | 改 hello.c、改 Makefile |
| Git | commit、push、创建分支 | `git add && git commit && git push` |
| 主机 | SSH 进主机操作 Docker | `docker compose restart jenkins` |
| 鲁班猫 | SSH 进板子检查状态 | `ls /home/cat/deploy/` |
| 文件 | 读写项目内所有文件 | Jenkinsfile、Dockerfile、脚本 |

---

## 八、快速启动（从零恢复全链路）

### 前提假设

- 三台设备已通电
- 网线已连接（笔记本 ↔ 主机）
- USB 共享线已连接（笔记本 ↔ 鲁班猫）
- 鲁班猫 IP 固定为 `192.168.137.100`

### 恢复步骤（约 5 分钟）

**1. 笔记本——检查网络**（管理员 PowerShell）
```powershell
Get-NetConnectionProfile | Format-Table InterfaceAlias, NetworkCategory
Set-NetConnectionProfile -InterfaceAlias "以太网 2" -NetworkCategory Private
Set-NetConnectionProfile -InterfaceAlias "以太网 3" -NetworkCategory Private
ping 10.0.0.1 && ping 192.168.137.100
```

**2. 笔记本——检查 sshd**
```powershell
Get-Service sshd | Format-List Name, Status, StartType
# 如果没运行： Start-Service sshd
```

**3. 笔记本——检查鲁班猫**
```bash
ssh cat@192.168.137.100 "echo OK && ls /home/cat/deploy/"
```

**4. 笔记本——检查主机**
```bash
ssh embedsys@10.0.0.1 "docker ps"
# 期望 gitea + jenkins 都是 Up
```

**5. 主机——验证 Jenkins → 笔记本**
```bash
docker exec jenkins ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 HUAWEI@10.0.0.2 "echo SSH OK"
```

**6. Jenkins UI——全链路验证**
浏览器 `http://10.0.0.1:8080` → project-template → main → Build Now → 观察输出

### 开机自动修复

任务计划程序 `FixNetworkProfile` 每次开机自动执行：
- 等待三块网卡就绪（最长 60 秒）
- 设为 Private
- 确保 sshd 运行

---

## 九、常见问题速查

| 症状 | 原因 | 解决 |
|------|------|------|
| Jenkins SSH 笔记本超时 | 网络 Profile 变 Public | `Set-NetConnectionProfile` 设 Private |
| sshd 没启动 | Windows 更新后重置 | `Start-Service sshd` |
| Jenkins 时间不对 | Docker 容器 UTC | docker-compose 已配 `TZ=Asia/Shanghai` |
| Toast 弹窗乱码 | ✅ 已修复（base64 管道 + @() 冻结数组） | — |
| 鲁班猫 ping 不通 | ICS 失效或 IP 漂移 | 笔记本侧检查 ICS 共享 + 鲁班猫侧 `nmcli` 确认 |
| feature 分支 push 没部署 | ✅ 设计如此（when { branch 'main' }） | — |
| git push 需要打全路径 | `master:main` 映射未清理 | ✅ 已统一为 `main`，直接 `git push` |
| deploy 阶段卡住 | `$result = ssh @"..."@` 阻塞 | ✅ 已修复，拆为独立 SSH 调用 |
| 鲁班猫 `/tmp` 文件重启消失 | ✅ 已切到 `/home/cat/deploy/` | — |

---

## 十、添加新项目

以 project-template 为蓝本：

```bash
# 1. 复制模板
cp -r workspace/project-template workspace/repos/my-new-project
cd workspace/repos/my-new-project

# 2. 改项目名
# 编辑 Makefile 第一行：PROJECT := my-new

# 3. 初始化 git
rm -rf .git && git init
git add -A && git commit -m "init"
git remote add origin ssh://git@10.0.0.1:2222/wangzhongqi/my-new-project.git
git push -u origin main

# 4. 在 Gitea 上配置 Webhook（🚹 需手动操作 UI）
# 5. 在 Jenkins 上创建 Multibranch Pipeline（🚹 需手动操作 UI）
```

---

## 十一、迁移到卫星 OS 环境

需改的部分：

| 组件 | 改什么 |
|------|--------|
| `Jenkins.Dockerfile` | 交叉编译链（`aarch64-linux-gnu-gcc` → 目标板工具链） |
| `Makefile` | `ARCH`、`CFLAGS`、链接方式 |
| `Jenkinsfile` | Deploy 阶段 SCP 路径和 IP |
| `deploy-to-lubancat.ps1` | 目标 IP、用户、部署路径 |
| 网络拓扑 | `10.0.0.x` 改为新环境私有子网 |

不变的部分：Docker 编排、Gitea+Jenkins 架构、Jenkinsfile 阶段骨架、Skills 知识库。

---

## 相关文档

| 文档 | 用途 |
|------|------|
| `roadmap.md` | 任务进度与路线图 |
| `phase3-recovery.md` | 详细的恢复步骤和配置速查 |
| `phase1-tutorial.md` | Phase 1 教学（Docker/Gitea/Jenkins 基础） |
| `ci-cd-foundation-learning.md` | CI/CD 概念学习笔记 |
| `network-fundamentals.md` | 网络知识笔记 |
| `CHANGELOG.md` | 完整变更历史 |
