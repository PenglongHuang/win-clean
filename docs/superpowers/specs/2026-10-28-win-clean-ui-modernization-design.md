# win-clean UI 现代化 + 措辞大众化 — 设计文档

日期：2026-10-28 ｜ 状态：设计定稿（原型 v4 已获用户认可）
设计基准：`docs/prototype-v4.html`（本文档与原型冲突时，以本文档为准）

## 1. 背景与目标

用户反馈两点：报告页 UI 不够美观现代、缺少动画；SKILL.md 措辞太技术化，
而本工具面向普通用户。

目标：
1. 以 prototype-v4 的「精致暗色·玻璃拟态」风格重写报告页与完成页前端。
2. SKILL.md 增加「对用户怎么说」规范，术语全部映射为大众语言。
3. 安全铁律、引擎逻辑、API 协议一字不动。

## 2. 非目标

- scan.ps1 / execute.ps1 / report-gen.ps1 的逻辑不改（report-gen 只换模板引用）。
- serve.ps1 的 API（POST /api/select、GET /shutdown）与 `/*__SCAN_DATA__*/null`
  marker 注入机制不改，只新增资产文件服务与静态内联。
- 不引入任何运行时依赖：纯手写 HTML/CSS/JS，PS 5.1 only，Node 仅用于开发期测试。
- 不支持 IE；目标浏览器为现代 Edge / Chrome。

## 3. 视觉设计语言（theme.css 承载）

| 类别 | 规格 |
|---|---|
| 底色 | `#0b0d13`，body `overflow-x:hidden`，`padding-bottom:110px` 给悬浮栏留位 |
| 玻璃卡 | `rgba(255,255,255,.055)` + `backdrop-filter: blur(22px)` + 1px `rgba(255,255,255,.09)` 描边 + 圆角 16px；`@supports` 降级为 `rgba(24,27,36,.92)` 实底 |
| 极光背景 | 三团 radial-gradient（L1 绿 / 蓝 / 紫），blur 90-100px，`drift` 动画 26/32/38s 交替 |
| 文字 | 三级墨色 `#eef1f6 / #a6adbb / #7c8494`；数字一律 `tabular-nums` |
| 等级色 | L1 `#199e70` L2 `#c98500` L3 `#a64b1c` L4 `#e66767` L5 `#3987e5`，各配 `-soft` 半透明背景（dataviz 校验过的暗色槽位，`#0b0d13` 上对比 ≥3:1） |
| 动效系统 | 统一 `--ease-out: cubic-bezier(.22,.9,.36,1)`；入场 rise 交错 90ms/项；色块波次 26ms/项；KPI count-up（rAF + easeOutCubic）；tab pill 滑动；勾选 wave 波纹；CTA sheen 扫光；标题 chev 旋转 |
| 字体 | Segoe UI Variable Text → Microsoft YaHei UI 系统栈，不引入 webfont |

## 4. 信息架构（报告页，自上而下）

1. **顶栏**（sticky 玻璃条）：品牌「磁盘清理中心」+ 扫描完成时间胶囊。
   背景 `rgba(13,16,23,.82)` —— 足够不透明，内容滚过时不透字。
2. **引导条**（可收起）：一句话教交互（切盘 · 单击勾选 · 双击详情 · 搜索高亮）。
3. **Hero 三卡**：可释放总量（count-up 大数字）/ 本盘可清理项数（含 L5 注脚）/
   磁盘占用条形卡（满载 >90% 红、>75% 黄、否则绿；点击切盘；未扫描盘灰显）。
4. **磁盘 Tab**：胶囊分段控件 + 滑动 pill；**只显示本次扫描过的盘**；右侧提示文字。
5. **地图卡**（地图即清单）：搜索框 + 等级色带 treemap + L5 虚线条。
6. **悬浮操作栏**：固定底部居中胶囊（`position:fixed; left:50%; translateX(-50%)`），
   显示「N 项已选 · 预计释放 X GB」+ 绿色 CTA。
7. **浮层**：贴边翻转 tooltip / 详情模态 / 顶部 toast。

## 5. 交互设计（定稿决策）

