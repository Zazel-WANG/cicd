# CI/CD 基础设施搭建学习笔记

> 日期：2026.6.9 - 6.10
> 阶段：Phase 1 基础设施固化与服务部署
> 目的：记录整个搭建过程中的概念理解、问题诊断和解决方案

---

## 一、Docker 是什么？

### 一句话

Docker 是一个**进程级隔离平台**，让应用跑在独立的"壳"里，共享宿主机内核。

### 容器 vs 虚拟机

```
虚拟机：每个 VM 有自己的 OS 内核，隔离在硬件层 → 几个 GB 起步，启动几十秒
容器：  所有容器共享宿主机内核，隔离在进程层 → 几十 MB 起步，启动毫秒级
```

### 核心概念

| 概念 | 类比 | 说明 |
|------|------|------|
| 镜像 (Image) | 软件安装包 | 包含应用+所有依赖的只读模板 |
| 容器 (Container) | 正在运行的程序 | 镜像的运行时实例，有独立的文件系统、网络、进程空间 |
| Dockerfile | 组装说明书 | 定义如何从零构建镜像 |
| docker-compose.yml | 组合食谱 | 定义多个容器如何协同工作 |
| 卷 (Volume) | 外接硬盘 | 把宿主机目录挂载到容器内，容器删了数据不丢 |

### 为什么"下载下来就能用"

Gitea 的例子：

```
Gitea 维护者做了：
  1. 编译 Gitea 二进制
  2. 写 Dockerfile：
     FROM alpine          ← 从极简 Linux 开始
     RUN apk add git sqlite  ← 装依赖
     COPY gitea /usr/bin/   ← 把二进制放进去
     ENTRYPOINT ["gitea"]   ← 启动时执行
  3. 打包成镜像，上传 Docker Hub

你跑 docker compose up 时：
  拉镜像 → 启动容器 → 容器里 Gitea + Git + SQLite 全有了
  不需要自己 apt install、解决依赖链
```

### 关键约束

- 容器默认有独立的网络栈（自己的 IP、端口）
- 容器间用 `docker network` 互联
- 容器内不可见宿主机的文件（除非挂载 volume）
- 容器内不可见宿主机的 SSH agent、socket（除非挂载 `/var/run/docker.sock`）

---

## 二、Git 的三层模型

### 核心理解

Git 是**分布式**版本控制——本地和远程是两个独立的仓库。

```
工作目录          暂存区           本地仓库          远程仓库
(你的文件)  →   (git add)  →   (git commit)  →  (git push)
                "装进篮子"      "贴标签封箱"     "寄到 Gitea"
```

### 每次 push 到底发生了什么

```
1. git add Jenkinsfile
   → 计算文件内容哈希，放入 .git/objects/
   → 更新暂存区索引

2. git commit -m "..."
   → 把暂存区的内容打包成一个 commit 对象
   → commit 包含：作者、时间、提交信息、文件树快照
   → 本地 HEAD 指针移动到新 commit

3. git push origin main
   → 把本地 commit 对象发送到远程
   → 更新远程的 main 分支指针
```

### 分支名不一致（master vs main）

- Git 旧版默认创建 `master` 分支
- Gitea/GitHub 新仓库默认是 `main`
- 两者只是名字不同，本质一样
- 推送时需要用 `HEAD:main` 或设置 upstream

### 踩过的坑

| 现象 | 原因 | 解决 |
|------|------|------|
| push 后提示"upstream branch does not match" | 本地 master 推送到远程 main，名字不一致 | `git push origin HEAD:main` |
| push 后远程没更新 | 看到提示以为是错误，实际 Git 根本没推 | 确认 `git push` 成功，或设置 upstream |
| `Changes not staged for commit` | 文件改了但没 `git add`，不在暂存区 | 先 add 再 commit |

---

## 三、四大网络链路

### 链路地图

```
笔记本 10.0.0.2 (Windows)
   │    │    │
  ①│   ④│    │
   │    │    │
   ▼    ▼    │
  ┌──────────┴──────────────────────────────────────┐
  │              主机 10.0.0.1 (Ubuntu)               │
  │                                                  │
  │  Docker 端口映射: 2222:22, 3000:3000, 8080:8080   │
  │                                                  │
  │  ┌─────────────── ci-network ────────────────┐   │
  │  │       ②                                     │   │
  │  │  Gitea ◄──────────── Jenkins               │   │
  │  │  :3000    HTTP       :8080                 │   │
  │  └────────────────────────────────────────────┘   │
  │                                                  │
  └─────────────┬────────────────────────────────────┘
                │
               ③│ WiFi → 外网（apt, docker pull）
                │
```

### 链路①：笔记本 → Gitea（git push）

- **协议**：SSH（`ssh://git@10.0.0.1:2222`）
- **认证**：SSH 密钥对（笔记本私钥 + Gitea 公钥）
- **路径**：笔记本网口 → 网线 → 主机 USB 网口 → Docker NAT 2222 → Gitea 容器:22
- **为什么 SSH 通**：笔记本用的是原生 OpenSSH（C 实现），ED25519 密钥支持完美

### 链路②：Jenkins → Gitea（拉代码构建）

- **协议**：HTTP（`http://gitea:3000/wangzhongqi/test.git`）
- **认证**：用户名 + 密码
- **路径**：Jenkins 容器 → ci-network 虚拟交换机 → Gitea 容器（全程容器内）
- **SSH 失败原因**：见第五部分

### 链路③：主机 → 外网

- 主机 WiFi 直接上网
- 用途：`apt install`、`docker pull`
- 加速策略：apt 换阿里云源，Docker 配国内镜像加速器

