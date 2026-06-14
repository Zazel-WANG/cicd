# 恢复指南（全链路状态）

> 用户重启后，AI 读取本文件即可恢复上下文。

## 当前中断点（无——2026.6.12 全部打通）

**重启原因**：手机热点 IP 变化 + ICS 服务卡死，鲁班猫失联。（已恢复）

**已解决的恢复问题**：
1. ✅ Webhook URL 修正：test-pipeline → project-template
2. ✅ project-template 全链路跑通（编译 → 测试 → 验证 → 部署）
3. ✅ 真机返回值回传（exit code → Jenkins pass/fail）
4. ✅ Toast 通知（成功/失败 + 阶段定位 + 中文提交信息）
5. ✅ 重启后 sshd 不自动启动 → fix-network-profile.ps1 已加守护
6. ✅ 网络 Profile 变 Public → fix-network-profile.ps1 覆盖三接口
7. ✅ Jenkins 时区 UTC → docker-compose 加 Asia/Shanghai

**当前进度**：
- ✅ Phase 1-3（Gitea + Jenkins + 交叉编译 + 部署链路）
- ✅ Phase 4a（QEMU 单元测试）
- ✅ Phase 4b（真机执行返回值回传）
- ✅ TEMPLATE（项目模板 + 通用 Makefile/Jenkinsfile）
- 🟡 下一步 → VERSION（构建产物版本化）

## 当前进度

- ✅ Phase 1: 基础设施（Gitea + Jenkins + Webhook）
- ✅ Phase 2: 交叉编译流水线（git push → 自动编译 ARM64 二进制）
- ✅ Phase 3: 部署到鲁班猫（Jenkins → 笔记本 → 鲁班猫 SCP 链路）

## 重启后快速恢复（5 分钟）

### Step 1：检查网络（笔记本 PowerShell 管理员）
```powershell
# 先看全部接口状态
Get-NetConnectionProfile | Format-Table InterfaceAlias, NetworkCategory

# 以太网 2 对主机可达
ping 10.0.0.1

# 以太网 3 对鲁班猫可达
ping 192.168.137.100

# 修复所有关键接口（哪个是 Public 就修哪个）
Set-NetConnectionProfile -InterfaceAlias "以太网 2" -NetworkCategory Private
Set-NetConnectionProfile -InterfaceAlias "以太网 3" -NetworkCategory Private
# WLAN 视需要决定是否设 Private（连接公司网络时有安全风险）
```

> 已配开机自修复脚本 `fix-network-profile.ps1`（覆盖以太网 2/3 + WLAN）
> 任务计划程序 → FixNetworkProfile → AtStartup

### Step 2：检查笔记本 SSH 服务（笔记本 PowerShell 管理员）
```powershell
# sshd 服务状态和启动类型
Get-Service sshd | Format-List Name, Status, StartType

# 如果没有运行：
Set-Service sshd -StartupType Automatic
Start-Service sshd

# 确认 22 端口在监听
netstat -an | findstr ":22 "
```

### Step 3：检查鲁班猫（笔记本终端）
```bash
ping 192.168.137.100
ssh cat@192.168.137.100 "echo LubanCat OK"
```

### Step 4：检查 Docker 容器（主机 VSCode 终端）
```bash
docker ps
# 期望 gitea + jenkins 两个容器 Up
```

### Step 5：检查 Jenkins → 笔记本 SSH（主机 VSCode 终端）
```bash
docker exec jenkins ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 HUAWEI@10.0.0.2 "echo SSH OK"
```

### Step 6：全链路验证
在 Jenkins `http://10.0.0.1:8080` 点击 Build Now，观察 Deploy 阶段输出。

## 关键配置速查

| 配置项 | 位置 | 值 |
|--------|------|----|
| 鲁班猫固定 IP | 鲁班猫 nmcli | `192.168.137.100` |
| 笔记本→鲁班猫 SSH 用户 | - | `cat` |
| Jenkins→笔记本 密钥类型 | - | ED25519 |
| 笔记本→鲁班猫 密钥类型 | - | ED25519 |
| SCP 路径格式 | Jenkinsfile | `HUAWEI@10.0.0.2:E:/AI-helper/...` |
| 交叉编译 | Makefile | `ARCH=arm64 -static` |
| Git 仓库本地路径 | 笔记本 | `E:\AI-helper\CICD_patform\workspace\repos\test-ci` |
| Git 远程 | Gitea | `ssh://git@10.0.0.1:2222/wangzhongqi/test.git` |
| 部署脚本 | 笔记本 | `E:\AI-helper\CICD_patform\workspace\deploy\deploy-to-lubancat.ps1` |

## 凭证速查

| 凭证 | 位置/获取方式 |
|------|-------------|
| Gitea 账号 | `wangzhongqi` |
| Jenkins 账号 | `wangzhongqi` |
| Jenkins API Token | `http://10.0.0.1:8080/user/wangzhongqi/configure` → Token `gitea-webhook` |
| Webhook 触发器 Token | `lubancat` |
| Webhook URL 模板 | `http://wangzhongqi:APIToken@jenkins:8080/job/任务名/build?token=lubancat` |
| 敏感信息 | 见桌面 `credentials.md` |
