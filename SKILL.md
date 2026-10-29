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

## 对用户怎么说

使用简短、具体的中文，数字带单位。扫描时说明正在检查的位置和进度；展示结果时区分发现容量与已选项目的预计释放量。提交前提醒用户检查项目的路径、处理方式和需管理员项。演练时明确说明没有实际删除；实际完成后根据执行报告说明处理、跳过和恢复方式。

面向用户可用「放心清理」「系统垃圾」「可恢复区」「逐项确认」「仅供参考」解释五个等级，同时保留等级标识以对应报告。不要保证每一项都能恢复，也不要把预计释放量说成已释放量。跨盘项目的选择会包含该项目全部路径，须在确认前说明。

## 路径约定

本文档中所有相对路径（engine/、tools/、rules/、logs/）均以本技能根目录
（SKILL.md 所在目录）为基准。执行命令前先解析为绝对路径，例如：
`$sk = "<本技能根目录的绝对路径>"`，然后所有命令写为 `powershell ... -File "$sk\engine\scan.ps1"`。
每次运行都创建独立会话目录，避免读取上次的选择或覆盖历史：
`$run = Join-Path "$sk\logs\runs" ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $run -Force | Out-Null`。
`$run` 保持在同一会话中，并用于本次扫描、选择和执行。

## 阶段① 开始：概况与档位

```
Get-PSDrive -PSProvider FileSystem | Select Name,Used,Free
```
向用户展示各盘紧张度，给出三档选择：
- ⚡快速档：只跑快扫（L1+L2 默认勾选即可执行）
- 🎯标准档：快扫 + 已知残留核对（learned.json 全量）
- 🔬深度档：快扫 + Agent 探索（见阶段②B）
- 盘位选择：问用户要扫哪些盘，默认全部固定盘；把盘符列表传给 scan.ps1 的 -Drives 参数（如 `-Drives "C,D"`）

## 阶段② 扫描

A. 快扫（所有档位必跑）：
```
powershell -NoProfile -ExecutionPolicy Bypass -File "$sk\engine\scan.ps1" -OutFile "$run\scan-result.json" -Drives "<用户选择的盘符>" -ProgressFile "$run\scan-progress.json"
```
（两个新参数默认可省略：不传 -Drives 扫全部固定盘，不传 -ProgressFile 不写进度文件。）

后台运行扫描，期间每隔几秒读 progress 文件并向用户播报进度（"正在扫描 npm-cache (5/24)…"），完成后播报发现总量。

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
powershell -NoProfile -ExecutionPolicy Bypass -File "$sk\engine\serve.ps1" -ScanFile "$run\scan-result.json" -SelectionsOut "$run\selections.json" -HistoryIndex "$sk\logs\history\index.json"
```
用后台方式启动（如 Bash run_in_background），等待 `"$run\serve-info.json"` 出现后读取 URL，
让用户在浏览器打开并勾选。轮询 `"$run\selections.json"` 出现（最多 15 分钟）。
超时未提交 → 读取 serve-info.json 的 pid 并 `Stop-Process -Id <pid>`，询问用户取消还是降级静态模式。

降级：服务起不来 → `-Static -OutHtml "$run\report.html"`，用户在页面"提交清理"处
复制命令回终端执行。用户执行复制命令后，把 `$env:TEMP\win-clean-selection.json`
复制为 `"$run\selections.json"` 再进入阶段④。

## 阶段④ 执行

```
$d = Join-Path $run "execution"
powershell -NoProfile -ExecutionPolicy Bypass -File "$sk\engine\execute.ps1" -ScanFile "$run\scan-result.json" -SelectionsFile "$run\selections.json" -HistoryDir $d
```
执行前应先用 `-DryRun` 演练并给用户看结果；需要管理员的项会被跳过，不要声称页面已生成管理员命令。隔离到同一磁盘通常不会立即释放磁盘空间。

## 阶段⑤ 最终报告

```
powershell -NoProfile -ExecutionPolicy Bypass -File "$sk\engine\report-gen.ps1" -ScanFile "$run\scan-result.json" -ExecSummaryFile (Join-Path $d 'exec-summary.json') -SessionDir $d -HistoryRoot "$sk\logs\history"
```
阶段⑤使用本次 `$run` 和 `$d`；跨会话继续时须明确定位对应的会话目录。
用浏览器打开 `<$d>/final-report.html`，向用户播报释放量、前后对比、恢复脚本位置、
被跳过/需管理员项、累计战绩。可恢复区位于本次执行目录内；工具仅在再次使用同一执行目录时检查并清理超过 30 天的隔离内容，不保证定期清除。

## 参数速查

scan.ps1: -RulesDir -OutFile -OnlyIds -Drives -ProgressFile ｜ serve.ps1: -ScanFile -SelectionsOut -HistoryIndex -Static -OutHtml
execute.ps1: -ScanFile -SelectionsFile -HistoryDir -DryRun ｜ report-gen.ps1: -ScanFile -ExecSummaryFile -SessionDir -HistoryRoot
learn-rule.ps1: -RulesDir -Id -Level -Name -Paths -Type -Desc -AutoSelect
