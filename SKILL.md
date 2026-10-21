---
name: win-clean
description: Windows 深度磁盘清理与空间分析。Use when user says C盘满了、磁盘空间不足、清理垃圾、释放空间、深度清理、卸载残留、disk full、free up space、cleanup. 扫描（规则快扫 + Agent 探索）→ 浏览器可视化勾选 → 分级安全执行 → 完整报告与恢复。
---

# win-clean — Windows 深度清理

五级安全模型：L1🟢可再生缓存(直接删) / L2🟡系统垃圾(直接删) / L3🟠应用缓存(可恢复区) / L4🔴深度发现(可恢复区,逐项确认) / L5⚫专家区(仅报告)。

## 铁律（不可违反）

1. 你（Claude）**永不直接删除任何文件**。删除只经由 `engine/execute.ps1`。
2. L4 深度发现的每一项，必须先在报告页由用户逐项确认。
3. execute.ps1 拒绝的路径（保护清单命中）不得用其他方式绕过删除。
4. 探索发现的沉淀规则，必须先征得用户同意再调用 learn-rule。

## 路径约定

本文档中所有相对路径（engine/、tools/、rules/、logs/）均以本技能根目录
（SKILL.md 所在目录）为基准。执行命令前先解析为绝对路径，例如：
`$sk = "<本技能根目录的绝对路径>"`，然后所有命令写为 `powershell ... -File "$sk\engine\scan.ps1"`。
logs/ 目录若不存在先创建：`New-Item -ItemType Directory -Path "$sk\logs" -Force`。

## 阶段① 开始：概况与档位

```
Get-PSDrive -PSProvider FileSystem | Select Name,Used,Free
```
向用户展示各盘紧张度，给出三档选择：
- ⚡快速档：只跑快扫（L1+L2 默认勾选即可执行）
- 🎯标准档：快扫 + 已知残留核对（learned.json 全量）
- 🔬深度档：快扫 + Agent 探索（见阶段②B）

## 阶段② 扫描

A. 快扫（所有档位必跑）：
```
powershell -NoProfile -ExecutionPolicy Bypass -File "$sk\engine\scan.ps1" -OutFile "$sk\logs\scan-result.json"
```

B. Agent 探索（仅深度档）— 像专家一样狩猎，规则库外的目标：
1. `du -sh <盘>/* | sort -rh | head -20` 找未知大户
2. 大户内部再 `du -sh` 钻取两层，识别：已卸载应用残留（对照已安装列表）、
   旧安装包/更新残留（`*-updater`、`pending`、`installer.exe`）、异常日志目录、
   重复工具链（同软件多版本目录）
3. 判断性质：残留→L4；可再生缓存→L1；系统级→L5 报告
4. 每个发现向用户播报："发现 X（大小，路径，判断依据，建议等级）"
5. 用户同意后沉淀：
```
powershell -NoProfile -ExecutionPolicy Bypass -File "$sk\tools\learn-rule.ps1" -RulesDir "$sk\rules" -Id <kebab-id> -Level <1-5> -Name "<名>" -Paths "<绝对路径>" -Type <cache|temp|leftover|installer|log|dump|system> -Desc "<判断依据>"
```
沉淀后重跑快扫，新规则即入报告。

## 阶段③ 报告与勾选

```
powershell -NoProfile -ExecutionPolicy Bypass -File "$sk\engine\serve.ps1" -ScanFile "$sk\logs\scan-result.json" -SelectionsOut "$sk\logs\selections.json" -HistoryIndex "$sk\logs\history\index.json"
```
用后台方式启动（如 Bash run_in_background），等待 `"$sk\logs\serve-info.json"` 出现后读取 URL，
让用户在浏览器打开并勾选。轮询 `"$sk\logs\selections.json"` 出现（最多 15 分钟）。
超时未提交 → 读取 serve-info.json 的 pid 并 `Stop-Process -Id <pid>`，询问用户取消还是降级静态模式。

降级：服务起不来 → `-Static -OutHtml "$sk\logs\report.html"`，用户在页面"提交清理"处
复制命令回终端执行。用户执行复制命令后，把 `$env:TEMP\win-clean-selection.json`
复制为 `"$sk\logs\selections.json"` 再进入阶段④。

## 阶段④ 执行

```
$d = Join-Path "$sk\logs" ("history/" + (Get-Date -Format 'yyyy-MM-dd_HHmm'))
powershell -NoProfile -ExecutionPolicy Bypass -File "$sk\engine\execute.ps1" -ScanFile "$sk\logs\scan-result.json" -SelectionsFile "$sk\logs\selections.json" -HistoryDir $d
```
先给用户看 freedBytes 预估（可用 -DryRun 演练）。需要管理员的项在报告里给命令。

## 阶段⑤ 最终报告

```
powershell -NoProfile -ExecutionPolicy Bypass -File "$sk\engine\report-gen.ps1" -ScanFile "$sk\logs\scan-result.json" -ExecSummaryFile (Join-Path $d 'exec-summary.json') -SessionDir $d -HistoryRoot "$sk\logs\history"
```
若阶段⑤在新会话执行，先重算 `$d = Get-ChildItem "$sk\logs\history" -Directory | Sort-Object Name -Last 1`，或与阶段④同一会话执行。
用浏览器打开 `<$d>/final-report.html`，向用户播报释放量、前后对比、恢复脚本位置、
被跳过/需管理员项、累计战绩。提醒：可恢复区文件 30 天后自动清除。

## 参数速查

scan.ps1: -RulesDir -OutFile -OnlyIds ｜ serve.ps1: -ScanFile -SelectionsOut -HistoryIndex -Static -OutHtml
execute.ps1: -ScanFile -SelectionsFile -HistoryDir -DryRun ｜ report-gen.ps1: -ScanFile -ExecSummaryFile -SessionDir -HistoryRoot
learn-rule.ps1: -RulesDir -Id -Level -Name -Paths -Type -Desc -AutoSelect
