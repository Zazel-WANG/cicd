# 变更日志

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
