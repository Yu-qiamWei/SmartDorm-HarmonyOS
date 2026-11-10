# 阶段二 · 页面 / 组件走查记录（源码级，非 Previewer 截图）

- 记录时间：2026-11-09（GMT+8）
- 记录人：工程师（角色化工作流，非真实人员）
- **性质声明（重要）**：本次会话**未启动 DevEco Studio Previewer**、**未产生任何 Previewer 截图**，
  也**未进行真机运行验证**。原因：当前为命令行会话，无法启动 IDE GUI；`hdc list targets=[Empty]`，
  已部署模拟器镜像最高 API 12 与 SDK API 17 不匹配；且 L1 构建在 SDK 组件扫描阶段失败
  （见 `evidence/构建日志-阶段二.md`）。
- 因此下表为**逐文件源码走查**结论（静态核对控件、回调、订阅、数据链路、布局令牌），
  **不是** L3 Previewer UI 验证证据，不得冒充图 6.1 / 图 6.2 真机运行效果。
- `screenshots/` 目录当前为空，见 `screenshots/README.md`。L3 Previewer 走查留待
  DevEco Studio GUI 可用后补做，并在此文件追加真实截图与标注。

---

## 1 十页逐页源码走查表

| # | 页面 / 路由 | 数据来源 | 主要可点击控件（全部有真实处理函数） | 反馈方式 | 订阅 / 取消订阅 | 平板适配 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `Index` / `pages/Index` | `AppDataRepository.getState()` | 六模块入口「进入」×6、`DeviceCard` 进详情 / 快速开关、刷新聚合数值、页头设置 | `RouteMap.push` 真实跳转；`ToastHost.showResult` 反馈 `CommandResult`；`notify()` 真实刷新 | ✅ `aboutToAppear` 订阅、`aboutToDisappear` 取消 | ✅ `mediaquery` + `GridRow/GridCol` |
| 2 | `DeviceList` / `pages/DeviceList` | `listDevices()` | 类型选择 ×6、添加设备、每卡片删除（二次确认）与进详情 / 快速开关 | `addDevice/removeDevice` 契约 + Toast；`ConfirmDialog.showDialog` | ✅ | ✅ `GridRow/GridCol` |
| 3 | `DeviceDetail` / `pages/DeviceDetail` | `findDevice(deviceId)` + `logs.operations` 过滤 | 电源开关、参数 −/+（门锁为上锁/解锁）、Mock 诊断 6 按钮、去设备列表 | `setPower/setParam/setDeviceStatus/setOnline` 契约 + Toast | ✅ | 两列诊断栅格 |
| 4 | `Environment` / `pages/Environment` | `state.environment` + `logs.environment` | 4 个 `SensorCard`（输入框 / 步进 / 应用）、人体存在置位、模拟开关、手动采样、求值报告 | `adjustEnvironment/evaluateRules/updateSettings` 契约 + Toast | ✅ | 顶部读数条 + 卡片纵列 |
| 5 | `RuleList` / `pages/RuleList` | `state.rules` | 新建规则、查看执行记录、求值说明、`RuleCard` 启停/编辑/删除 | 导航 + `toggleRule/removeRule` 契约 + Toast + 二次确认 | ✅ | 列表纵列 |
| 6 | `RuleEdit` / `pages/RuleEdit` | `RouteParams` + `listDevices()` | 名称输入、优先级 ±、阈值 ±、添加/移除条件、添加/移除动作、切换目标设备、保存、取消 | 页面局部 `@State` 真实更新 + `validateSensorValue` 真实校验 + `createRule/updateRule` 契约 + Toast + `back()` | ✅ | 表单纵列 |
| 7 | `SceneList` / `pages/SceneList` | `state.scenes` | 新建自定义场景、查看切换日志、恢复说明、`SceneCard` 切换/编辑/删除 | 导航 + `applyScene/removeScene` 契约 + Toast + 二次确认 | ✅ | 卡片纵列 |
| 8 | `SceneEdit` / `pages/SceneEdit` | `RouteParams` + `listDevices()` | 名称输入、全部开/关、逐设备目标电源切换、保存、取消 | `@State` 真实更新 + `createScene/updateScene` 契约 + Toast | ✅ | 设备行纵列 |
| 9 | `Statistics` / `pages/Statistics` | 四类真实日志 + `state.environment` | 四类记录筛选 ×4 | `selectedType` 真实过滤 + Toast；`LineChart`/`BarChart` 接收真实数组自绘 | ✅ | ✅ `mediaquery` 切 1/2 列图表 |
| 10 | `Settings` / `pages/Settings` | `state.settings` | 两个总开关、采样间隔 ±、日志上限 ±、手动保存、数据导出、重置全部数据、说明 | `updateSettings/flush/exportState/resetData` 契约 + Toast + 二次确认 | ✅ | 分组卡片纵列 |

