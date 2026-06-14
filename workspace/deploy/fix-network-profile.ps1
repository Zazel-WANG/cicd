# 强制关键网络接口为 Private
# 脚本位置: E:\AI-helper\CICD_patform\workspace\deploy\fix-network-profile.ps1
# 触发: 任务计划程序 → FixNetworkProfile → AtStartup

$targets = @("以太网 2", "以太网 3", "WLAN")

# 等待网络适配器就绪（开机时网卡可能还没初始化）
$waited = 0
$maxWait = 60

while ($waited -lt $maxWait) {
    $ready = $true
    foreach ($t in $targets) {
        $profile = Get-NetConnectionProfile | Where-Object InterfaceAlias -eq $t
        if (-not $profile) { $ready = $false; break }
    }
    if ($ready) { break }
    Start-Sleep -Seconds 3
    $waited += 3
}

foreach ($target in $targets) {
    $profile = Get-NetConnectionProfile | Where-Object InterfaceAlias -eq $target

    if (-not $profile) {
        Write-Host "[Fix] $target 未就绪，跳过"
        continue
    }

    if ($profile.NetworkCategory -ne "Private") {
        Write-Host "[Fix] $target 当前为 $($profile.NetworkCategory)，正在设为 Private..."
        Set-NetConnectionProfile -InterfaceAlias $target -NetworkCategory Private
        Write-Host "[Fix] $target → Private 完成"
    } else {
        Write-Host "[Fix] $target 已是 Private，无需操作"
    }
}

# 确保 sshd 在运行（启动顺序竞争可能导致它没起来）
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshd) {
    if ($sshd.StartType -ne "Automatic") {
        Write-Host "[Fix] sshd StartType=$($sshd.StartType)，设为 Automatic"
        Set-Service sshd -StartupType Automatic
    }
    if ($sshd.Status -ne "Running") {
        Write-Host "[Fix] sshd 未运行，正在启动..."
        Start-Service sshd
        Write-Host "[Fix] sshd 已启动"
    } else {
        Write-Host "[Fix] sshd 运行中"
    }
} else {
    Write-Host "[Fix] 警告：sshd 服务未安装"
}
