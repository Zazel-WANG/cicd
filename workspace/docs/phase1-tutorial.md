# CI/CD 基础设施搭建教程（Phase 1）

> 本文档基于真实搭建过程中的试错经验编写。如果你完全按本文档操作，可以避开我们踩过的每一个坑。

---

## 目录

1. [背景：你在搭建什么？](#一背景你在搭建什么)
2. [架构总览](#二架构总览)
3. [前置条件](#三前置条件)
4. [Step 1：建立物理网络连接](#四step-1建立物理网络连接)
5. [Step 2：配置静态 IP 与固化](#五step-2配置静态-ip-与固化)
6. [Step 3：安装 Docker](#六step-3安装-docker)
7. [Step 4：部署 Gitea](#七step-4部署-gitea代码仓库)
8. [Step 5：部署 Jenkins](#八step-5部署-jenkinsci-引擎)
9. [Step 6：笔记本 ↔ Gitea SSH 链路](#九step-6笔记本--gitea-ssh-链路)
10. [Step 7：Jenkins ↔ Gitea 集成](#十step-7jenkins--gitea-集成)
11. [Step 8：Webhook 自动触发](#十一step-8webhook-自动触发)
12. [故障排查索引](#十二故障排查索引)
13. [概念速查表](#十三概念速查表)

---

## 一、背景：你在搭建什么？

### 目标

```
现在：                    未来：
  笔记本写代码  →  手动编译  →  手动拷到板子上运行
  
  笔记本写代码  →  git push  →  自动编译  →  自动部署  →  自动测试
                               (在服务器上)   (到鲁班猫)
```

### 三台设备

| 设备 | 角色 | OS | 网络能力 |
|------|------|-----|----------|
| 笔记本 | 写代码 + 中转部署 | Windows 11 | WiFi（外网），有线（连主机） |
| 主机 | 运行 CI/CD 服务 | Ubuntu Desktop 22.04 | WiFi（外网），有线（公司内网），USB网口（连笔记本） |
| 鲁班猫 RK3588 | 目标运行板 | Linux ARM64 | 通过笔记本 USB 共享上网 |

### CI/CD 流水线的三要素

```
代码仓库       CI 引擎       部署通道
    │            │              │
Gitea    +   Jenkins   +   SCP/SSH   =   全自动流水线
(自建Git服务)  (自动构建机)   (产物→鲁班猫)
```

---

## 二、架构总览

### 网络拓扑

```
                      ┌─────────────────────────────────┐
                      │         公司网络                  │
                      │  WiFi VLAN 118    WiFi VLAN 119 │
                      │       │                │        │
                      │   笔记本WiFi       主机WiFi      │
                      │       │                │        │
                      └───────┼────────────────┼────────┘
                              │                │
                              │  ❌ 被VLAN隔离  │
                              │  两个WiFi不能   │
                              │  互相通信       │
                              │                │
    ┌─────────────┐           │                │
    │  笔记本 Win  │←──网线直连──→│    ┌─────────┴──────────┐
    │  10.0.0.2   │  私有子网   │    │  主机 Ubuntu        │
    │             │ 10.0.0.0/24│    │  10.0.0.1           │
    │  WiFi→外网  │            │    │                     │
    │  USB→鲁班猫 │            │    │ WiFi→外网           │
    └──────┬──────┘            │    │ 有线→公司内网        │
           │                   │    │                     │
           │ USB共享           │    │ Docker:             │
    ┌──────┴──────┐            │    │ ┌─────────────────┐ │
    │ 鲁班猫 RK3588│            │    │ │  ci-network     │ │
    │  ARM64      │            │    │ │  ┌──────┐┌────┐ │ │
    │  无独立IP   │            │    │ │  │Gitea ││Jen-│ │ │
    └─────────────┘            │    │ │  │:3000 ││kins│ │ │
                               │    │ │  │:2222 ││:8080│ │ │
                               │    │ │  └──────┘└────┘ │ │
                               │    │ └─────────────────┘ │
                               │    └─────────────────────┘
```

### 为什么用网线直连

公司 WiFi 部署了 **VLAN 隔离**——不同子网的客户端之间不能直接通信（标准企业安全策略）。笔记本（`192.168.118.x`）和主机（`192.168.119.x`）的 WiFi 虽然都能上网，但互相 ping 不通。

**解决方案**：一根网线 + USB 转 RJ45 适配器直连，配私有子网 `10.0.0.0/24`。数据包不走路由器、不经过公司网络——物理上就是一根线连着两张网卡。

### 四条数据链路

```
链路①  笔记本 ──SSH──────→ Gitea    (git push，端口2222)
链路②  Jenkins ──HTTP───→ Gitea    (拉代码构建，容器名直连)
链路③  主机   ──WiFi────→ 外网     (apt install, docker pull)
链路④  笔记本 ──HTTP───→ Gitea/Jenkins Web UI  (浏览器管理)
```

---

## 三、前置条件

### 硬件

| 物品 | 数量 | 用途 |
|------|------|------|
| USB 转 RJ45 千兆网口适配器 | 1 | 插在主机 USB 口，提供额外网口 |
| 网线（六类线及以上） | 1 | 直连笔记本和主机 |
| 笔记本（Windows） | 1 | 开发写代码 |
| 主机（Ubuntu Desktop） | 1 | 运行 CI/CD 服务 |

### 软件（需提前装好）

- [x] 主机 Ubuntu Desktop 已安装
- [x] 笔记本 VSCode 已安装 Remote-SSH 插件
- [x] 笔记本 Git 已安装（`git --version`）
- [x] 主机基础工具链：`build-essential`, `git`, `curl`

### 网络确认（每次操作前检查）

```bash
# 笔记本 → 主机
ping 10.0.0.1

# 主机 → 笔记本
ping 10.0.0.2

# 双向都通 = 可以开始
```

---

## 四、Step 1：建立物理网络连接

### 4.1 插硬件

1. USB 转 RJ45 适配器插入主机 USB 口
2. 网线一端插适配器，另一端插笔记本网口（或第二个 USB 转 RJ45）

### 4.2 确认新网卡被识别（主机）

```bash
ip link show
```

会看到所有网卡。新增的那个 USB 网口通常叫 `enx...`（后面跟 MAC 地址）或 `eth1`。和笔记本那边连的是同一根线。

**怎么判断哪个是新增的？** 跑 `ip link show` 前后对比——多出来的那个就是。

---

## 五、Step 2：配置静态 IP 与固化

### 为什么需要静态 IP

网线直连没有 DHCP 服务器（不像连路由器那样自动分配 IP）。两张网卡如果没配 IP，物理层虽然通了，但 IP 层没有地址，无法通信。你需要**手动给两张网卡分配同一子网的 IP**。

### 5.1 笔记本（Windows）

1. 控制面板 → 网络和共享中心 → 更改适配器设置
2. 找到对应的"以太网"适配器 → 右键 → 属性
3. 双击 **Internet 协议版本 4 (TCP/IPv4)**
4. 选"使用下面的 IP 地址"：

| 字段 | 值 |
|------|-----|
| IP 地址 | `10.0.0.2` |
| 子网掩码 | `255.255.255.0` |
| 默认网关 | **留空** |
| DNS | **留空** |

> Windows 控制面板的设置是**持久化**的，重启不会丢。

### 5.2 主机（Ubuntu Desktop）

```bash
# 列出所有网卡连接
nmcli connection show

# 找到新增 USB 网口的连接名（如 "有线连接 1" 或 "enx0826ae39bae5"）
```

```bash
# 配静态 IP、禁用 DHCP、设定连接名
sudo nmcli connection modify "enx0826ae39bae5" \
  ipv4.method manual \
  ipv4.addresses 10.0.0.1/24 \
  ipv4.gateway "" \
  connection.autoconnect yes

# 激活
sudo nmcli connection up "enx0826ae39bae5"
```

> nmcli 是 NetworkManager 的命令行工具。`connection.modify` 写入的配置是**持久化**的，重启不变。

**命令解释**：

| 参数 | 含义 |
|------|------|
| `ipv4.method manual` | 手动配 IP，不找 DHCP |
| `ipv4.addresses 10.0.0.1/24` | IP + 子网掩码（/24 = 255.255.255.0） |
| `ipv4.gateway ""` | 不设网关——同一子网不需要 |
| `connection.autoconnect yes` | 开机自动连接 |

### 5.3 解决 Windows 防火墙单向 ping 通

如果"笔记本能 ping 主机，但主机 ping 不通笔记本"——这是 Windows 防火墙默认禁止入站 ping。在笔记本 PowerShell（管理员）里：

```powershell
New-NetFirewallRule -DisplayName "Allow ICMPv4-In" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow
```

> ICMPv4 Type 8 就是 Echo Request（ping 请求）。这条规则允许外部设备 ping 你的笔记本，规则持久保存。

### 5.4 验证

```bash
# 主机 ping 笔记本
ping 10.0.0.2

# 笔记本 ping 主机
ping 10.0.0.1

# 双向通 = 网络层 OK
```

---

## 六、Step 3：安装 Docker

### Docker 是什么

Docker 是一个**进程级隔离平台**。和虚拟机的区别：

| | 虚拟机 | Docker |
|------|--------|--------|
| 隔离层 | 硬件虚拟化，每个 VM 有自己的 OS 内核 | 进程隔离，共享宿主机内核 |
| 启动速度 | 几十秒到几分钟 | 毫秒级 |
| 磁盘占用 | 每个 VM 几 GB | 镜像几十到几百 MB |
| 适用场景 | 完全隔离的环境 | 应用打包 + 快速部署 |

**三个核心概念**：

| 概念 | 类比 | 说明 |
|------|------|------|
| 镜像 (Image) | 软件安装包 | 包含应用 + 所有依赖的只读模板 |
| 容器 (Container) | 正在运行的程序 | 镜像的运行实例，有独立的文件系统和网络 |
| 卷 (Volume) | 外接硬盘 | 把宿主机目录挂载到容器内，容器删了数据还在 |

### 6.1 换 apt 源（GFW 环境必须）

```bash
sudo sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list
sudo apt update
```

> 如果之前没换过 apt 源，后续 `apt install` 会非常慢或超时。

### 6.2 安装 Docker

```bash
sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker $USER
```

> 不要用 `curl get.docker.com | sh`——这个域名在国内被阻断。
> `docker.io` 是 Ubuntu 官方维护的 Docker 包，功能一致，走国内 apt 镜像。
> `docker-compose-v2` 是 `docker compose` 命令的插件（不是旧版 `docker-compose`）。

**`sudo usermod -aG docker` 在做什么**：把当前用户加入 `docker` 组。Docker daemon 的 socket（`/var/run/docker.sock`）只允许 `docker` 组的用户访问。不加组的话每次 `docker ps` 都要加 `sudo`。

> ⚠️ 加入组后当前终端可能不会立即生效。VSCode SSH 连接需要断开重连一次。

### 6.3 配置 Docker 镜像加速

```bash
sudo nano /etc/docker/daemon.json
```

写入：

```json
{
  "registry-mirrors": [
    "https://docker.1panel.live",
    "https://dockerpull.com"
  ]
}
```

```bash
sudo systemctl restart docker
```

**原理**：当你 `docker pull gitea/gitea` 时，Docker daemon 先去镜像站查有没有缓存。有缓存就直接从这里拉（国内速度），没有再回 Docker Hub 拉。

> ⚠️ `/etc/docker/daemon.json` 需要 root 权限写入。VSCode 的文件编辑器用的是普通用户，写不了。在 VSCode 终端（Ctrl+`）里用 `sudo nano`。

### 6.4 验证

```bash
docker run --rm hello-world
```

看到 "Hello from Docker!" 就是装好了。

### 6.5 长记性：VSCode SSH 连 Docker 主机

如果你用 VSCode Remote-SSH 连主机，`newgrp docker` 对 SSH 会话不生效。断开 VSCode SSH 重新连一次即可——新的 SSH 登录会自动读取 `docker` 组权限。

---

## 七、Step 4：部署 Gitea（代码仓库）

### 为什么是 Gitea

代码不能上传公网（公司规定），需要在主机自建 Git 托管。

| 选项 | 资源消耗 | 复杂度 | 结论 |
|------|----------|--------|------|
| GitLab | 最低 4GB 内存 | 高 | ❌ 太重 |
| Gitea | ~100MB 内存，单二进制 | 低 | ✅ 个人项目首选 |
| Gogs | 与 Gitea 同源但更新慢 | 低 | ❌ Gitea 是更好的 fork |

### 7.1 准备目录和 compose 文件

```bash
sudo mkdir -p /data/gitea /data/jenkins
sudo chown -R $USER:$USER /data/gitea /data/jenkins
mkdir -p ~/cicd
nano ~/cicd/docker-compose.yml
```

写入以下内容：

```yaml
name: lubancat-cicd

services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    restart: unless-stopped
    ports:
      - "3000:3000"   # Web UI
      - "2222:22"     # SSH git
    volumes:
      - /data/gitea:/data
    environment:
      - GITEA__server__DOMAIN=10.0.0.1
      - GITEA__server__SSH_DOMAIN=10.0.0.1
      - GITEA__server__ROOT_URL=http://10.0.0.1:3000
    networks:
      - ci-network

  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - /data/jenkins:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - JAVA_OPTS=-Xmx1024m
    networks:
      - ci-network

networks:
  ci-network:
    driver: bridge
```

### 逐配置详解

**`ports`（端口映射）**

```
"宿主机端口:容器内端口"

"3000:3000"  外面访问 10.0.0.1:3000 → 转发到容器内 Gitea 的 3000 端口
"2222:22"    外面访问 10.0.0.1:2222 → 转发到容器内 Gitea 的 22 端口(SSH)
             ↑ 用 2222 是因为主机自己的 SSH 已经占了 22 端口
```

**`volumes`（卷挂载）**

```
"/data/gitea:/data"   宿主机的 /data/gitea 映射为容器内的 /data
                      Gitea 的仓库、数据库、日志全在 /data 下
                      容器删了，/data/gitea 还在，数据不丢
```

> 容器是无状态的——删除容器后内部所有改动丢失。只有挂载到宿主机目录的数据才能持久化。升级 Gitea 时：删旧容器 → 拉新镜像 → 挂载同一个 `/data/gitea` → 所有仓库和配置都在。

**`networks: ci-network`**

```
同一 network 下的容器可以用容器名直接通信：
  Jenkins 容器内 ping gitea → 通
  Jenkins 容器内 curl http://gitea:3000 → 通
  
不需要经过主机 IP 和端口映射，Docker 内建 DNS 解析容器名到 IP。
```

**`environment`（环境变量）**

```yaml
GITEA__server__DOMAIN=10.0.0.1
#  Gitea 配置的 [server] 段
#  __ 是层级分隔符
#  这行 = 在 Gitea 配置文件里写 [server] DOMAIN = 10.0.0.1
```

这三个变量预设了 Gitea 的域名和 URL。跳过首次启动时需要手动填写。

**`restart: unless-stopped`**

```
主机重启后 Docker 自动拉起容器
"unless-stopped" = 除非你手动 docker stop 它，否则永远自动重启
```

**`/var/run/docker.sock:/var/run/docker.sock`**（Jenkins 用）

```
把宿主机的 Docker 套接字"借"给 Jenkins 容器
Jenkins 容器内没装 Docker，但通过这个 socket 可以操控宿主机的 Docker
流水线里 docker build → 实际在宿主机上跑
```

### 7.2 启动 Gitea

```bash
cd ~/cicd
docker compose up -d gitea
docker ps   # 确认 STATUS 是 Up
```

### 7.3 初始化 Gitea

浏览器打开 `http://10.0.0.1:3000`，你会看到初始配置页面。**只改两处**：

**① SSH 端口：改成 `2222`**

原因：容器的 22 映射到宿主机 2222（主机 SSH 已占用 22）。如果这里写 22，clone 地址会缺端口号，git 客户端默认连 22 连不上。

**② 滚动到底部，设置管理员账号**

| 字段 | 填什么 |
|------|--------|
| 用户名 | 你的名字拼音 |
| 密码 | 自己设（记住） |
| 邮箱 | 常用邮箱 |

> ⚠️ 第一个注册的用户自动成为管理员。如果跳过这步，之后要手动改数据库才能添加管理员。

其他字段全保持默认。点 **安装 Gitea**。

---

## 八、Step 5：部署 Jenkins（CI 引擎）

### 为什么是 Jenkins

- CI/CD 行业标准，秋招简历加分项
- Pipeline as Code（Jenkinsfile 随代码一起管理）
- 自建，不依赖 GitHub/GitLab
- 丰富的插件生态

### 8.1 启动 Jenkins

```bash
cd ~/cicd
docker compose up -d jenkins
```

### 8.2 解锁

打开 `http://10.0.0.1:8080`。需要解锁密码：

```bash
cat /data/jenkins/secrets/initialAdminPassword
```

复制输出，粘贴。

### 8.3 安装插件

选 **Install suggested plugins**，等待完成。

### 8.4 创建管理员

设置用户名和密码（可以和 Gitea 一样，好记）。

---

## 九、Step 6：笔记本 ↔ Gitea SSH 链路

### 9.1 理解：为什么 SSH 在这段能用

| 链路 | 方式 | 为什么 |
|------|------|--------|
| 笔记本 → Gitea | SSH | 笔记本装的是原生 OpenSSH（C 语言实现），ED25519 密钥支持完善 |
| Jenkins → Gitea | HTTP（非 SSH）| Jenkins 的 Java SSH 库对 ED25519 格式不兼容 → 后面会用 HTTP |

### 9.2 生成 SSH 密钥（笔记本）

```powershell
ssh-keygen -t ed25519 -C "yourname@lubancat-ci"
```

一路回车（不设密码短语）。

> `-t ed25519`：ED25519 是目前最推荐的 SSH 密钥类型——比 RSA 更短、更快、更安全。

### 9.3 添加公钥到 Gitea

```powershell
cat ~/.ssh/id_ed25519.pub
```

复制输出的整行（以 `ssh-ed25519` 开头）。

打开 `http://10.0.0.1:3000` → 右上角头像 → 设置 → SSH/GPG 密钥 → 增加密钥 → 粘贴 → 添加。

### 9.4 验证 SSH 链路

在 Gitea 创建一个测试仓库（`http://10.0.0.1:3000` → 右上角 `+` → 新建仓库 → 名称 `test`）。

```powershell
git clone ssh://git@10.0.0.1:2222/你的用户名/test.git
```

第一次连接会问 `yes/no`，输入 `yes`。看到 "cloned an empty repository" 就通了。

### 9.5 理解：`ssh://git@10.0.0.1:2222` 各部分含义

```
ssh://git@10.0.0.1:2222/wangzhongqi/test.git
  │     │       │     │         │
  │     │       │     │         └── 仓库路径
  │     │       │     └── 端口号（Docker 映射的 2222 → 容器:22）
  │     │       └── 主机 IP（私有子网地址）
  │     └── 用户名（Gitea 容器内用 git 用户运行）
  └── 协议（SSH = 加密的 Git 传输）
```

---

## 十、Step 7：Jenkins ↔ Gitea 集成

### 10.1 "为什么不用 SSH"——一份完整诊断

**我们尝试了 SSH，三次失败**：

**第一次："Host key verification failed"**

原因：Jenkins 容器的 `~/.ssh/known_hosts` 里没有 `10.0.0.1:2222` 的指纹。笔记本第一次连也会弹 `yes/no` 确认，你手动点了。Jenkins 没人帮它点。

临时解决：关掉 Strict Host Key Checking。后面还有问题。

**第二次："error in libcrypto"**

原因：Jenkins 用的是 J**ava SSH 库**（JSch 或 Mina SSHD），不是系统的 OpenSSH。某些旧版 Java SSH 库无法正确解析 ED25519 格式的私钥。`ssh-keygen -t ed25519` 生成的密钥，Java 不认。

**第三次："Permission denied (publickey)"**

原因：第二次错误导致私钥根本没加载成功。认证时 Jenkins 没有任何可用身份，Gitea 拒绝连接。

**所以选择 HTTP**：同一 Docker 网络内，HTTP 是容器间通信的标准方式。不涉及密钥文件解析，直接用用户名+密码认证。

### 10.2 创建测试 Jenkinsfile

在笔记本 `test` 仓库目录里：

```powershell
Set-Content -Path Jenkinsfile -NoNewline -Value @"
pipeline {
    agent any
    stages {
        stage('Hello') {
            steps {
                echo 'Hello from Jenkins! Pipeline works!'
            }
        }
    }
}
"@

git add Jenkinsfile
git commit -m "add Jenkinsfile"
git push origin HEAD:main
```

> ⚠️ 用 `Set-Content` 而不是 `Out-File`——PowerShell 的 `Out-File` 默认写 BOM（文件头不可见字符），会导致 Jenkins 无法识别 `pipeline` 关键字。错误信息为 `No such DSL method '﻿pipeline'`。

### 10.3 创建 Jenkins 任务

Jenkins 首页 → 新建任务 → 名称 `test-pipeline` → **Pipeline** → OK。

**Pipeline 区域配置**：

| 字段 | 值 |
|------|-----|
| Definition | `Pipeline script from SCM` |
| SCM | `Git` |
| Repository URL | `http://gitea:3000/你的用户名/test.git` |
| Branches to build | `*/main` |

> ⚠️ 注意：Repository URL 用 `http://gitea:3000`（容器名），不用 `http://10.0.0.1:3000`。Jenkins 和 Gitea 同在 `ci-network` 里，容器名直连更快且不需要经过 Docker 端口映射。

**Credentials → Add → Jenkins**：

| 字段 | 值 |
|------|-----|
| Kind | `Username with password` |
| Username | Gitea 用户名 |
| Password | Gitea 密码 |
| ID | `gitea-cred` |

### 10.4 测试

保存 → **Build Now**。左侧点进构建号 → **Console Output**，应该看到：

```
Hello from Jenkins! Pipeline works!
```

### 10.5 常见 Jenkinsfile 错误

| 错误 | 原因 | 解决 |
|------|------|------|
| `No such DSL method '﻿pipeline'` | 文件开头有 BOM 字符 | 用 `Set-Content` 代替 `Out-File` |
| `No such property: any` | `pipeline` 前有前导空格 | pipeline 必须在行首 |
| `couldn't find remote ref refs/heads/master` | 仓库主分支是 `main` 不是 `master` | Jenkins 配置中 Branches 改成 `*/main` |
| 构建成功但内容不对 | push 没实际生效 | 检查 Git 远程分支是否真的更新了 |

### 10.6 理解 Git push 的坑

**Git 的三层模型**：

```
工作目录 ──(add)──→ 暂存区 ──(commit)──→ 本地仓库 ──(push)──→ 远程仓库
```

- `git commit` 只改本地，`git push` 才发到 Gitea
- 本地分支名 `master` 和远程 `main` 不一致时，`git push` 不自动工作
- 用 `git push origin HEAD:main` 明确指定"把我当前分支推到远程 main"
- 永久解决：`git branch --set-upstream-to=origin/main master`

---

## 十一、Step 8：Webhook 自动触发

### 11.1 问题：Webhook 调用链

```
笔记本 git push → Gitea 收到推送 → 需要主动通知 Jenkins
                                    │
                                    ├── CSRF 保护（Jenkins 安全机制）
                                    ├── 认证要求（不能匿名调用）
                                    └── ALLOWED_HOST（Gitea 安全策略）
```

### 11.2 允许 Gitea 访问 Jenkins 容器

编辑 `~/cicd/docker-compose.yml`，在 Gitea 的 `environment` 里加一行：

```yaml
      - GITEA__webhook__ALLOWED_HOST_LIST=jenkins,10.0.0.1,localhost
```

重启 Gitea：`docker compose up -d gitea`

> Gitea 默认禁止 Webhook 访问私有 IP 范围（包括 Docker 内网 `172.x.x.x`）。这一行白名单了 `jenkins` 这个容器名。

### 11.3 关闭 Jenkins CSRF 保护

打开 Jenkins Script Console（`http://10.0.0.1:8080/manage` → **Script Console**），运行：

```groovy
jenkins.model.Jenkins.instance.setCrumbIssuer(null)
```

> Jenkins 的 CSRF 保护要求每个 POST 请求带一个 token（crumb），但 Gitea Webhook 不会带。关掉在这个私有网络环境里没有安全问题——Jenkins 只在 `10.0.0.x` 私有子网内可见，外部无法访问。

### 11.4 配置 Jenkins 远程触发

打开任务配置页面 → **Build Triggers** → 勾选 **触发远程构建 (例如,使用脚本)** → Token 填 `lubancat`。

### 11.5 生成 Jenkins API Token

打开 `http://10.0.0.1:8080/user/你的用户名/configure` → **Add new Token** → 名称 `gitea-webhook` → Generate → **立即复制**。

### 11.6 配置 Gitea Webhook

打开 `http://10.0.0.1:3000/用户名/test/settings/hooks` → 添加 Webhook → Gitea：

| 字段 | 值 |
|------|-----|
| 目标 URL | `http://用户名:API_Token@jenkins:8080/job/test-pipeline/build?token=lubancat` |
| HTTP 方法 | POST |
| 触发器 | Push 事件 |

> URL 格式：`http://用户:密码@主机/路径` 是 HTTP Basic Auth 的标准写法。Gitea 在 POST 时会带上这个身份，Jenkins 就知道是谁在调用。

### 11.7 验证

```powershell
# 随便改一下 Jenkinsfile
git add Jenkinsfile
git commit -m "trigger webhook"
git push origin HEAD:main
```

推完之后 Jenkins 应该自动开始构建。去 `http://10.0.0.1:8080/job/test-pipeline` 确认新构建自动出现。

> ⚠️ API Token 有过期时间。过期后 Gitea Webhook 会重新弹 403。到期前重新生成 Token 并更新 Webhook URL。

---

## 十二、故障排查索引

| 故障现象 | 可能原因 | 解决方式 |
|----------|----------|----------|
| 笔记本 ↔ 主机 ping 不通 | 网线没插好 / IP 没配 / 不在同一子网 | 检查网卡状态 `ip link`，检查 IP `ip addr` |
| 笔记本能 ping 主机，反向不通 | Windows 防火墙拦截入站 ICMP | 加防火墙规则（Step 2） |
| `apt install` 超时 | apt 源是 Ubuntu 官方（海外） | 切阿里云镜像（Step 3） |
| `docker pull` 超时 | Docker Hub 被墙 | 配镜像加速器（Step 3） |
| `curl get.docker.com` 连接被重置 | 脚本地址被阻断 | 用 `apt install docker.io` |
| VSCode 写入 `/etc/` 无权限 | 编辑器用普通用户 | 终端里 `sudo nano` |
| `docker run` permission denied | 用户不在 docker 组 | 重连 SSH |
| Gitea clone 报 "Cannot find repository" | 仓库还没创建 / 用户名拼错 | 在 Gitea Web UI 确认仓库存在 |
| Jenkins 构建报 `No such DSL method '﻿pipeline'` | Jenkinsfile 文件有 BOM | 用 `Set-Content` 而非 `Out-File` 写文件 |
| Jenkins 构建报 `No such property: any` | `pipeline` 关键字前有空格 | Jenkinsfile 里 pipeline 必须顶格 |
| Jenkins 构建报 `couldn't find remote ref` | 分支名不匹配（master vs main） | Jenkins 配置 Branches 改成 `*/main` |
| git push 后远程没更新 | `git push` 没实际推（分支名不一致） | `git push origin HEAD:main` |
| Webhook 报 `ALLOWED_HOST_LIST` | Gitea 禁止访问 Docker 内网 IP | 加环境变量（Step 8） |
| Webhook 报 `No valid crumb` | Jenkins CSRF 保护 | Script Console 关闭（Step 8） |
| Webhook 报 `Authentication required` | Gitea 没带认证去调 Jenkins | 配上 API Token URL（Step 8） |

---

## 十三、概念速查表

### 网络

| 概念 | 一句话 | 在这项目里 |
|------|--------|-----------|
| IP 地址 | 网络上的门牌号 | 笔记本 `10.0.0.2`，主机 `10.0.0.1` |
| 子网掩码 | 判断"谁跟我在同一栋楼" | `/24` = `255.255.255.0`，`10.0.0.x` 全在同一子网 |
| 网关 | "不属于本栋楼的都扔给它" | 网线直连不走网关 |
| DHCP | 自动分配 IP 的服务 | 网线直连没有 DHCP，所以必须手动配静态 IP |
| VLAN | 把一个物理交换机切成多个逻辑隔离网络 | 公司 WiFi 被 VLAN 隔开，笔记本和主机不能通过 WiFi 互访 |
| ARP | IP→MAC 地址翻译官 | 只在同一子网内有效 |

### Docker

| 概念 | 一句话 |
|------|--------|
| 镜像 | 包含应用 + 所有依赖的只读模板 |
| 容器 | 镜像的运行实例，有独立文件系统和网络 |
| 端口映射 `"3000:3000"` | 宿主机端口 → 容器内端口 |
| 卷挂载 `/data:/data` | 宿主机目录 → 容器内目录，持久化数据 |
| Docker 网络 | 同一网络的容器可用容器名直接通信 |
| `docker.sock` | 借给容器操控宿主机 Docker 的套接字 |

### Git

| 概念 | 一句话 |
|------|--------|
| `git add` | 把改动装进暂存区 |
| `git commit` | 把暂存区打包成一个版本 |
| `git push` | 把新版本发到远程仓库 |
| `origin` | 远程仓库的缩写名 |
| `HEAD:main` | "把我当前分支推到远程 main 分支" |

---

> 最后更新：2026.6.10
> 基于真实搭建过程（Phase 1）的全部试错经验编写