### 链路④：笔记本浏览器 → Web 界面

- Gitea：`http://10.0.0.1:3000`
- Jenkins：`http://10.0.0.1:8080`
- 路径：笔记本 → 网线 → 主机 Docker 端口映射 → 对应容器

---

## 四、docker-compose.yml 配置解析

### 端口映射

```yaml
ports:
  - "3000:3000"
```

格式：`"宿主机端口:容器内端口"`。

容器有自己的网络栈，外部无法直接访问容器内的端口。Docker 在宿主机上开一个监听端口，收到的流量转发到容器内对应端口。

### 卷挂载

```yaml
volumes:
  - /data/gitea:/data
```

格式：`"宿主机路径:容器内路径"`。

容器是无状态的——删除容器后内部数据全丢。卷把数据落到宿主机磁盘上，删容器重建也不丢。

### Docker 网络

```yaml
networks:
  ci-network:
    driver: bridge
```

`bridge` 创建一个虚拟交换机。同一网络中的容器可以用**容器名**直接互相访问（Docker 内建 DNS 解析容器名到 IP），不经过宿主机网卡。

### docker.sock 挂载

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

把宿主机的 Docker 套接字"借"给 Jenkins 容器。Jenkins 容器内没有 Docker 守护进程，但通过这个 socket 可以直接操控宿主机的 Docker，在宿主机上跑构建容器。

### 环境变量

```yaml
environment:
  - GITEA__server__DOMAIN=10.0.0.1
```

双下划线 `__` 是 Gitea 配置的命名约定。`GITEA__server__DOMAIN` 映射到 Gitea 配置文件的 `[server]` 段的 `DOMAIN`。在 docker-compose 里写就跳过了 Gitea 首次安装页面的手动填写。

---

## 五、Jenkins SSH 失败全诊断

### 问题 1：Host key verification failed

```
Jenkins 容器尝试 SSH 连接 10.0.0.1:2222
→ 容器的 ~/.ssh/known_hosts 里没有这个主机的指纹
→ SSH 严格模式拒绝连接
```

笔记本第一次连也弹了 yes/no 确认，但你手动点了 yes。Jenkins 没人帮它点。

### 问题 2：error in libcrypto

```
Jenkins 加载 ED25519 私钥
→ Jenkins 用的是 Java SSH 库（JSch / Mina SSHD）
→ 这些库对 ED25519 格式的解析存在兼容性问题
→ 密钥加载失败
```

### 问题 3：Permission denied (publickey)

```
SSH 认证阶段
→ 因为问题2，私钥根本没加载成功
→ Jenkins 没有可用的身份凭证
→ Gitea 拒绝连接
```

### 为什么 HTTP 能用

| 对比维度 | SSH | HTTP |
|----------|-----|------|
| 密钥处理 | Java SSH 库解析 ED25519 → 不兼容 | 不涉及密钥文件，只用用户名+密码 |
| 网络路径 | 需经过主机端口映射（gitea → 10.0.0.1 → 2222 → 容器:22） | 容器间 `ci-network` 直连 |
| 认证复杂度 | 非对称加密（公私钥） | Basic Auth（用户名密码） |
| 容器间通信 | SSH 在容器间不太自然 | HTTP 是容器间通信的标准方式 |

**核心教训**：
1. Java 生态的 SSH 库 ≠ OpenSSH，密钥格式兼容性是老坑
2. 同一 Docker 网络内的容器间通信，HTTP 比 SSH 更自然
3. 遇到 `libcrypto` 错误，不要折腾密钥格式——直接切 HTTP

---

## 六、GFW 环境下的 Docker 部署策略

### apt 加速

```bash
sudo sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list
```

### Docker 镜像加速

```json
// /etc/docker/daemon.json
{
  "registry-mirrors": [
    "https://docker.1panel.live",
    "https://dockerpull.com"
  ]
}
```

原理：镜像站定期同步 Docker Hub，你在墙内拉镜像时从镜像站的缓存拿。

### 当加速也无效时

`curl get.docker.com` 被 GFW 阻断 → 改用 `apt install docker.io`（Ubuntu 自带源，走阿里云镜像）。

---

## 七、CI/CD 架构决策记录

| 决策 | 选型 | 理由 |
|------|------|------|
| Git 托管 | Gitea (Docker) | 代码不能上公网；Gitea 轻量（100MB vs GitLab 4GB） |
| CI 引擎 | Jenkins (Docker) | 行业标准，秋招加分；Pipeline as Code |
| 部署方式 | Docker Compose | 服务编排简单；一个文件描述所有服务关系 |
| Gitea ↔ Jenkins | HTTP (非 SSH) | 同 Docker 网络内 HTTP 更简单；避免 Java SSH 兼容性问题 |
| 网络 | 私有子网 10.0.0.0/24 | 绕过公司 VLAN 隔离；网线直连零中间设备 |
| 持久化 | Docker Volume | 容器无状态，数据不丢 |

---

## 八、当前状态与后续

### 已通链路

- [x] 笔记本 ↔ 主机（ping 双向通）
- [x] 笔记本 ↔ Gitea（git push 成功）
- [x] Jenkins ↔ Gitea（HTTP 拉代码成功）
- [x] 笔记本 ↔ Web 界面（Gitea :3000，Jenkins :8080）
- [x] Jenkinsfile 被正确解析并执行

### 待做

- [ ] Webhook 自动触发（目前手动 Build Now）
- [ ] 交叉编译流水线
- [ ] 部署到鲁班猫
