<!--
---
描述: Windows 磁盘空间分析与分级清理，提供可视化选择、执行记录和可恢复区
提出: 2026-10-18
阶段: active
ingenuity: ../../ingenuity.md#win-clean
---
-->

# win-clean

在 Windows 上找出占空间的缓存、临时文件和应用残留，在浏览器里看清路径与处理方式，由你选择要清理的内容。

它以 [Agent Skill](https://agentskills.io/specification) 的形式工作：`SKILL.md` 负责引导扫描和执行，PowerShell 脚本处理文件，本地报告展示结果。适用于 Claude Code，当前提供 PowerShell 安装脚本。

## 安装

需要 Windows、Windows PowerShell 5.1、Git 和可用的 Claude Code。报告建议使用 Edge 或 Chrome。**普通使用无需 Node.js 或额外 API Key。**

在 PowerShell 中运行：

```powershell
git clone https://github.com/PenglongHuang/win-clean.git
cd win-clean
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

安装脚本将 Skill 放到 `%USERPROFILE%\.claude\skills\win-clean`。重新打开 Claude Code 后，输入 `/win-clean` 即可使用。Claude Code 也可能在你描述“C 盘空间不足”等需求时自动调用它。

**更新：**在克隆目录运行 `git pull`，再运行 `install.ps1`。安装脚本会更新程序文件，保留目标目录中的日志与已学习规则；运行前可先查看脚本内容。

## 使用

在 Claude Code 中输入 `/win-clean`，或说“帮我看看 C 盘哪些内容占空间”。Skill 根据你的请求确定扫描范围；未指定盘符时扫描全部固定盘，默认使用标准模式。报告打开后，查看每项的路径、容量估算和处理方式，勾选需要处理的内容并提交选择；后续执行与结果汇总由 Skill 完成。

- **快速：**按内置及已学习规则扫描。
- **标准：**额外核对已知应用残留。
- **深度：**进一步探索规则之外的占用；新规则须经你同意才保存。

报告支持按磁盘筛选、搜索和图形化查看。按磁盘筛选只改变显示；一个项目可能覆盖多个磁盘，选中该项目会包含它的全部路径。

## 清理边界

| 等级 | 内容 | 处理方式 |
| --- | --- | --- |
| L1 | 可再生缓存 | 永久删除；部分规则默认选中 |
| L2 | 临时文件、更新残留 | 永久删除；部分规则默认选中 |
| L3 | 应用缓存 | 移入可恢复区；手动选择 |
| L4 | 深度发现 | 移入可恢复区；逐项确认 |
| L5 | 系统级项目 | 只报告，不执行 |

**请在提交前检查路径。**L1、L2 永久删除后无法通过本工具恢复。L3、L4 的可恢复区位于本次执行目录，并会生成恢复脚本；它不是 Windows 回收站。隔离文件若仍在同一磁盘，通常不会立即释放该磁盘空间。报告中的容量为扫描估算，不等于实际释放量。

扫描、选择、日志和可恢复文件保存在安装目录的 `logs/` 中。报告只在本机提供服务，但页面和日志可能包含用户名与文件路径，分享前请检查。需管理员权限的项目可能被跳过。

## 仓库结构

```text
SKILL.md       Skill 工作流程与安全约束
install.ps1    安装与更新
engine/        扫描、执行、报告服务
report/        浏览器报告界面
rules/         内置规则
tools/         规则校验与学习
tests/         自动化测试
docs/          设计资料
```

开发验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-all.ps1
```

测试只应在隔离的测试目录中运行，**不要将真实资料放入测试目录**。仓库目前未附开源许可证，授权范围以仓库实际文件为准。
