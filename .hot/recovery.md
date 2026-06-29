# Session Handoff | cicd
> Last: 2026-06-29 18:00 | Session: 982a358f-57e9-4083-ba33-c816b84f49e3

## Session Summary

pollSCM 放弃 → cron + git ls-remote 变更检测 → 端到端验证通过 → 磁盘治理完成。

### 最终架构
```
触发:
  main    → cron 12:00/17:00 (TimerTrigger) → git ls-remote 变更检测 → 全编 8.5min
  feature → Gitea webhook push → os-feature 增量编译 ~3min

workspace:
  /data/os-workspace/           ← main 全编 (33G)
  /data/os-workspace-feature/   ← feature 增量 (8.3G)

构建:
  os-builder Docker → --user 1000:1000 --group-add 6 --privileged → ci-build.sh → update.img
```

### 关键决策
- ❌ pollSCM → Pipeline + lightweight checkout 根本不可用 (JENKINS-46431, 0ms bug)
- ✅ cron + `git ls-remote` 变更检测 → 定时检查 + 有变更才构建
- ❌ main 分支 webhook 删除 → main=定时产出, feature=快速验证
- ✅ `--group-add 6` → 主机重启后 loop 设备权限修复
- ✅ `SHOULD_BUILD` 替代 `HAS_CHANGES` → environment{} 不初始化，避免 when 被覆盖
- ✅ 构建产物自动清理 → post{always} 保留最新 3 个 img + 磁盘 >90% 告警
- ✅ 磁盘 81% 是基准容量（SDK 源码 33G），不是泄漏

### 已验证
- [x] cron 触发 "Started by timer" (15:56, 17:00)
- [x] 变更检测 + 无变更跳过 + 有变更全编
- [x] 端到端: feature 分支 → 全编(25min) → 增量(3min, 8x) → merge main → 17:00 cron → update.img 3.6G
- [x] Webhook: push feature 触发 os-feature, push main 不触发 os-main
- [x] 磁盘: 100%→81%, 自动清理已就位
- [x] 9/9 build stages 全部通过

📋 [决策: pollSCM→cron 迁移完成, webhook main 回滚, 磁盘自动清理就位, e2e 验证通过 | 待办: 无]
