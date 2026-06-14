param(
    [Parameter(Mandatory=$true)]
    [string]$ArtifactPath,

    [Parameter(Mandatory=$true)]
    [string]$TargetIP,

    [string]$TargetUser = "cat",
    [string]$DeployDir = "/home/cat/deploy"
)

$ErrorActionPreference = "Stop"

$binary  = Split-Path $ArtifactPath -Leaf
# 从 hello-9d53647 提取项目名 hello
$baseName = $binary -replace '-[^-]+$', ''

# 1. 确保远程目录存在
ssh -o StrictHostKeyChecking=no ${TargetUser}@${TargetIP} "mkdir -p ${DeployDir}"

# 2. SCP 传版本化二进制
Write-Host "[Deploy] SCP $binary -> ${TargetUser}@${TargetIP}:${DeployDir}/"
scp -o StrictHostKeyChecking=no $ArtifactPath ${TargetUser}@${TargetIP}:${DeployDir}/

# 3. 设执行权限 + 更新软链接 + 运行
Write-Host "[Deploy] Run on LubanCat..."
ssh -o StrictHostKeyChecking=no ${TargetUser}@${TargetIP} "chmod +x ${DeployDir}/${binary} && ln -sf ${binary} ${DeployDir}/${baseName} && ${DeployDir}/${baseName}"
$exitCode = $LASTEXITCODE

# 4. 清理旧版本（保留最新 2 个）
ssh -o StrictHostKeyChecking=no ${TargetUser}@${TargetIP} "cd ${DeployDir} && ls -t ${baseName}-* 2>/dev/null | tail -n +3 | xargs rm -f"

if ($exitCode -eq 0) {
    Write-Host "[Deploy] $binary PASS"
} else {
    Write-Host "[Deploy] $binary FAIL (exit code: $exitCode)"
}

exit $exitCode
