# OS CI/CD Bug/Debug 全记录

> 项目：LubanCat RK3588 嵌入式 OS 镜像 CI/CD 平台
> 日期：2026-06-25 ~ 2026-06-26
> 涉及组件：Jenkins, Docker, Gitea, Linux Kernel Build, repo, bash

---

## 总览

共遇到 **12 个 bug**，按调试顺序记录。每个 bug 包含现象、诊断过程、根因、解决方案、教训。

---

## Bug 1：rsync not found — Jenkins 容器缺少工具

**现象**：
```
rsync: not found
```

**诊断**：Jenkinsfile-feature 在 Jenkins agent 上直接跑 `rsync`。Jenkins 容器（Debian base）默认不含 rsync。

**根因**：Jenkins 容器精简，rsync 未预装。

**解决**：`docker exec -u root jenkins apt install -y rsync`

**教训**：Jenkins 容器 ≠ 开发环境。Runtime 依赖应在 `Jenkins.Dockerfile` 预装，而不是 `docker exec` 临时补。

---

## Bug 2：rsync error code 11 — 目标路径不存在

**现象**：
```
rsync -a --delete ${WORKSPACE}/ /data/os-workspace/kernel/
rsync: [Receiver] mkdir "/data/os-workspace/kernel" failed: No such file or directory (2)
rsync error: error in file IO (code 11)
```

**诊断过程**：最初怀疑 UID 权限问题 → 加了 `--user 1000:1000` → 仍然失败 → 在 Jenkins 容器内 `ls /data/` → `/data/` 目录不存在 → 确认 Jenkins 容器没挂载 `/data/os-workspace`。

**根因**：Jenkins 容器只挂载了 `/data/jenkins:/var/jenkins_home` 和 `docker.sock`。`/data/os-workspace/` 在主机上存在，但 Jenkins 容器内不可见。

**解决**：把 rsync 搬进 os-builder Docker 容器执行（该容器已挂载 `/data/os-workspace:/workspace`）。同时需要把 Jenkins workspace 也挂入容器：
```groovy
docker run --user 1000:1000 \
    -v /data/os-workspace:/workspace \
    -v ${WS_HOST}:/src:ro \
    os-builder:latest bash -c "rsync -a /src/ /workspace/kernel/"
```

**教训**：
- `sh` 块在 Jenkins agent 上执行，宿主机路径 ≠ 容器内路径
- 排查顺序：先确认路径是否存在，再考虑权限

---

## Bug 3：`| tail -N` 吞掉构建错误 → 假 SUCCESS

**现象**：
```
./build.sh extboot 2>&1 | tail -3
ERROR: Running build_extboot failed!
Finished: SUCCESS   ← 应该 FAILURE!
```

**诊断**：bash 管道 `cmd | tail` 的退出码来自最后一个命令（`tail`）。`tail` 总是 exit 0 → Jenkins 认为成功。

**根因**：`| tail -3` 是为了减少 Jenkins 日志量，但它也隐藏了错误退出码。

**解决**：所有 bash 脚本和 Jenkinsfile sh 块加 `set -eo pipefail`。`-o pipefail` 让管道中任一命令失败时整体失败。
```bash
set -eo pipefail
```

**教训**：
- 管道吞退出码是经典 bash 陷阱
- `tail` `grep` `tee` 等消耗性命令后面的东西都会继承它们的退出码
- CI 环境里日志完整性 > 日志简洁性

---

## Bug 4：python3 symlink Permission denied

**现象**：
```
ln: failed to create symbolic link '/usr/bin/python': Permission denied
ERROR: Running build_uboot failed!
```

**诊断**：`ci-build.sh` / Jenkinsfile-feature 运行时执行 `ln -sf /usr/bin/python3 /usr/bin/python`。容器以 UID 1000 运行，无权写 `/usr/bin/`。

**根因**：Plan D 统一 UID 1000 后，所有需要 root 权限的操作都必须在镜像构建时完成。

**解决**：移入 Dockerfile（构建时 root 执行）：
```dockerfile
RUN ln -sf /usr/bin/python3 /usr/bin/python
```

**教训**：区分"构建时"和"运行时"——前者 root，后者 UID 1000。`/usr/bin/`、`/etc/` 这类系统目录操作必须进 Dockerfile。

---

## Bug 5：`sudo mount` 需要 root — 统一 UID 冲突

**现象**：main 全编时 `build.sh` 在 rootfs 阶段调用 `sudo mount rootfs.img`，UID 1000 无权执行。

**诊断**：SDK 的 `build.sh` 用 `sudo mount/umount` 打包镜像。`--user 1000:1000` 后 `sudo` 需要密码。

**根因**：全编的 updateimg 步骤真需要 root（mount 系统调用）。

**解决**：Dockerfile 中创建 UID 1000 的 builder 用户 + NOPASSWD sudo：
```dockerfile
RUN useradd -u 1000 -m -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
```
所有 `docker run` 加 `--user 1000:1000`，feature 和 main 统一。

