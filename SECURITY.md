# 安全模型 / Security model

这份文档说明 **dsh-solution-first** 到底会做什么、以什么权限做、信任哪些输入。
它从实现（`skills/solution-first/SKILL.md`、`templates/AGENTS.md.snippet.md`、
`scripts/*.ps1`、`scripts/validate.py`、`scripts/hooks/pre-commit`）里读出来；
**如果文档和代码不一致，以代码为准，那说明这份文档是个 bug。**

> 一句话：**这个仓库本身几乎不执行任何东西**——它是给 agent 读的提示词 + 三个安装/校验脚本。
> 真正的风险不在仓库里，而在「agent 读完 `SKILL.md` 之后会去跑什么」，以及
> `install.ps1` / `install-hooks.ps1` 会往你的 home 目录和 `.git/hooks/` 里写什么。

## 信任边界

仓库里没有服务、没有端口、没有 `package.json`、没有依赖、没有运行时。全部内容分三类：

| 类别 | 文件 | 谁来执行 | 能力 |
| --- | --- | --- | --- |
| 提示词（文本） | `skills/solution-first/SKILL.md`、`templates/AGENTS.md.snippet.md` | agent 宿主按需加载 / 用户手工粘贴 | 影响 agent 的判断与回复结构，**不直接执行** |
| 安装脚本 | `scripts/install.ps1`、`sync.ps1`、`install-hooks.ps1` | 你手工运行（PowerShell 5.1+） | 建/删 junction、`git pull`、写 `.git/hooks/pre-commit` |
| 校验脚本 | `scripts/validate.py`、`scripts/hooks/pre-commit` | 你手工运行 / git 在 commit 时 / CI | **只读**仓库文件，打印结果，非 0 退出表示拒绝 |

**视为不可信输入**的：

- **`SKILL.md` 的正文**——它是注入给模型上下文的文本。你 clone 的是谁的 fork，就等于让谁的
  文字影响你的 agent。这个仓库自己的文本不包含指令注入，但 fork 可能；
- **仓库里被校验的文件内容**——`validate.py` 会把它们当纯文本读入并正则匹配，不执行；
- **`git pull` 拉下来的内容**——`sync.ps1` 只做 `--ff-only` 快进，但快进到的提交本身没有签名校验
  （见「已知限制」）；
- **环境变量 `HOME`**——`install.ps1` 用它定位 `~/.agents/skills`，`HOME` 被改就会写到别处。

## 脚本具体做什么（逐条对应到代码）

### `scripts/install.ps1`

- 目标：`$HOME/.agents/skills/solution-first`（可用 `-SkillsHome` 改）。
- 目录不存在会 `New-Item -ItemType Directory` 创建它（包括父目录）。
- 目标已存在时：
  - 是 junction / symlink → 用 `[System.IO.Directory]::Delete($target, $false)` **只删链接本身**，
    代码注释明确写了「绝不能用 `Remove-Item -Recurse`」；
  - 是真实目录/文件 → **直接 throw，不覆盖**。
- 建链接：`New-Item -ItemType Junction -Target <repo>/skills/solution-first`（Windows 目录联接，
  不需要管理员权限）。`-Copy` 时改为复制一份，之后两份独立。
- 不写仓库、不联网、不请求提权。

### `scripts/sync.ps1`

- `Push-Location <仓库根>` 后执行 `git pull --ff-only`——会修改**当前仓库的工作树**；
  有未提交改动或分叉时失败退出，不制造合并提交。
- 读完 `SKILL.md` 前 40 行检查 frontmatter；检查 `~/.agents/skills/solution-first/SKILL.md`
  是否可达。不写文件、不联网（git 自己联网）。

### `scripts/install-hooks.ps1`

- 把 `scripts/hooks/pre-commit` 复制到 `<仓库>/.git/hooks/pre-commit`；
- 已存在同名钩子会先备份成 `pre-commit.bak`，**然后覆盖**；
- 只动这一个仓库的 `.git/hooks/`，不碰全局 `core.hooksPath`。

### `scripts/hooks/pre-commit`（`/bin/sh`）

- 依次找 `python3`、`python`，用仓库根为工作目录执行 `scripts/validate.py`；
- 两个都没有时打印提示并 `exit 0`（**跳过校验**，见「已知限制」）；
- 可以用 `git commit --no-verify` 绕过。

