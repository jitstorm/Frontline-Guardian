<#
.SYNOPSIS
逐项限时运行 Godot 脚本，保存标准输出与错误；断言挂起时仅结束本次测试进程。
.PARAMETER GodotPath
本机 Godot 控制台可执行文件的绝对路径。
.PARAMETER Cases
要运行的脚本文件名，不含扩展名；import 表示项目导入检查，每项单独启动。
.PARAMETER MaxSeconds
每项允许的最长秒数，超时后报告失败，避免断言中断协程后无限等待。
#>
param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [string[]]$Cases = @('import', 'smoke', 'economy', 'hero_rpg', 'dungeon', 'playthrough', 'phase4_full_run', 'balance_mechanics', 'input_controls', 'balance_matrix', 'build_mechanics', 'build_matrix', 'performance', 'visual_capture'),
    [int]$MaxSeconds = 30
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$failedCases = @()
try {
    # 把引擎缓存限制到项目的忽略目录，避免沙箱下用户配置目录不可写导致误判。
    $env:APPDATA = Join-Path $projectPath '.godot_user/Roaming'
    $env:LOCALAPPDATA = Join-Path $projectPath '.godot_user/Local'
    New-Item -ItemType Directory -Force $env:APPDATA, $env:LOCALAPPDATA, (Join-Path $projectPath 'test_logs') | Out-Null
    foreach ($case in $Cases) {
        $outPath = Join-Path $projectPath "test_logs/$case.out.txt"
        $errPath = Join-Path $projectPath "test_logs/$case.err.txt"
        $arguments = @('--headless', '--path', '.', '--script', "tests/$case.gd")
        if ($case -eq 'import') { $arguments = @('--headless', '--path', '.', '--editor', '--quit') }
        if ($case -eq 'visual_capture') { $arguments = @('--path', '.', '--script', 'tests/visual_capture.gd') }
        $child = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WorkingDirectory $projectPath -WindowStyle Hidden -PassThru -RedirectStandardOutput $outPath -RedirectStandardError $errPath
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (-not $child.WaitForExit(1000) -and $watch.Elapsed.TotalSeconds -lt $MaxSeconds) {
            # 引擎运行时保持输出文件独占写入，结束后再读取，避免 Windows 文件共享冲突。
            if ([int]$watch.Elapsed.TotalSeconds % 10 -eq 0) { Write-Output "RUN $case elapsed=$([int]$watch.Elapsed.TotalSeconds)s" }
        }
        if (-not $child.HasExited) {
            # 只终止本次启动且持有进程句柄的测试，避免干扰编辑器或其他游戏实例。
            Stop-Process -Id $child.Id
            $failedCases += $case
            Write-Output "TIMEOUT $case after $MaxSeconds seconds"
            continue
        }
        $child.WaitForExit()
        $outputText = [IO.File]::ReadAllText($outPath)
        $errorText = [IO.File]::ReadAllText($errPath)
        Write-Output $outputText
        # 本机证书存储不可读不影响离线战斗；其余脚本、断言与引擎错误均使验证失败。
        $hasError = ($outputText + $errorText) -match 'SCRIPT ERROR|Assertion failed|Parse Error|ERROR: (?!Failed to read the root certificate store)'
        if ($child.ExitCode -ne 0 -or $hasError) {
            $failedCases += $case
            Write-Output "FAIL $case exit=$($child.ExitCode)"
            Write-Output $errorText
        } else { Write-Output "PASS $case exit=0" }
    }
} finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
}
if ($failedCases.Count -gt 0) { exit 1 }
exit 0