**安全评估**：个人内网 Jenkins，单用户，不暴露公网。`--privileged` 容器本身已等于 root。风险可接受。

**教训**：
- `--privileged` 给内核能力，UID 决定文件属主。两者独立
- `fakeroot` 可替代大部分 root 需求，但 `mount` 类操作必须真 root
- embed-hello 用 Jenkins Docker Pipeline 插件（自动 `-u 1000:1000`）避开了这个问题

---

## Bug 6：内核并行编译竞态（Mali GPU driver race）

**现象**：
```
make[5]: *** [drivers/gpu/arm/mali400/mali/built-in.a] Error 1
ar: mali_memory.o: No such file or directory
make[6]: *** [drivers/gpu/arm/midgard/...] Error 2
```

**诊断**：`make -j$(nproc)` (=6 核) 并行编译时，`ar` 打包 `built-in.a` 时子目录的 `.o` 还没编译完。

**根因**：LubanCat kernel 5.10.160 的 Mali GPU 驱动 Makefile 有依赖缺陷，高并行度触发竞态。

**解决**：`-j4` 代替 `-j$(nproc)`：
```bash
make ARCH=arm64 -j4
```

**教训**：
- 嵌入式 BSP 内核不一定能承受高并行编译
- 降并行度是最小代价的修复
- 同一项目不同 kernel tree 可能有不同的安全并发上限

---

## Bug 7：Git checkout 不保留文件时间戳 → make 全编

**现象**：每次 feature push 后，make 都重新编译全部 86000 个文件（~20 分钟），而不是增量编译改动的几个文件（预期 ~2 分钟）。

**诊断过程**：
1. 怀疑 `.o` 文件被 rsync `--delete` 删除 → 去掉 `--delete` → 无效
2. 怀疑 `rsync --size-only` 能解决 → 无效（文件大小相同时内容变化被丢弃）
3. 检查时间戳：`ls -la` 发现 `.c` 文件 mtime = NOW（git checkout 时间），`.o` 文件 mtime = PAST（上次构建时间）→ `.c` > `.o` → make 认为全部过期

**根因**：Git 不保留文件修改时间。`git checkout` 将所有文件 mtime 设置为当前时间。rsync 保留了这些"新"时间戳到 workspace → make 判断全部需要重新编译。

**尝试过的方案**：
| 方案 | 效果 | 问题 |
|------|------|------|
| `rsync -a` | 全编（默认） | git checkout mtime = NOW |
| `rsync --size-only` | 大部分跳过 | 改代码不改变大小时静默丢弃 |
| `rsync --checksum` | 正确 | 计算 86000 文件校验和 ~60 秒，可接受但非最优 |
| `git restore-mtime` | 恢复 git commit 时间戳 | pip 不可用（Python 3.8），curl 手动安装可行 |

**最终解决**：独立 workspace 方案（见 Bug 12）让问题自然消失。首次构建产生 `.o`，后续 rsync 只改变实际修改文件的时间戳，其余不变 → make 正确增量。

**教训**：
- Git + Make 的时间戳模型是 CI 系统的基础认知
- 不要试图 hack rsync 参数绕开时间戳问题——从架构层面隔离 workspace

---

## Bug 8：rsync 覆盖 gitfile → repo sync 失败

**现象**：
```
repo sync: /workspace/kernel/.git: unsupported checkout state
```

**诊断**：`sync-repos.sh` 用 `git init` + `git reset --hard` 绕过 repo 初始化，repo 期望 `.git/objects/` 是指向 `.repo/project-objects/` 的 symlink。修复为 gitfile 后，rsync 又把 Jenkins checkout 的 `.git/` 目录覆盖过来，导致 gitfile 变回普通 `.git` 目录。

**根因**：rsync 不加过滤，连 `.git/` 一起复制。

**解决**：
1. 修 gitfile：`echo "gitdir: /data/os-workspace/.repo/projects/kernel.git" > /data/os-workspace/kernel/.git`
2. rsync 排除 `.git`：`rsync -a --exclude='.git' /src/ /workspace/kernel/`
3. 最终方案：独立 workspace 彻底不需要 gitfile（见 Bug 12）

**教训**：rsync 是"无脑复制"，不会自动区分版本控制元数据和业务文件。

---

## Bug 9：repo sync 永远 NO CHANGE — manifest 不可达

**现象**：`ci-build.sh` 中 `repo sync --no-repo-verify` 每次都在 3 秒内 `NO CHANGE: 19f1be7`，从不触发全编。

**诊断**：manifest 指向 `https://github.com/LubanCat/manifests.git`。Docker 容器内 GitHub 不可达（GFW/网络）。`--no-repo-verify` 跳过网络验证，使用本地缓存的 manifest → manifest 永远不变。

**根因**：
1. GitHub 不可达 → manifest 永远不更新
2. pollSCM 已经在 kernel.git 上做了变更检测 → ci-build.sh 里的 repo sync 是重复逻辑
3. SDK 源码是一次性快照，不需要从上游更新