---

## 2 逐项核对（源码级）

| 核对项 | 结论 | 依据 |
| --- | --- | --- |
| 10 页全部存在且 `main_pages.json` 注册 10 项、首项 `pages/Index` | ✅ | 自动脚本比对 `RouteMap.ALL` 与 `main_pages.json` 逐字一致 |
| 每个页面可被路由访问 | ✅ | 10 个 `.ets` 文件均在 `ets/pages/` 且 url 与注册表一致 |
| 页面 `aboutToAppear()` 订阅并保存 `unsubscribe`、`aboutToDisappear()` 取消订阅 | ✅ | 10/10 页面均实现；无页面在 `build()` 内订阅 |
| 页面不注册定时器 / 不写日志 / 不 import `PreferencesStore` | ✅ | 唯一 `setInterval` 在 `mock/TimerHost.ets`；页面只 import `AppDataRepository` 与契约 |
| 无空 `onClick` / 无装饰性按钮 | ✅ | 自动扫描 `.onClick(() => {})` 为空；逐控件均有导航 / 契约 + Toast / 局部状态 / 二次确认 |
| 图表为 Canvas 真实自绘、接收真实数组 | ✅ | `LineChart` / `BarChart` 仅用核验清单第 25/26 项绘图方法；`Statistics` 传入 `buildLineModel(真实 logs)` 与 `buildLiveEnvironmentBarModel(真实 environment)`（5 根真实柱） |
| 图表组件无静态图片 / 无内嵌演示数据点 | ✅ | `grep` 扫描 `components/chart/` 无图片资源引用；空数据由 `fillText` 自绘提示 |
| 状态反馈明显（FAULT / OFFLINE 区分） | ✅ | `StatusBadge` 四态不同色值 + 补充说明文字（源码核对，待 Previewer 视觉确认） |
| 统一设计令牌、无散落硬编码色值 | ✅ | 颜色 / 圆角 / 间距 / 字号全部取自 `ThemeTokens`，与 `color.json` / `float.json` 对齐 |
| 首页 ≥6 类设备卡片、六模块入口 | ✅ | `MockDataFactory` 产出 6 类设备；`Index` 用 `GridRow/GridCol` 渲染 6 张 `DeviceCard` 与 6 个入口 |
| 平板断点 `mediaquery.matchMediaSync` + `GridRow/GridCol` | ✅ | `Index` / `DeviceList` / `Statistics` 使用；断点值由 `ThemeTokens.tabletQuery()` 统一提供 |
| 10 页布局避免同一模板 | ✅ | 首页聚合+栅格、列表栅格、详情诊断区、环境读数条+传感器卡、表单页、图表页、分组设置页各不相同 |
| 重要设备状态在线 / 离线 / 故障可见 | ✅ | `DeviceCard` 使用 `StatusBadge`；`DeviceDetail` 有「模拟/调试」诊断区（Q-15，明确标注非真实硬件故障） |

---

## 3 待补做（未完成，不得预填）

| 项 | 前置条件 | 说明 |
| --- | --- | --- |
| L3 DevEco Previewer 10 页真实截图 | DevEco Studio GUI 可用 + L1 构建/组件解析通过 | 截图须标注「Previewer 截图，非真机运行」，存 `screenshots/` |
| Previewer 多尺寸断点视觉核对（横 / 竖屏） | 同上 | 补充真实观察结论，替换本文件第 2 节的「源码核对」标注 |
| 图 6.1 / 图 6.2 / DL-05 连续录屏 | 接入 API 17 HarmonyOS 平板或匹配镜像 | 当前 `hdc list targets=[Empty]`，列为未完成 |
| 表 5.1「实际结果 / 是否通过 / 证据路径」 | ST-05 真实测试执行 | 结果列**保持空白**，本阶段不预填 |
