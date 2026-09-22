#Requires -Version 5.1
<#
.SYNOPSIS
  把 solution-first skill 挂到 agent 的 skill 目录。

.DESCRIPTION
  默认建立 junction（Windows 目录联接），不需要管理员权限，也不会留下两份副本 ——
  在仓库里改内容，agent 立刻读到最新版。

  目标已存在且不是链接时，脚本会报错退出，绝不覆盖你已有的文件。

.PARAMETER RepoRoot
  仓库根目录，默认取本脚本的上级目录。

.PARAMETER SkillsHome
  agent 的用户级 skill 目录，默认 ~/.agents/skills。

.PARAMETER Copy
  改为复制文件而不是建链接。复制后仓库与 skill 目录会各自独立。

.EXAMPLE
  ./scripts/install.ps1
  ./scripts/install.ps1 -Copy
#>
[CmdletBinding()]
param(
    [string]$RepoRoot   = (Split-Path -Parent $PSScriptRoot),
    [string]$SkillsHome = (Join-Path $HOME '.agents\skills'),
    [switch]$Copy
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $RepoRoot 'skills\solution-first'
if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) {
    throw "找不到 skill 源：$source\SKILL.md"
}

if (-not (Test-Path -LiteralPath $SkillsHome)) {
    New-Item -ItemType Directory -Path $SkillsHome -Force | Out-Null
    Write-Host "已创建 skill 目录：$SkillsHome"
}

$target = Join-Path $SkillsHome 'solution-first'

if (Test-Path -LiteralPath $target) {
    $item = Get-Item -LiteralPath $target -Force
    if ($item.LinkType -in @('Junction', 'SymbolicLink')) {
        Write-Host "移除已存在的链接：$target" -ForegroundColor Yellow
        # 只删链接本身。绝不能用 Remove-Item -Recurse：那会连目标内容一起删掉。
        [System.IO.Directory]::Delete($target, $false)
    }
    else {
        throw "目标已存在且不是链接：$target。请先手动处理，脚本不会覆盖真实目录。"
    }
}

if ($Copy) {
    Copy-Item -LiteralPath $source -Destination $target -Recurse
    Write-Host "已复制到：$target"
}
else {
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Host "已建立 junction：$target -> $source"
}

$ok = Test-Path -LiteralPath (Join-Path $target 'SKILL.md')
Write-Host "校验 SKILL.md 可达：$ok"
if (-not $ok) { throw "安装后校验失败。" }