**解决**：砍掉 ci-build.sh 中全部 repo sync/git config/safe.directory 逻辑，只保留核心：
```bash
#!/bin/bash
set -eo pipefail
cd /workspace
./build.sh BoardConfig-LubanCat-3588-debian-xfce.mk
./build.sh
# archive... (见下方)
```

**教训**：pollSCM 已经是变更检测机制，不要在构建脚本里再做一遍。

---

## Bug 10：Shared workspace — feature 和 main 互相污染

**现象**：
1. Feature rsync 覆盖 kernel 源文件 → main 全编时 `scripts/Makefile.dtbinst` 等文件缺失
2. Main 全编（Docker root）产生 root 属主的 `.o` / `Image` → feature 的 rsync `--delete` 删不掉
3. 每次都要 `git checkout -- .` 或 `chown` 额外清理步骤

**诊断**：两个 pipeline 共享 `/data/os-workspace/kernel/`，通过不同机制（repo sync vs rsync）修改同一目录。任何一方的修改都是另一方的污染。

**根因**：架构设计缺陷——共享可变状态。

**尝试过的方案**：
| 方案 | 问题 |
|------|------|
| `chown -R` 每次 manually | 需要 sudo，不自动 |
| `git checkout -- .` 每次构建前 | 治标，增加构建时间 |
| `cp -al` 硬链接（方案 B） | 写入共享 inode，互相污染 |

**最终解决**：物理隔离 workspace（见 Bug 12）。

---

## Bug 11：Jenkins pollSCM 触发时间不匹配

**现象**：`H 12,17 * * *` 期望 12:00 和 17:00 整点触发，但 `H` 使分钟变为哈希值（如 12:34、17:51），观察不到"整点触发"。

**根因**：`H` = hash(job_name) → 在 0-59 之间固定但不透明的分钟数。

**解决**：改为 `0 12 * * *` 和 `0 17 * * *`（两行），整点触发：
```groovy
triggers { pollSCM('0 12 * * *\n0 17 * * *') }
```

**教训**：`H` 是为了多 job 环境避免负载尖峰，个人 Jenkins 不需要。

---

## Bug 12：最终架构 — 独立 workspace

**综合现象**：Bug 2/6/7/8/10 的根因都指向同一架构缺陷——两个 pipeline 共享可变状态。

**解决方案**：物理隔离。

```
/data/os-workspace/           ← main 全编专用（完整 SDK，pollSCM → build.sh → update.img）
/data/os-workspace-feature/   ← feature 增量专用（仅 kernel/ + .o，push → rsync → make -j4）
```

**实施**：
1. 主机 `cp -a /data/os-workspace/kernel /data/os-workspace-feature`（一次性，~7.7GB 含 .o）
2. Jenkinsfile-feature 挂载路径改为：
   ```groovy
   -v /data/os-workspace-feature:/workspace \
   -v /data/os-workspace/prebuilts:/workspace/prebuilts:ro \  # 工具链
   ```
3. ci-build.sh 精简为纯 build 逻辑

**效果**：

| 指标 | 修复前 | 修复后 |
|------|--------|--------|
| Feature 首次全编 | ~20min | ~22min（相当） |
| Feature 增量（改 1 个 .c） | ~20min（全编） | ~2.5min（真增量） |
| Main 全编 | 不可靠（文件缺失） | ~8.5min（可靠） |
| 额外清理步骤 | chown / git checkout / gitfile 修复 | **零** |

---

## 调试方法论总结

1. **分步最小化**：每次改一个变量，观察结果。不要修 A + B 一起测试。
2. **先确认存在性，再查权限**：`ls` → `stat` → `id` → `chown`
3. **日志不截断**：`| tail -N` 提速了开发？不，它让 debug 多花了 10 倍时间。
4. **现象归类**：多个 bug 指向同一个根因时，停止逐修，退回架构层思考。
5. **对照已知正常系统**：embed-hello 的 UID 模式、GiteaSCMSource 用法都是活样板。

## 文件变更轨迹

| 文件 | 关键变更 |
|------|----------|
| `workspace/os-build/Dockerfile` | +builder(UID 1000) + NOPASSWD sudo + python3 symlink + git config + git-restore-mtime |
| `workspace/os-build/Jenkinsfile-feature` | 全量重写 3 次：SDK build.sh → make ← 独立 workspace |
| `workspace/os-build/Jenkinsfile-main` | +`--user 1000:1000` |
| `workspace/os-build/ci-build.sh` | 从 repo sync + git config → 纯 build.sh + archive |
| `workspace/os-build/sync-repos.sh` | 一次性初始化脚本（已存档，不再使用） |
| kernel.git `Jenkinsfile` | 与 Jenkinsfile-main 同步 |
| kernel.git `Jenkinsfile-feature` | 与 Jenkinsfile-feature 同步 |
