---
描述: Windows 深度磁盘清理 Claude skill,规则快扫+Agent 探索双引擎,浏览器可视化勾选,五级安全模型
提出: 2026-10-18
阶段: active
ingenuity: ../ingenuity.md
---

# win-clean

Windows 深度磁盘清理 Claude Code skill(开发中,设计文档见根仓库 `docs/superpowers/specs/2026-10-18-win-clean-design.md`)。

- 双引擎:规则库确定性快扫 + Claude Agent 探索性扫描,探索发现自动沉淀回规则库
- 五级安全模型:L1/L2 直接删,L3/L4 进可恢复区,L5 仅报告
- 浏览器报告:仪表盘 + Treemap 勾选,最终分析报告 + 历史趋势
- 全程可审计:执行日志 + 一键恢复脚本

> 本 README 为元信息占位,完整使用说明随 Task 10(M5 打磨)落地。
