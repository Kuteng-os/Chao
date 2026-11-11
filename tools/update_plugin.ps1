# Installs the newest 巢战 DSH plugin from GitHub Releases.
#   irm https://raw.githubusercontent.com/xiangwu738-design/Chao/main/tools/update_plugin.ps1 | iex
# Plugin 0.5.1 and later can also update itself from inside DSH ("更新插件").
$ErrorActionPreference = 'Stop'
$releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/xiangwu738-design/Chao/releases?per_page=50' -Headers @{ Accept = 'application/vnd.github+json' }
$best = $null
foreach ($release in $releases) {
    if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^plugin-v(\d+\.\d+\.\d+)$') { continue }
    $version = [version]$Matches[1]
    $asset = $release.assets | Where-Object { $_.name -eq "dsh-plugin-chao-cards-$($Matches[1]).tgz" } | Select-Object -First 1
    if (-not $asset -or $asset.digest -notmatch '^sha256:([0-9a-f]{64})$') { continue }
    $digest = $Matches[1]
    if (-not $best -or $version -gt $best.Version) { $best = [pscustomobject]@{ Version = $version; Asset = $asset; Sha256 = $digest } }
}
if (-not $best) { throw 'GitHub 上没有找到插件安装包。' }

$directory = Join-Path $env:LOCALAPPDATA 'ChaoCards\plugins'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$target = Join-Path $directory $best.Asset.name
Write-Host "下载巢战插件 $($best.Version) ..."
Invoke-WebRequest -Uri $best.Asset.browser_download_url -OutFile "$target.part" -UseBasicParsing
if ((Get-FileHash -Algorithm SHA256 "$target.part").Hash.ToLower() -ne $best.Sha256) {
    Remove-Item -Force "$target.part"
    throw '安装包校验失败，已删除下载的文件。'
}
Move-Item -Force "$target.part" $target

$dsh = Get-Command dsh -ErrorAction SilentlyContinue
if (-not $dsh) {
    Write-Host "安装包已下载到 $target"
    Write-Host '找不到 dsh 命令：请在 DSH Desktop 菜单选择 Manage dsh Command… → Install，然后在新终端运行：'
    Write-Host "dsh plugin --profile desktop add `"$target`""
    return
}
& $dsh.Source plugin --profile desktop add $target
if ($LASTEXITCODE -ne 0) { throw "dsh 安装失败（退出码 $LASTEXITCODE）。" }
Write-Host "已安装巢战插件 $($best.Version)。请完全退出 DSH Desktop 再重新打开。"
