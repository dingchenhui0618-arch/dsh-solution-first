#Requires -Version 5.1
<#
.SYNOPSIS
  拉取本仓库最新内容，并校验 skill 仍可用。

.DESCRIPTION
  因为 install.ps1 建立的是链接，pull 完成后 agent 读到的就是最新版，
  不需要重新安装。

  只做 --ff-only 快进合并：本地有分叉或未提交改动时会直接失败，
  而不是悄悄制造一次合并提交。

.EXAMPLE
  ./scripts/sync.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot  = (Split-Path -Parent $PSScriptRoot),
    [string]$SkillsHome = (Join-Path $HOME '.agents\skills')
)

$ErrorActionPreference = 'Stop'

Push-Location $RepoRoot
try {
    if (-not (Test-Path -LiteralPath '.git')) { throw "$RepoRoot 不是 git 仓库。" }

    Write-Host "拉取更新 ..." -ForegroundColor Cyan
    git pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "git pull 失败（本地可能有未提交改动或分叉）。" }

    $head = (git rev-parse --short HEAD).Trim()
    Write-Host "当前 HEAD：$head"

    # 校验 frontmatter，避免一次坏提交把 skill 弄失效
    $skill = Join-Path $RepoRoot 'skills\solution-first\SKILL.md'
    if (-not (Test-Path -LiteralPath $skill)) { throw "SKILL.md 缺失：$skill" }

    $lines = Get-Content -LiteralPath $skill
    if ($lines[0].Trim() -ne '---') { throw "SKILL.md 第一行必须是 ---（frontmatter 起始）。" }
    $fm = ($lines | Select-Object -First 40) -join "`n"
    foreach ($key in 'name:', 'description:') {
        if ($fm -notmatch [regex]::Escape($key)) { throw "frontmatter 缺少 $key" }
    }
    Write-Host "SKILL.md frontmatter 校验通过。" -ForegroundColor Green

    $linked = Join-Path $SkillsHome 'solution-first'
    if (Test-Path -LiteralPath (Join-Path $linked 'SKILL.md')) {
        Write-Host "skill 目录可达：$linked" -ForegroundColor Green
    }
    else {
        Write-Host "提示：skill 尚未挂载，运行 ./scripts/install.ps1" -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}
