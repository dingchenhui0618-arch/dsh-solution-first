#!/usr/bin/env python3
"""校验本仓库可以安全公开、且 skill 仍然可用。

同一份逻辑既在 CI 里跑，也可以在本地推送前跑：

    python scripts/validate.py

检查项：
  1. SKILL.md 的 frontmatter 完整，且 name 等于目录名
  2. 所有文本文件是合法 UTF-8
  3. 含中文的 .ps1 是 UTF-8 with BOM（否则 Windows PowerShell 5.1 按 ANSI 解析会报语法错误）
  4. 没有混进本机绝对路径或常见密钥格式

退出码非 0 表示拒绝通过。
"""

from __future__ import annotations

import pathlib
import re
import sys

SKILL_DIR = pathlib.Path("skills/solution-first")
SKILL_MD = SKILL_DIR / "SKILL.md"

SECRET_AND_PATH_PATTERNS = [
    (r"[A-Za-z]:\\Users\\", "Windows 用户绝对路径"),
    (r"/Users/[A-Za-z0-9._-]+/", "macOS 用户目录"),
    (r"/home/[A-Za-z0-9._-]+/", "Linux 用户目录"),
    (r"sk-[A-Za-z0-9]{20,}", "疑似 OpenAI 风格密钥"),
    (r"gh[pousr]_[A-Za-z0-9]{20,}", "疑似 GitHub token"),
    (r"AKIA[0-9A-Z]{16}", "疑似 AWS Access Key"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "私钥"),
    (r"api[_-]?key\s*[:=]\s*['\"][A-Za-z0-9_-]{16,}", "疑似硬编码 api key"),
]

SKIP_DIRS = {".git", "__pycache__", "node_modules"}


def fail(message: str) -> None:
    print(f"FAIL {message}", file=sys.stderr)
    sys.exit(1)


def check_skill_frontmatter() -> None:
    if not SKILL_MD.is_file():
        fail(f"缺少文件：{SKILL_MD}")

    text = SKILL_MD.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        fail(f"{SKILL_MD}: 第一行必须是 ---")

    end = text.find("\n---\n", 4)
    if end < 0:
        fail(f"{SKILL_MD}: frontmatter 未闭合")

    frontmatter = text[4:end]
    for key in ("name:", "description:"):
        if key not in frontmatter:
            fail(f"{SKILL_MD}: frontmatter 缺少 {key}")

    name_line = next(line for line in frontmatter.splitlines() if line.startswith("name:"))
    name = name_line.split(":", 1)[1].strip()
    if name != SKILL_DIR.name:
        fail(f"{SKILL_MD}: frontmatter 的 name={name!r} 必须等于目录名 {SKILL_DIR.name!r}")

    description = frontmatter.split("description:", 1)[1].strip()
    if len(description) < 40:
        fail(f"{SKILL_MD}: description 太短，无法触发按需加载")

    print(f"OK   frontmatter  name={name}")


def iter_text_files():
    for path in sorted(pathlib.Path(".").rglob("*")):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        try:
            # utf-8-sig 让带 BOM 的文件也能正常解码，同时仍会拒绝非法字节
            yield path, path.read_text(encoding="utf-8-sig")
        except (UnicodeDecodeError, OSError):
            yield path, None


def check_powershell_bom() -> None:
    """含中文的 .ps1 必须是 UTF-8 with BOM。

    Windows PowerShell 5.1 在没有 BOM 时按系统 ANSI 代码页读取脚本，
    中文会被拆成非法字节，直接导致 ParserError。Linux/macOS 的 pwsh 不受影响，
    所以这个坑只在 Windows 上出现 —— 正是需要在 CI 里拦住的那类问题。
    """
    bom = b"\xef\xbb\xbf"
    checked = 0

    for path in sorted(pathlib.Path(".").rglob("*.ps1")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        raw = path.read_bytes()
        if not raw.startswith(bom):
            fail(f"{path}: 缺少 UTF-8 BOM —— Windows PowerShell 5.1 会按 ANSI 解析含中文的脚本")
        checked += 1

    print(f"OK   {checked} 个 .ps1 文件均为 UTF-8 with BOM")


def check_encoding_and_leaks() -> None:
    findings: list[str] = []
    checked = 0

    for path, text in iter_text_files():
        if text is None:
            findings.append(f"{path}: 不是合法 UTF-8")
            continue
        checked += 1
        for pattern, label in SECRET_AND_PATH_PATTERNS:
            for match in re.finditer(pattern, text):
                findings.append(f"{path}: {label} -> {match.group(0)[:50]}")

    if findings:
        for line in findings:
            print(f"FAIL {line}", file=sys.stderr)
        sys.exit(1)

    print(f"OK   {checked} 个文本文件，未发现本机路径或密钥")


def main() -> None:
    check_skill_frontmatter()
    check_powershell_bom()
    check_encoding_and_leaks()
    print("PASS 全部检查通过")


if __name__ == "__main__":
    main()
