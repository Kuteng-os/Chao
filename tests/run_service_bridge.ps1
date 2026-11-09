param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testDirectory = Join-Path $projectRoot ('.runtime/test-bridge-' + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
if (-not $GodotPath) { $GodotPath = 'D:\工程\GT\Godot_v4.7-stable_win64.exe' }
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Set GODOT_BIN or pass -GodotPath to Godot 4.7.' }
$nodeExecutable = (Get-Command node -ErrorAction Stop).Source
$testServer = $null
$previousProfile = $env:FRONTLINE_PROFILE_PATH
$previousURL = $env:FRONTLINE_BRIDGE_URL
$testExit = 1
try {
    $helper = Join-Path $PSScriptRoot 'service_bridge_server.mjs'
    $testServer = Start-Process -FilePath $nodeExecutable -ArgumentList @('"' + $helper + '"', '"' + $testDirectory + '"') -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testDirectory 'server.out.log') -RedirectStandardError (Join-Path $testDirectory 'server.err.log')
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($testServer.HasExited) { throw 'Isolated bridge server exited. Check test directory server.err.log.' }
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:18787/health' -TimeoutSec 1
            $startup = Get-Content -LiteralPath (Join-Path $testDirectory 'server.out.log') -Raw -ErrorAction SilentlyContinue
            if ($health.ok -and -not $health.configured -and $startup -match 'BRIDGE_SERVER_READY') { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) { throw 'Isolated bridge service did not start; port 18787 may be occupied.' }
    $env:FRONTLINE_BRIDGE_URL = 'http://127.0.0.1:18787'
    $env:FRONTLINE_PROFILE_PATH = Join-Path $testDirectory 'profile.json'
    $godotArguments = @('--headless', '--path', '"' + $projectRoot + '"', '--script', 'tests/test_service_bridge.gd', '--log-file', '"' + (Join-Path $testDirectory 'godot.log') + '"')
    $godotTest = Start-Process -FilePath $GodotPath -ArgumentList $godotArguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -Wait
    $testExit = $godotTest.ExitCode
    Get-Content -LiteralPath (Join-Path $testDirectory 'godot.log')
    Write-Host ('Isolated HTTP bridge artifacts: ' + $testDirectory)
} finally {
    $env:FRONTLINE_PROFILE_PATH = $previousProfile
    $env:FRONTLINE_BRIDGE_URL = $previousURL
    if ($testServer -and -not $testServer.HasExited) {
        Set-Content -LiteralPath (Join-Path $testDirectory 'stop.request') -Value 'stop'
        if (-not $testServer.WaitForExit(5000)) { Stop-Process -Id $testServer.Id; $testServer.WaitForExit() }
    }
}
exit $testExit
