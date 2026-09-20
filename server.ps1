param(
    [Parameter(Position = 0)]
    [string]$Command = "",
    [Parameter(Position = 1)]
    [string]$PortValue = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$PidFile = Join-Path $Root ".file_server.pid"
$LogFile = Join-Path $Root ".file_server.log"
$ErrLog = Join-Path $Root ".file_server.err.log"
$Server = Join-Path $Root "file_server.py"
$ShareDir = if ($env:SHARE_DIR) { $env:SHARE_DIR } else { Join-Path $Root "down" }
$Bind = if ($env:BIND) { $env:BIND } else { "0.0.0.0" }
$script:DefaultPort = 8765
$script:PortFile = Join-Path $Root ".file_server.port"
$script:RuntimePortFile = Join-Path $Root ".file_server.runtime_port"
$script:PortFromEnv = $env:PORT
$script:Port = $script:DefaultPort
$script:ShowDetails = $true

function Enable-VirtualTerminal {
    try {
        $code = @"
using System;
using System.Runtime.InteropServices;
public static class VtConsole {
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out int m);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, int m);
    public static void Enable() {
        var h = GetStdHandle(-11);
        int m;
        if (GetConsoleMode(h, out m)) SetConsoleMode(h, m | 4);
    }
}
"@
        Add-Type -TypeDefinition $code -ErrorAction Stop
        [VtConsole]::Enable()
    } catch {}
}
Enable-VirtualTerminal

function Write-Bright {
    param(
        [string]$Code,
        [string]$Text,
        [switch]$NoNewline
    )
    $esc = [char]27
    $s = "$esc[${Code}m$Text$esc[0m"
    if ($NoNewline) {
        Write-Host -NoNewline $s
    } else {
        Write-Host $s
    }
}
function Write-Ok([string]$Text) { Write-Host $Text -ForegroundColor Green }
function Write-Warn([string]$Text, [switch]$NoNewline) { Write-Bright "1;38;5;226" $Text -NoNewline:$NoNewline }
function Write-ErrMsg([string]$Text, [switch]$NoNewline) { Write-Bright "1;38;5;196" $Text -NoNewline:$NoNewline }
function Write-Hi([string]$Text) { Write-Host $Text -ForegroundColor Cyan }
function Write-Dim([string]$Text) { Write-Host $Text -ForegroundColor DarkGray }

function Test-ValidPort([string]$Value) {
    $n = 0
    if (-not [int]::TryParse($Value, [ref]$n)) { return $false }
    return ($n -ge 1 -and $n -le 65535)
}

function Read-SavedPort {
    if (-not (Test-Path -LiteralPath $script:PortFile)) { return $null }
    $raw = ((Get-Content -LiteralPath $script:PortFile -Raw -ErrorAction SilentlyContinue) + "").Trim()
    if (Test-ValidPort $raw) { return [int]$raw }
    return $null
}

function Read-RuntimePort {
    if (-not (Test-Path -LiteralPath $script:RuntimePortFile)) { return $null }
    $raw = ((Get-Content -LiteralPath $script:RuntimePortFile -Raw -ErrorAction SilentlyContinue) + "").Trim()
    if (Test-ValidPort $raw) { return [int]$raw }
    return $null
}

function Get-PortLabel {
    if ($script:PortFromEnv) { return "本次环境变量" }
    if (Test-Path -LiteralPath $script:PortFile) { return "已保存" }
    return "默认"
}

function Initialize-Port {
    $saved = Read-SavedPort
    if ($script:PortFromEnv) {
        if (Test-ValidPort $script:PortFromEnv) {
            $script:Port = [int]$script:PortFromEnv
        } else {
            Write-ErrMsg "环境变量 PORT 无效: $($script:PortFromEnv)，改用已保存或默认端口"
            $script:Port = if ($saved) { $saved } else { $script:DefaultPort }
        }
    } elseif ($saved) {
        $script:Port = $saved
    } else {
        $script:Port = $script:DefaultPort
    }
}

