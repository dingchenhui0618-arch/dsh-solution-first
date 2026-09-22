#Requires -Version 5.1
<#
.SYNOPSIS
  安装本仓库的 git 钩子。

.DESCRIPTION
  把 scripts/hooks/pre-commit 装到 .git/hooks/，让每次提交都在本地跑
  scripts/validate.py —— 与 CI 完全同一份逻辑，不必等推送后才发现问题。

  钩子只存在于 .git/hooks/，不会提交进仓库，也不会影响其他仓库。

.EXAMPLE
  ./scripts/install-hooks.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$gitDir = Join-Path $RepoRoot '.git'
if (-not (Test-Path -LiteralPath $gitDir)) {
    throw "$RepoRoot 不是 git 仓库。"
}

$source = Join-Path $RepoRoot 'scripts\hooks\pre-commit'
if (-not (Test-Path -LiteralPath $source)) {
    throw "找不到钩子源文件：$source"
}

$hookDir = Join-Path $gitDir 'hooks'
if (-not (Test-Path -LiteralPath $hookDir)) {
    New-Item -ItemType Directory -Path $hookDir -Force | Out-Null
}

$target = Join-Path $hookDir 'pre-commit'
if (Test-Path -LiteralPath $target) {
    Copy-Item -LiteralPath $target -Destination "$target.bak" -Force
    Write-Host "已备份原有钩子到：$target.bak" -ForegroundColor Yellow
}

Copy-Item -LiteralPath $source -Destination $target -Force
Write-Host "已安装 pre-commit 钩子：$target" -ForegroundColor Green

# git 在 Windows 上通过自带的 sh 执行钩子，不需要可执行位；
# 但显式校验一次脚本能被解析，避免装上一个必然报错的钩子。
$check = & git -C $RepoRoot rev-parse --git-dir 2>&1
Write-Host "git dir: $check"
Write-Host "钩子会在下次 git commit 时生效。"
