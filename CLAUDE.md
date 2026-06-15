# CI/CD 平台

> ⚠️ **核心规则（最高优先级，不可跳过）**
>
> 每次完成用户任务后，必须在返回结果前检查是否有新知识需要写入对应 SKILL.md。
> 更新后必须在回复末尾报告。

本文件为 Claude Code 提供项目上下文和操作指南。

## 用户背景

详见全局 Skill `user-profile`（自动加载）。

## 项目概述

- **名称**：CI/CD 平台
- **领域**：embedded-cicd
- **描述**：为鲁班猫 RK3588 搭建 CI/CD 全自动构建-测试-部署流水线，后续迁移到麒麟软件卫星嵌入式 OS
- **输出**：Docker Compose / Jenkinsfile / Makefile / PowerShell 脚本
- **团队**：个人
- **创建日期**：2026.6.13

## 硬件环境

- 开发板：鲁班猫 RK3588（ARM64，8核，NPU）
- 外设：屏幕、摄像头
- 笔记本：Windows（开发 + 部署中转）
- 主机：Ubuntu Server 22.04（Docker + Gitea + Jenkins）
- 网络：笔记本↔主机网线直连（10.0.0.x），鲁班猫↔笔记本 USB 共享网络

## 🛡️ 安全规则（最高优先级，不可覆盖）

> 这些规则通过 SessionStart hook 自动注入，此处再次强调。

1. **NOT-FOUND 熔断** — 工具返回 NOT FOUND → 停手确认，不猜测
2. **观测矛盾停手** — 两个以上观测通道矛盾 → 停手复核
3. **写前必读** — 向 SKILL.md 写入前必读当前文件
4. **审计用 node** — 读 JSONL 必须逐行 JSON.parse

## 目录结构

```
E:\AI-helper\projects\cicd\    ← 独立 git 仓库
├── CLAUDE.md
├── CHANGELOG.md
├── .gitignore
├── .claude/settings.json
├── .hot/recovery.md           ← 会话恢复（自动）
├── workspace/
│   ├── deploy/                ← 部署脚本（deploy-to-lubancat.ps1 等）
│   ├── docs/                  ← 操作手册和学习笔记
│   ├── project-template/      ← CI 模板（Jenkins cicd job 的 Jenkinsfile 在此）
│   ├── repos/test-ci/         ← 测试项目（Jenkins test-pipeline 的 Jenkinsfile 在此，job 已禁用）
│   ├── Jenkins.Dockerfile
│   └── docker-compose.yml
└── references/
    └── notes/
        └── network-setup-lessons.md
```

> 本项目是独立的 git 仓库（嵌套在父仓库 `E:\AI-helper\` 下，父仓库 .gitignore 忽略本目录）。
> 全局 Skill 池和 hook 系统由父仓库统一管理，本项目直接使用。

## 项目定位

本项目的职责是**基础设施维护**——Docker、Jenkins、Gitea 的配置与运维。具体的嵌入式项目（人脸识别、语音交互等）在 `E:\AI-helper\projects\` 下作为独立目录存在，每个有自己的 git 仓库、CLAUDE.md、CI/CD 链路。

新嵌入式项目用 `AI_PROJECT_INIT.md` 在 `projects/` 下初始化，与本项目平级。详见 `E:\AI-helper\AI optimization\workspace\用户使用指南.md` §六。

## Skills 系统

**全局 Skill 池**：`E:\AI-helper\skills\` —— 所有项目共享。
**本项目关联的 Skill 域**：[ci-cd-pipeline, embedded-cross-compile, shell-safety, workflow-methodology, docker-ops, deployment]

### AI 检索流程

1. **SessionStart** — hook 自动注入 GLOBAL_RULES + 项目上下文 + 会话恢复
2. **UserPromptSubmit** — hook 自动扫描全局 skills/，注入匹配索引
3. **AI 主动检索** — AI 看到索引后自行 Read 相关 SKILL.md
4. **AI 自动归档** — 每次回答末尾反思 → 更新 Skill + frontmatter → 报告用户

### Skill 管理规则

| 规则 | 详情 |
|------|------|
| 归档优先级 | 已有 Skill → 新建 Skill（需用户确认） |
| 删改规则 | **任何删改必须先询问用户** |
| 永不删除 | 可加 `[已过时]` 标签 |

## 会话恢复

SessionStart hook 自动读取 `.hot/recovery.md`（包含上次会话摘要 + 最后完整问答）。
关闭 Claude 时 Stop hook 自动覆写该文件，无需手动操作。

## 冷记忆（COLD）

遇到终结性结论（事故根因、架构决策、可迁移原则）时，AI 提议、用户审批后写入 `E:\AI-helper\memory\COLD\`。
文件名格式：`{YYYY-MM-DD}--{项目名}--{标题}.md`

## 关联 Skill

| Skill | 用途 |
|------|------|
| `ci-cd-pipeline` | Jenkins Pipeline、Multibranch、Gitea 集成 |
| `docker-ops` | Docker Compose、容器网络、镜像构建 |
| `deployment` | SCP/SSH 部署链路、Windows 中转、真机测试 |
| `embedded-cross-compile` | ARM64 工具链、Makefile、glibc 版本 |
| `shell-safety` | Bash/PowerShell 安全经验 |
| `workflow-methodology` | SSH 调试、架构迁移、文件归属 |
| `user-profile` | 用户画像（自动加载） |
| `global-traps` | 全局安全规则（自动加载） |

## 关键配置速查

| 项目 | 值 |
|------|-----|
| 主机 IP (私有子网) | 10.0.0.1 |
| 笔记本 IP (私有子网) | 10.0.0.2 |
| 鲁班猫 IP | 192.168.137.100 |
| Gitea | http://10.0.0.1:3000 |
| Jenkins | http://10.0.0.1:8080 |
| SSH 密钥类型 | ED25519 |
| 交叉编译 | `ARCH=arm64 -static` |

### Git Remote

| Remote | URL | 用途 |
|--------|-----|------|
| `origin` | `git@github.com:Zazel-WANG/cicd.git` | GitHub public 面试展示 |
| `gitea` | `ssh://git@10.0.0.1:2222/wangzhongqi/cicd.git` | Gitea 触发 Jenkins CI/CD |

```bash
git push origin main   # → GitHub
git push gitea main    # → Gitea，Jenkins 自动构建
```

### Jenkins Job 映射

| Job 名 | 类型 | Gitea 仓库 | Jenkinsfile 路径 | 状态 |
|--------|------|-----------|-----------------|:--:|
| `cicd` (project-template) | Multibranch Pipeline | `wangzhongqi/cicd` | `workspace/project-template/Jenkinsfile` | ✅ |
| `test-pipeline` | Pipeline | `wangzhongqi/cicd` | `workspace/repos/test-ci/Jenkinsfile` | 已禁用 |
| `project-template-old` | Pipeline | — | — | 归档 |

## 工作规范

- **语言**：中文
- **CI/CD 原则**：可复现、可回滚、最小权限
- **验证要求**：所有脚本和配置必须实测
- **变更记录**：记录到 CHANGELOG.md
- **Skill 更新**：新知识优先归入已有 Skill，回答末尾检查
