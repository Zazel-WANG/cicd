# Session Handoff | cicd
> Last: 2026-06-29 16:30 | Session: 982a358f-57e9-4083-ba33-c816b84f49e3

## Session Summary

pollSCM 对 Pipeline job 根本不可用（已知缺陷 JENKINS-46431），改用 `cron` + pipeline 内 `git ls-remote` 变更检测。主分支 webhook 回滚（只保留 feature 分支快速验证）。

### 最终架构
```
触发:
  main    → cron 12:00/17:00 (TimerTrigger) → 变更检测 → 全编 8.5min
  feature → Gitea webhook push → 增量编译 ~2.5min

workspace:
  /data/os-workspace/           ← main 全编
  /data/os-workspace-feature/   ← feature 增量
```

### 关键决策
- ❌ pollSCM → Pipeline + lightweight checkout 根本不可用 (0ms bug)
- ✅ cron + `git ls-remote` 变更检测 → 定时触发 + 自行判断是否需要构建
- ❌ main 分支 webhook 删除 → main 是定时产出通道，不是快速验证通道
- ✅ `--group-add 6` → 主机重启后 loop 设备权限修复
- ✅ 构建产物自动清理 → 磁盘不能无限堆积

### 已验证
- [x] cron 触发 "Started by timer" (#28, 15:56)
- [x] 变更检测 + 无变更跳过 (#28)
- [x] Gitea webhook 删除后 push 不触发
- [x] 磁盘清理: 100% → 83%
- [x] feature 分支已清理

### TODO
- [ ] 等待 17:00 验证 cron 触发 + 变更→构建 全链路

📋 [决策: pollSCM 放弃, cron+git ls-remote 替代, main webhook 回滚 | 待办: 17:00 验证]