### `scripts/validate.py`

- 只用标准库（`pathlib`、`re`、`sys`），**不联网、不写文件、不起子进程**；
- 检查四件事：`SKILL.md` frontmatter（`name` 必须等于目录名）、所有文本文件是合法 UTF-8、
  所有 `.ps1` 带 UTF-8 BOM、正则扫描本机绝对路径与常见密钥格式；
- 失败打印 `FAIL ...` 并以退出码 1 结束。

## 权限现状（照实写）

- **没有提权**：三个脚本都不调用 `-Verb RunAs`、不改注册表、不加防火墙规则、不装服务。
- **没有网络出口**：唯一联网的是 `sync.ps1` 里的 `git pull`，走你已有的 git 凭据。
- **写权限范围**：`~/.agents/skills/`（链接或副本）、`<仓库>/.git/hooks/pre-commit`、
  `<仓库>` 自身的工作树（`git pull`）。除此之外不写任何路径。
- **没有"看起来像门禁其实不是"的东西**：`validate.py` 的 secret 扫描是**正则启发式**，
  它的通过不等于"没有密钥"；真正的门禁是你在推送前自己看一眼 diff。

## 数据与副作用

- 不收集遥测、不上传仓库内容、不写日志文件；
- `validate.py` 只把仓库文件读进内存做正则匹配；
- `install.ps1` 之后，agent 读到的是**同一份**仓库文件（junction），不存在两份副本漂移；
- 卸载 = 删掉那个 junction（**不要** `Remove-Item -Recurse`，那会删到仓库内容）+
  删掉 `.git/hooks/pre-commit`。

## 已知限制（都是设计取舍，不是 bug——但你应该知道）

1. **提示词不是强制**：`SKILL.md` 和 AGENTS.md 片段都只是给模型的文本，模型可以不听。
   仓库 README 自己就写了这一点；真正硬的卡点是人手里的 plan mode 审批。
2. **校验是启发式的**：密钥/路径扫描靠正则，换一种写法就漏；BOM 检查会**对全部 `.ps1`**
   生效（不只是含中文的），纯 ASCII 脚本也必须带 BOM 才能过本地校验。
3. **钩子可被绕过**：`git commit --no-verify` 直接跳过；CI 只校验本仓库自己的
   `validate.py` 覆盖项，不校验你的 agent 产出。
4. **`sync.ps1` 不验签**：`--ff-only` 只保证不产生合并提交，不保证拉下来的提交可信；
   信任链是 GitHub 账号本身。
5. **junction 是 Windows 概念**：Linux/macOS 用户按 README 用 `ln -s`，脚本不负责。
   删错链接（用递归删除）会连带删掉仓库内容。
6. **没有版本策略**：没有 tag、没有 release、没有 `CHANGELOG`；`main` 就是唯一版本。
7. **skill 目录位置随宿主而异**：脚本默认 `~/.agents/skills`，别的宿主可能要手工指路径。

## 明确不算漏洞的

- 仓库里没有任何运行时、没有监听端口、没有可被远程触发的入口——没有攻击面可言；
- `install.ps1` 删除已存在的 junction（这是"重装"的正常行为，且只删链接不删内容）；
- `install-hooks.ps1` 覆盖已有的 `pre-commit`（会先备份成 `.bak`）；
- `SKILL.md` 要求 agent 在回复里写"放弃了什么"（这是产品设计，不是信息泄露）；
- 有人 fork 后往 `SKILL.md` 里塞了别的指令——那是 fork 的问题，不是本仓库的漏洞；
- `validate.py` 拒绝你的提交（编码、BOM、路径、正则误报）——照报错修，或改你自己的文本。

## 报告漏洞

用 GitHub 的私密渠道：<https://github.com/dingchenhui0618-arch/dsh-solution-first/security/advisories/new>

这是一个人维护的项目，**我不承诺响应时限**；但我会读、会修，修完会在 commit 说明里写清
影响范围。请不要把还在生效的问题直接发到公开 issue 里。

## 支持范围

只维护 `main` 上的最新提交。没有版本号、没有回补分支；用 `./scripts/sync.ps1` 拉最新即可。