function Save-Port([int]$Value) {
    $script:Port = $Value
    if ($Value -eq $script:DefaultPort) {
        Remove-Item -LiteralPath $script:PortFile -Force -ErrorAction SilentlyContinue
    } else {
        Set-Content -LiteralPath $script:PortFile -Value "$Value" -Encoding ASCII
    }
}

function Get-ActivePort {
    if (Get-RunningPid) {
        $live = Read-RuntimePort
        if ($live) { return $live }
    }
    return $script:Port
}

function Test-Alive([int]$ProcessId) {
    try {
        $null = Get-Process -Id $ProcessId -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-ProcessCommandLine([int]$ProcessId) {
    try {
        return (Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop).CommandLine
    } catch {
        try {
            return (Get-WmiObject Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue).CommandLine
        } catch {
            return $null
        }
    }
}

function Test-ThisServer([int]$ProcessId) {
    $cl = Get-ProcessCommandLine $ProcessId
    if ([string]::IsNullOrWhiteSpace($cl)) { return $false }
    $norm = $cl.Replace("/", "\").ToLowerInvariant()
    $needle = $Server.Replace("/", "\").ToLowerInvariant()
    return $norm.Contains($needle)
}

function Get-ListenPids([int]$ListenPort) {
    $ids = @()
    foreach ($line in (& netstat -ano)) {
        if ($line -match ":$ListenPort\s+\S+\s+(?:LISTENING|侦听)\s+(\d+)\s*$") {
            $ids += [int]$Matches[1]
        }
    }
    return @($ids | Select-Object -Unique)
}

function Get-RunningPid {
    if (Test-Path -LiteralPath $PidFile) {
        $raw = ((Get-Content -LiteralPath $PidFile -Raw -ErrorAction SilentlyContinue) + "").Trim()
        $oldId = 0
        if ([int]::TryParse($raw, [ref]$oldId) -and (Test-Alive $oldId) -and (Test-ThisServer $oldId)) {
            return $oldId
        }
    }
    $ports = @($script:Port)
    $live = Read-RuntimePort
    if ($live -and $live -ne $script:Port) { $ports += $live }
    foreach ($p in $ports) {
        foreach ($id in @(Get-ListenPids $p)) {
            if (Test-ThisServer $id) { return $id }
        }
    }
    return $null
}

function Get-ServerPids {
    $ids = New-Object System.Collections.Generic.List[int]
    $running = Get-RunningPid
    if ($running) { $ids.Add([int]$running) }
    $ports = @($script:Port)
    $live = Read-RuntimePort
    if ($live -and $live -ne $script:Port) { $ports += $live }
    foreach ($p in $ports) {
        foreach ($id in @(Get-ListenPids $p)) {
            if ((Test-ThisServer $id) -and -not $ids.Contains($id)) {
                $ids.Add($id)
            }
        }
    }
    try {
        $procs = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
    } catch {
        $procs = Get-WmiObject Win32_Process
    }
    foreach ($p in $procs) {
        if (-not $p.CommandLine) { continue }
        $norm = $p.CommandLine.Replace("/", "\").ToLowerInvariant()
        $needle = $Server.Replace("/", "\").ToLowerInvariant()
        if ($norm.Contains($needle) -and -not $ids.Contains([int]$p.ProcessId)) {
            $ids.Add([int]$p.ProcessId)
        }
    }
    return $ids
}

function Wait-Exit([int]$ProcessId) {
    for ($i = 0; $i -lt 30; $i++) {
        if (-not (Test-Alive $ProcessId)) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return -not (Test-Alive $ProcessId)
}

function Write-Urls {
    param([int]$ShowPort = 0)
    if ($ShowPort -le 0) { $ShowPort = $script:Port }
    Write-Host "访问地址:" -ForegroundColor White
    Write-Host "  http://127.0.0.1:${ShowPort}/" -ForegroundColor Cyan
    $seen = @{}
    foreach ($line in (& ipconfig)) {
        if ($line -match "(?i)IPv4[^:]*:\s*(\d+\.\d+\.\d+\.\d+)") {
            $ip = $Matches[1]
            if ($ip -like "127.*" -or $ip -like "169.254.*") { continue }
            if ($seen.ContainsKey($ip)) { continue }
            $seen[$ip] = $true
            Write-Host "  http://${ip}:${ShowPort}/" -ForegroundColor Cyan
        }
    }
}

function Resolve-Python {
    $names = @()
    if ($env:PYTHON) { $names += $env:PYTHON }
    $names += @("py", "python", "python3")
    foreach ($name in $names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $exe = $cmd.Source
        if ($name -eq "py" -or ($exe -match '(?i)\\py\.exe$')) {
            return @{ Exe = $exe; Prefix = @("-3") }
        }
        return @{ Exe = $exe; Prefix = @() }
    }
    return $null
}

function Show-Usage {
    Write-Host "用法: server.bat [start|stop|restart|status|port]"
    Write-Host ""
    Write-Host "  start           启动服务"
    Write-Host "  stop            停止服务"
    Write-Host "  restart         重启服务"
    Write-Host "  status          查看状态"
    Write-Host "  port [端口]     修改端口；port default 恢复 8765"
    Write-Host ""
    Write-Host "不带参数时进入菜单；执行完一项后会回到菜单，选 0 才退出。"
    Write-Host "服务运行中退出时会询问是否同时停止。"
    Write-Host "端口会保存到 .file_server.port，菜单第 5 项也可改。"
}

function Invoke-Status {
    $pidNow = Get-RunningPid
    if ($pidNow) {
        Write-Host "状态: 运行中 (PID $pidNow)" -ForegroundColor Green
        if ($script:ShowDetails) {
            Write-Host "目录: $ShareDir"
            Write-Host ("端口: {0} ({1})" -f $script:Port, (Get-PortLabel))
            Write-Urls -ShowPort (Get-ActivePort)
            Write-Host "日志: $LogFile"
        }
    } else {
        Write-Warn "状态: 未运行"
        if ($script:ShowDetails) {
            Write-Host "目录: $ShareDir"
            Write-Host ("端口: {0} ({1})" -f $script:Port, (Get-PortLabel))
        }
    }
}

function Invoke-Start {
    if (-not (Test-Path -LiteralPath $Server)) {
        Write-ErrMsg "找不到 $Server"
        return
    }

    New-Item -ItemType Directory -Force -Path $ShareDir | Out-Null

    $py = Resolve-Python
    if (-not $py) {
        Write-ErrMsg "找不到 Python 解释器。请安装 Python 并勾选 Add python.exe to PATH，或设置 PYTHON 环境变量。"
        return
    }

    $pidNow = Get-RunningPid
    if ($pidNow) {
        Write-Warn "服务已在运行 (PID $pidNow)"
        if ($script:ShowDetails) {
            Write-Host "目录: $ShareDir"
            Write-Urls
            Write-Host "日志: $LogFile"
        }
        return
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue

    $existing = @(Get-ListenPids $script:Port)
    if ($existing.Count -gt 0) {
        Write-ErrMsg ("端口 {0} 已被占用: {1}" -f $script:Port, ($existing -join ", "))
        netstat -ano | Select-String ":$script:Port\s+\S+\s+(?:LISTENING|侦听)"
        Write-Host "可先执行 server.bat stop，或换端口: set PORT=9000 && server.bat start"
        return
    }

    "" | Set-Content -LiteralPath $LogFile -Encoding UTF8
    "" | Set-Content -LiteralPath $ErrLog -Encoding UTF8

    $argList = @()
    $argList += $py.Prefix
    $argList += @(
        $Server,
        "--bind", $Bind,
        "--port", "$script:Port",
        "--directory", $ShareDir
    )

    try {
        $proc = Start-Process -FilePath $py.Exe -ArgumentList $argList -WorkingDirectory $Root -RedirectStandardOutput $LogFile -RedirectStandardError $ErrLog -WindowStyle Hidden -PassThru
    } catch {
        Write-ErrMsg "启动失败: $($_.Exception.Message)"
        return
    }

    Set-Content -LiteralPath $PidFile -Value "$($proc.Id)" -Encoding ASCII

    $ok = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (-not (Test-Alive $proc.Id)) { break }
        $listeners = @(Get-ListenPids $script:Port)
        if ($listeners -contains $proc.Id) {
            $ok = $true
            break
        }
        Start-Sleep -Milliseconds 100
    }

    if (-not $ok) {
        Write-ErrMsg "启动失败，最近日志:"
        if (Test-Path -LiteralPath $LogFile) { Get-Content -LiteralPath $LogFile -Tail 40 }
        if (Test-Path -LiteralPath $ErrLog) { Get-Content -LiteralPath $ErrLog -Tail 40 }
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:RuntimePortFile -Force -ErrorAction SilentlyContinue
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        return
    }

    Set-Content -LiteralPath $script:RuntimePortFile -Value "$($script:Port)" -Encoding ASCII
    Write-Ok "已启动内网文件服务 (PID $($proc.Id))"
    if ($script:ShowDetails) {
        Write-Host "目录: $ShareDir"
        Write-Urls
        Write-Host "日志: $LogFile"
        Write-Host "停止: server.bat stop"
    }
}

function Invoke-Stop {
    $pids = @(Get-ServerPids)
    if ($pids.Count -eq 0) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:RuntimePortFile -Force -ErrorAction SilentlyContinue
        Write-Warn "服务未运行"
        return
    }

    foreach ($id in $pids) {
        try { Stop-Process -Id $id -ErrorAction SilentlyContinue } catch {}
    }

    foreach ($id in $pids) {
        if (-not (Wait-Exit $id)) {
            try { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } catch {}
            $null = Wait-Exit $id
        }
    }

    $still = @(Get-ServerPids)
    if ($still.Count -gt 0) {
        Write-ErrMsg ("停止失败，仍在运行: {0}" -f ($still -join ", "))
        return
    }

    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:RuntimePortFile -Force -ErrorAction SilentlyContinue
    Write-Warn "已停止内网文件服务"
    if ($script:ShowDetails -and (Test-Path -LiteralPath $LogFile)) {
        Write-Host "日志: $LogFile"
    }
}

function Invoke-Restart {
    Invoke-Stop
    Invoke-Start
}

function Confirm-Exit {
    $pidNow = Get-RunningPid
    if (-not $pidNow) {
        Write-Dim "已退出"
        return
    }
    Write-Warn "退出后是否停止服务？ [y/N] " -NoNewline
    $answer = Read-Host
    switch -Regex ($answer) {
        '^(?i)(y|yes|是|停|停止)$' {
            Invoke-Stop
            Write-Dim "已退出"
        }
        default {
            Write-Hi "服务继续在后台运行。"
            Write-Dim "已退出"
        }
    }
}

function Apply-PortValue([string]$InputValue) {
    $input = ($InputValue + "").Trim()
    if (-not $input) {
        Write-Dim "已取消"
        return
    }
    $newPort = 0
    switch -Regex ($input) {
        '^(?i)(default|d|默认|reset|restore)$' { $newPort = $script:DefaultPort }
        default {
            if (-not (Test-ValidPort $input)) {
                Write-ErrMsg "端口无效: $input（需要 1-65535）"
                return
            }
            $newPort = [int]$input
        }
    }
    if ($newPort -eq $script:Port) {
        if ($newPort -eq $script:DefaultPort -and (Test-Path -LiteralPath $script:PortFile)) {
            Save-Port $newPort
            Write-Ok "已恢复默认端口 $($script:DefaultPort)"
        } else {
            Write-Warn "已经是端口 $newPort"
            return
        }
    } else {
        Save-Port $newPort
        if ($newPort -eq $script:DefaultPort) {
            Write-Ok "已恢复默认端口 $($script:DefaultPort)"
        } else {
            Write-Ok "端口已保存为 $($script:Port)"
        }
    }
    if (Get-RunningPid) {
        $live = Read-RuntimePort
        if (-not $live) { $live = $script:Port }
        if ($live -ne $script:Port) {
            if ([Environment]::UserInteractive) {
                Write-Warn "服务仍在 $live 运行，是否立即按新端口重启？ [Y/n] " -NoNewline
                $answer = Read-Host
                if ($answer -match '^(n|no|否)$') {
                    Write-Hi "下次启动或重启后生效。"
                } else {
                    Invoke-Restart
                }
            } else {
                Write-Hi "服务仍在 $live 运行，下次启动或重启后生效。"
            }
        }
    }
}

function Invoke-SetPort {
    Write-Host ("当前端口: {0} ({1})" -f $script:Port, (Get-PortLabel))
    if (Get-RunningPid) {
        Write-Host ("服务正在 {0} 运行" -f (Get-ActivePort))
    }
    Write-Host ("输入新端口 (1-65535)。输入 default / 默认 恢复 {0}，回车取消。" -f $script:DefaultPort)
    if ([Environment]::UserInteractive) {
        $input = Read-Host ">"
        Apply-PortValue $input
    } else {
        Write-ErrMsg "非交互环境请使用: server.bat port 9000  或  server.bat port default"
    }
}

function Show-Menu {
    $script:ShowDetails = $false
    $redraw = $true
    while ($true) {
        if ($redraw) {
            $pidNow = Get-RunningPid
            $statusLine = if ($pidNow) { "运行中 (PID $pidNow)" } else { "未运行" }
            Write-Host ""
            Write-Host "内网文件服务" -ForegroundColor White
            Write-Host "状态: " -NoNewline
            if ($pidNow) {
                Write-Host $statusLine -ForegroundColor Green
            } else {
                Write-Warn $statusLine
            }
            Write-Host "目录: $ShareDir"
            Write-Host ("端口: {0} ({1})" -f $script:Port, (Get-PortLabel))
            if ($pidNow) {
                $live = Read-RuntimePort
                if ($live -and $live -ne $script:Port) {
                    Write-Warn "服务仍在 $live，重启后才会改到 $($script:Port)"
                    Write-Urls -ShowPort $live
                } else {
                    Write-Urls -ShowPort $script:Port
                }
            }
            Write-Host ""
            Write-Host "  1) 启动"
            Write-Host "  2) 停止"
            Write-Host "  3) 重启"
            Write-Host "  4) 状态"
            Write-Host "  5) 修改端口"
            Write-Host "  0) 退出"
            Write-Host ""
        }
        $redraw = $true
        $choice = Read-Host "请选择 [0-5]"
        switch ($choice) {
            { $_ -in @("1", "start", "启动") } { Invoke-Start }
            { $_ -in @("2", "stop", "停止") } { Invoke-Stop }
            { $_ -in @("3", "restart", "重启") } { Invoke-Restart }
            { $_ -in @("4", "status", "状态") } { }
            { $_ -in @("5", "port", "端口") } { Invoke-SetPort }
            { $_ -in @("0", "q", "quit", "exit", "退出") } {
                Confirm-Exit
                return
            }
            "" { $redraw = $false }
            default {
                Write-Warn "未知选项: $choice"
                $redraw = $false
            }
        }
    }
}

function Invoke-ThenMenu([scriptblock]$Action) {
    if ([Environment]::UserInteractive) {
        $script:ShowDetails = $false
        & $Action
        Show-Menu
    } else {
        $script:ShowDetails = $true
        & $Action
    }
}

Initialize-Port

switch ($Command.ToLowerInvariant()) {
    { $_ -in @("start", "on", "up", "启动") } { Invoke-ThenMenu { Invoke-Start } }
    { $_ -in @("stop", "off", "停止") } { Invoke-ThenMenu { Invoke-Stop } }
    { $_ -in @("restart", "reboot", "重启") } { Invoke-ThenMenu { Invoke-Restart } }
    { $_ -in @("status", "state", "状态") } { Invoke-ThenMenu { Invoke-Status } }
    { $_ -in @("port", "端口") } {
        if ($PortValue) {
            Apply-PortValue $PortValue
            if ([Environment]::UserInteractive) { Show-Menu }
        } else {
            Invoke-SetPort
            if ([Environment]::UserInteractive) { Show-Menu }
        }
    }
    { $_ -in @("-h", "--help", "help", "帮助") } { Show-Usage }
    "" {
        if ([Environment]::UserInteractive) {
            Show-Menu
        } else {
            Show-Usage
            Write-Host ""
            Invoke-Status
            exit 1
        }
    }
    default {
        Write-ErrMsg "未知命令: $Command"
        Show-Usage
        exit 1
    }
}
