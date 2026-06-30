# Session Handoff | cicd
> Last: 2026-06-30 09:30 | Session: 982a358f-57e9-4083-ba33-c816b84f49e3

## Session Summary

CI 部分全部完成。双通道触发、变更检测、全编/增量编译、磁盘治理全部验证通过。CI 重建指南已输出。

### 最终架构
```
触发:
  main    → cron 12:00/17:00 → git ls-remote 变更检测 → 全编 8.5min
  feature → Gitea webhook push → incremental make ~3min

workspace:
  /data/os-workspace/           ← main 全编 (33G)
  /data/os-workspace-feature/   ← feature 增量 (8.3G)

基础设施:
  Gitea (容器) + Jenkins (容器, /data 挂载, docker 组 124)
  os-builder (镜像, UID 1000, NOPASSWD sudo)
  docker-compose group_add 解决 Socket 权限

磁盘治理:
  post{always}: 保留最新 3 个 img + >90% 告警 + 自动清理
```

### 关键决策 (6/29-6/30)
- ❌ pollSCM → Pipeline + lightweight checkout 不可用 (JENKINS-46431)
- ✅ cron + git ls-remote 替代
- ❌ main webhook 删除 → main=定时产出
- ✅ /data 挂入 Jenkins → 替代 Docker-in-Docker
- ✅ group_add: ["124"] → Docker socket 权限
- ✅ df -h | awk 替代 df --output=pcent (避免转义)
- ✅ --group-add 6 证明不必要 (sudo mount 已覆盖)

### 已解决问题 (完整列表)
| Bug | 根因 | 修复 |
|-----|------|------|
| pollSCM 不触发 | Pipeline + lightweight checkout | cron + git ls-remote |
| 磁盘 100% | 构建产物无限堆积 | 自动清理(保留3)+监控 |
| loop 权限 | 磁盘满误诊, 实为磁盘满 | 删除旧 img |
| Shell 转义损坏 | ssh heredoc 三层转义 | scp 上传文件 |
| Docker socket 拒绝 | 容器重建丢失组权限 | group_add: ["124"] |
| 磁盘检查静默失败 | Jenkins 无 /data 挂载 | docker-compose + /data |

### 已验证 (端到端)
- [x] feature 全编 25min + 增量 3min (8x)
- [x] merge main → 17:00 cron → 全编 → update.img 3.6G
- [x] 无变更跳过 + 不发假通知
- [x] 磁盘检查 + 自动清理 (92%→88%)
- [x] 9/9 build stages 全部通过

📋 [CI 完成 | 输出: ci-rebuild-guide.md | 待办: CD (烧录+测试)]
