---
描述: Windows 深度磁盘清理 Claude skill,规则快扫+Agent 探索双引擎,浏览器可视化勾选,五级安全模型
提出: 2026-10-18
阶段: active
ingenuity: ../ingenuity.md
---

# win-clean

Claude Code skill：Windows 深度磁盘清理。规则快扫 + Agent 探索双引擎，
浏览器可视化勾选，五级安全模型，全程可审计、可恢复。

## 安装

```powershell
git clone <repo>
cd win-clean
powershell -ExecutionPolicy Bypass -File install.ps1
```

## 使用

在 Claude Code 中说「C盘满了，帮我清理」或 `/win-clean`。

## 安全模型

| 级别 | 内容 | 删除策略 |
|---|---|---|
| L1 | pip/npm/conda 等可再生缓存 | 直接删 |
| L2 | Temp/转储/更新缓存 | 直接删 |
| L3 | 应用缓存（微信等） | 移入可恢复区（30天） |
| L4 | 卸载残留/深度发现/休眠文件 | 移入可恢复区，逐项确认（休眠文件 report-only） |
| L5 | Windows.old/WinSxS 等系统级 | 仅报告命令，不执行 |

- 每次执行产出审计日志（jsonl）与一键恢复脚本
- 硬编码保护清单（Windows/Program Files/用户目录根）不可越过
- Claude 自身永不执行删除，删除只经由 execute.ps1

## 开发

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-all.ps1   # PS 套件 (+Node 纯函数)
```

零运行时依赖：仅 Windows PowerShell 5.1；开发期 Node 仅用于 JS 纯函数测试。