1. **地图即清单**：勾选直接发生在色块上。单击=切换勾选，双击=详情模态。
2. **色带**（按等级分组，L3→L2→L1 自上而下）：标题行点击=展开/收起
   （同时只展开一条，展开高 380px，收起按占比 66-300px）；标题行右侧
   「全选/取消」组级按钮 —— **L4 色带除外**（见 §8 铁律 2）。
3. **小项**：≤100KB 的项画不进地图，收进色带下方「＋ N 个小项（共 X）」虚线胶囊，
   点开模态清单勾选。
4. **默认勾选**：L1+L2 且 >100KB 自动勾上（沿用现有语义：快速档开箱可执行）。
5. **跨盘合计**：操作栏统计跨所有盘汇总，不随当前 Tab 重置。
6. **tooltip 贴边翻转**：先量自身尺寸，右/下放不下就往左/上翻，四周留 12px。
7. **搜索**：即时把非命中色块 fade 到 8% 饱和度（不清不删）；Esc 清搜索/关模态。
8. **L4 项**：🔴 色带，**无组级全选**，必须逐项单击勾选或双击看详情后确认；
   模态文案明示「你确认之后才会处理」。
9. **L5 项**：整条虚线条「另有 X 在系统区域」，展开给 DISM 命令 + 「让 Claude 带你做」。
10. **admin 项**：色块名后 🔒，tooltip 注明「需管理员」；提交后不自动执行，
    完成页给可复制命令。
11. **提交**：CTA 点击 → POST /api/select → 按钮变「✅ 已提交，回到终端继续」
    + toast；静态降级模式下显示可复制命令（沿用现有机制）。

## 6. 无障碍（两条硬规则，含踩坑教训）

1. `prefers-reduced-motion: reduce` 时全部动画/过渡压到 .01ms，`.rise/.cell`
   直接呈现终态 —— **但 fixed 定位靠 transform 居中的元素必须显式豁免**：
   `.actionbar.rise { transform: translateX(-50%) !important }`。
   否则无障碍规则的 `transform:none !important` 会冲掉居中，整栏溢出屏幕
   （v3→v4 的真实根因之一，已用数字探针在 1000/720px 双宽度验证修复）。
2. 文字一律用墨色阶，不用等级色承载文字；等级色只上色块，identity 靠
   「图标+名称」双通道（图标 🟢🟡🟠🔴🔵 + 色带标题）。

## 7. 文件分层（重写后的 report/）

```
report/
  template.html        # 报告页骨架；marker: /*__SCAN_DATA__*/null + 资产引用
  final-template.html  # 完成页骨架；同款 marker
  assets/
    theme.css          # §3 全部 tokens + 玻璃/极光/动效系统 + 无障碍豁免（两页共用）
    report.css         # 报告页专属：hero/色带/cell/actionbar/modal/tip/toast
    final.css          # 完成页专属：战报卡/前后对比/恢复指引
    core.js            # 纯函数：fmtBytes / squarify / countUp / namePx（零 DOM，进 Node 测试）
    ui.js              # UI 原语：tip 贴边翻转 / modal / toast / tab pill（浏览器跑）
    report-app.js      # 报告页逻辑：状态 / renderBands / layoutBand / refresh / 提交
    final-app.js       # 完成页逻辑：战报渲染
```

分层理由：core.js 无 DOM 依赖可被 Node 测试直接加载；ui.js 两页复用；
每文件控制在 ~400 行内。prototype-v4.html 中的等价实现按此边界拆分，
不重写逻辑（已验证的 squarify/翻转/动画代码原样迁移）。

数据映射：serve.ps1 依旧注入原始 scan-result.json（格式不变）；
「scan JSON → 页面模型（按盘分组的 drives/findings/l5，见原型 DATA 结构）」
的转换放 report-app.js 顶部，纯函数、可测。

## 8. 安全（铁律 → UI 落点）

