# 变更日志

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
