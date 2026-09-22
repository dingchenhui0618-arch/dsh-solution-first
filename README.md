# dsh-solution-first

> **先选路径，再动手。** 一套让 coding agent 在写代码之前先找现成解、先说清验收标准的工作约定。

## 它解决什么问题

Agent（和人）最常见的失败模式不是「写不出来」，而是**埋头猛干，最后产出一堆没人用的代码**：

- 没有验收标准，做到一半才发现理解错了
- 没有对比过现成方案，从零实现了一个生态里已经有五个实现的东西
- 产出「看起来做了很多」的代码，但没人会用它

这个仓库是一份可复用的对策。

## 三层机制

| 机制 | 形态 | 强度 | 为什么放这一层 |
|---|---|---|---|
| 常驻闸门 | [`templates/AGENTS.md.snippet.md`](templates/AGENTS.md.snippet.md) | 软 | 每轮注入，保证「不等 agent 想起来」 |
| 展开流程 | [`skills/solution-first/`](skills/solution-first/SKILL.md) | 软+ | 按需加载，承载完整的搜索与评估方法 |
| 审批卡点 | `/plan`（宿主自带，见下） | **硬** | 必须先交计划、由人 Approve 才能动代码 |

### 一个反直觉的结论：常驻规则不该做成 skill

Skill 是**按需加载**的 —— 只有 agent 判断「这个任务匹配它的描述」时才会读。
而「埋头猛干」恰恰是 agent **不会停下来加载任何东西**的那个状态。

**用需要主动想起才生效的机制，去治「想不起来」的病，逻辑上自相矛盾。**

所以正确分工是：

- **闸门**（短、每轮都在）→ `AGENTS.md`
- **流程**（长、按需读）→ skill，由 `AGENTS.md` 里一行指向它
- **强制**（否决权在人手里）→ plan mode

### 为什么最硬的一层不在这里

提示词是**软约束**：写了不等于每次都执行，尤其在上下文很长、用户在催的时候。
它显著提高概率，但不构成保证。

结构性的保证只有两个：**人手里的审批卡点**，或**在 agent 要写文件时硬拦的运行时钩子**。
前者开箱即用，后者容易被做成噪音，不建议一步到位。

`/plan` 属于前者。以 DeepSeek Harness 为例，其 `cordis` preset 里的 plan-mode
策略段落已经写明了这两条，正好就是本仓库的主张：

> Explore first. Use non-mutating reads... **Do not edit or write files**...
> **Prefer existing functions and patterns over new machinery.**

> Make the plan decision-complete: state the goal and **success criteria**; ...
> cover edge cases, failure modes, tests, **acceptance criteria, and explicit assumptions**.

换句话说：**「先找现成的」「先说清验收标准」在 plan mode 里已经是官方策略，只是默认不开。**

## 使用

### 1. 装 skill

把本仓库克隆到你的项目目录，然后：

```powershell
# Windows：以 junction 挂到 agent 的 skill 目录，避免两份副本
./scripts/install.ps1
```

```bash
# macOS / Linux：用符号链接
ln -s "$PWD/skills/solution-first" ~/.agents/skills/solution-first
```

> skill 目录位置随宿主而异。DeepSeek Harness 会扫描
> `~/.agents/skills/`（用户级）与 `<项目根>/.agents/skills`（项目级）。

### 2. 把闸门贴进你的指令文件

把 [`templates/AGENTS.md.snippet.md`](templates/AGENTS.md.snippet.md) 的内容
追加到你的用户级或项目级 `AGENTS.md`，并按注释替换占位符。

### 3. 重要任务用 plan mode

新建项目、改架构、大重构时，用宿主的计划模式入口（DSH 里是 `/plan <需求>`）开头。
agent 会先探索和设计，再提交完整计划，**必须你批准才动手**。

## 仓库结构

```
skills/solution-first/SKILL.md     可复用 skill：搜索顺序 / 评估清单 / 停止条件
templates/AGENTS.md.snippet.md     可直接粘贴的常驻闸门段落
scripts/install.ps1                把 skill 挂到 agent skill 目录
scripts/sync.ps1                   拉取更新并校验
.github/workflows/validate.yml     CI：frontmatter / 编码 / 隐私泄漏
```

## 自动化更新与校验

三道防线，跑的是**同一份** [`scripts/validate.py`](scripts/validate.py)：

| 时机 | 怎么触发 | 需要做什么 |
|---|---|---|
| 提交前 | `git commit` | 装一次：`./scripts/install-hooks.ps1` |
| 推送后 | GitHub Actions | 无需配置，见 `.github/workflows/validate.yml` |
| 手动 | 任何时候 | `python scripts/validate.py` |

- **改内容**：在本仓库改 → commit → push。
- **用最新版**：`./scripts/sync.ps1`（`git pull --ff-only` + 校验）。
  因为 skill 目录是链接，拉取后立即生效，不存在两份副本。
- **钩子只写进 `.git/hooks/`**，不进仓库、不影响其他仓库。

## 已知陷阱：Windows PowerShell 5.1 与 UTF-8 BOM

含中文的 `.ps1` **必须**以 UTF-8 with BOM 保存。

Windows PowerShell 5.1 在文件没有 BOM 时，会按系统 ANSI 代码页（简体中文环境是 GBK）
读取脚本。UTF-8 的中文字节被当成 GBK 解码后会产生非法字符，**直接导致 ParserError**，
报错信息还会显示为乱码，极难定位。

这不是理论问题 —— 本仓库的 `install.ps1` 第一次提交前就踩了这个坑。
`scripts/validate.py` 里的 `check_powershell_bom()` 会强制拦住它。

注意 `pwsh`（PowerShell 7+）默认按 UTF-8 读取，**不受影响**，
所以这个问题只在 Windows PowerShell 5.1 上出现，跨平台 CI 也不会帮你发现。

## 许可

MIT