| 铁律 | UI 落点 |
|---|---|
| 1. Claude 永不直接删文件 | 提交只产出 selections.json，执行仍唯一走 execute.ps1；页面无任何删除动作 |
| 2. L4 每项必须用户逐项确认 | L4 色带**无组级全选按钮**；只能逐项单击/详情确认；默认不勾选 |
| 3. execute 拒绝的路径不得绕过 | UI 无绕过路径；提交物是纯勾选清单 |
| 4. learn-rule 先征得同意 | 不在 UI 范围；SKILL.md 话术保留该门槛 |

## 9. serve.ps1 改动清单

1. 新增 `assets/` 静态服务（Content-Type: text/css / application/javascript）。
2. `-Static` 降级：把 theme/report/core/ui/app 按 marker 全部内联进单文件 HTML
   （离线双击可用），`/*__SCAN_DATA__*/null` 数据注入机制不变。
3. `/api/select`、`/shutdown`、serve-info.json 协议不变。
4. 编码：.ps1 保存为 UTF-8 **带 BOM**（PS 5.1 无 BOM 会按 GBK 读中文字符串）。

## 10. SKILL.md 措辞改造

结构（保持「Agent 指令 + 用户话术」双栏性质，铁律与命令速查原文保留）：

1. 新增「对用户怎么说」小节：
   - 称呼「你」；短句；先说结果再说原理；数字必带单位（「清出 3.8 GB」不是「清出不少」）。
   - 永不裸报术语：不说「L3 可恢复区 quarantine」，说「先存回收站，30 天内能找回」。
   - 播报范例：扫描进度、发现播报、执行前后、最终战报各给一句模板。
2. 术语映射表（页面与话术共用同一套词）：

   | 内部 | 对用户 |
   |---|---|
   | L1 可再生缓存 | 🟢 放心清理（删了会自动重建） |
   | L2 系统垃圾 | 🟡 系统垃圾（用完即弃） |
   | L3 应用缓存→可恢复区 | 🟠 先存回收站（30 天可找回） |
   | L4 深度发现 | 🔴 逐项确认（你点头才动） |
   | L5 专家区 | 🔵 仅给建议（只教方法不代删） |
   | 快速档 / 标准档 / 深度档 | ⚡快速清理 / 🎯推荐 / 🔬彻底深挖 |
3. install.ps1 部署清单加入 `report/assets/*`。

## 11. 完成页（final-template.html）

同一套 theme.css + 玻璃卡：顶部大战报数字（本次释放 X GB，count-up），
前后磁盘占用对比条，明细表（处理/跳过/需管理员分组），恢复指引卡
（可恢复区位置 + 30 天提醒 + restore 脚本路径），累计战绩条。
需管理员项给「复制命令」按钮而非自动执行。

## 12. 测试

| 层 | 内容 |
|---|---|
| core.js（Node） | fmtBytes 边界；squarify 布局不变量（面积守恒、矩形互不重叠、全部在界内、无零宽高）；namePx 单调性 |
| 文件级断言（Node） | theme.css 必含 riseBar 关键帧与 reduced-motion 豁免行（防回归 v3 溢出 bug）；两模板都引用 scan-data marker |
| test-serve.ps1 | marker 注入后产物包含全部内联资产；/api/select 写盘；-Static 产物可独立打开 |
| 冒烟（手工，写入 README） | 真实扫描 → serve → 1360/1000/720px × reduce-motion 开/关无溢出（#probe 探针全 OK:Y）→ 提交 → execute -DryRun → final 页 |
| run-all.ps1 | 汇总以上自动部分 |

`#bottom / #tip / #geom / #probe` 开发钩子保留在正式版（hash 触发、无副作用），
作为将来回归验证的探针。

## 13. 验收标准

1. 真实数据全流程跑通：扫描 → 浏览器勾选 → 提交 → DryRun → 完成页。
2. 六个视口×动效组合无溢出（探针 OK:Y），玻璃降级实底正常。
3. SKILL.md 通读无未映射术语；铁律与命令速查逐字未动。
4. tests/run-all.ps1 全绿。
5. install.ps1 重装后 skill 目录包含 assets/。

## 14. 工作区备注

原型 v1-v4 与截图存于仓库根 `win-clean/docs/`（ingenuity 根目录下的散落工作区）；
定稿原型 v4 已复制入本项目 `docs/prototype-v4.html` 作为设计基准。
