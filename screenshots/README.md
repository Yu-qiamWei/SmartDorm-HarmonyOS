# screenshots/ · 运行截图归档

## 当前状态

本目录现有 **29 张截图**，全部来自 HarmonyOS API 17 手机模拟器（`Huawei_Phone`，`127.0.0.1:5555`）。

- 采集方式：`hdc shell snapshot_display -f /data/local/tmp/x.jpeg` → `hdc file recv` 取回
- 分辨率：1260 × 2720 px，设备密度 3.25 → 逻辑视口 **387.7vp × 836.9vp**
- **不是** Previewer 渲染图，**不是** 静态设计稿，**未做任何裁剪拼接**

## 性质声明

| 项 | 说明 |
| --- | --- |
| 设备类型 | **模拟器**（`const.product.model = emulator`），**不是真机** |
| API 版本 | 17（`const.ohos.apiversion = 17`，系统串 `OpenHarmony-5.0.5.165`） |
| 可宣称范围 | 仅代表模拟器上的运行效果，不代表真机表现 |
| 禁止表述 | 不得称"真机运行通过"、不得把本目录图片当作报告图 6.1 / 6.2 的真机证据 |

## 文件对照

| 文件 | 内容 |
| --- | --- |
| `01_index.jpeg` | 首次启动首页（修复前：标题与传感器数值折行） |
| `01b_index.jpeg` | 首页复抓 |
| `02_device_list.jpeg` | 设备管理列表（6 台设备） |
| `03_device_detail.jpeg` | 设备详情（真实 deviceId、参数字段） |
| `07_bright_reject.jpeg` | 亮度 110 越界被拒绝的 Toast |
| `08_delete_confirm.jpeg` | 删除二次确认弹窗 |
| `09_environment.jpeg` | 环境监测（5 类传感器） |
| `10_eval_report.jpeg` | 规则求值报告（引擎真实返回的耗时与计数） |
| `11_rule_list.jpeg` | 规则列表空态 |
| `12_rule_edit.jpeg` | 新建规则初始态 |
| `12c_rule_edit_state.jpeg` | 修复前：阈值 18℃ 但条件行仍显示 28℃（DEV-03 证据） |
| `12e_rule_edit_now.jpeg` | 编辑态（软键盘弹出） |
| `13_rule_saved.jpeg` | 修复前保存失败、提示为阶段二占位（DEV-02 证据） |
| `20_index_after_fix.jpeg` | **修复后**首页：标题单行、四个数值单行 |
| `21_rule_edit_new.jpeg` | 修复后新建规则 |
| `22_cond_sync_fixed.jpeg` | **修复后**三处阈值一致 16℃（DEV-03 回归） |
| `23_rule_list_one.jpeg` | 规则创建成功（共 1 条 · 启用 1 条） |
| `24_eval_triggered.jpeg` | 求值报告：去重跳过 1 条 |
| `28_two_rules.jpeg` | 两条规则（共 2 条 · 启用 2 条） |
| `29_rule_triggered.jpeg` | 触发后求值报告 |
| `30_exec_log.jpeg` | 数据统计页：四类计数 + 温度趋势折线图（101 条真实记录） |
| `31_stats_charts.jpeg` | 三张图表连续区间（含 T3-06 新增「设备操作次数」） |
| `32_scene_list.jpeg` | 场景模式（4 个预置场景） |
| `33_scene_switched.jpeg` | 切换后 `当前运行模式：STUDY` |
| `34_index_after_scene.jpeg` | 首页回显「运行模式：学习」 |
| `35_settings.jpeg` | 设置页上半（总开关、采样与容量） |
| `38_after_restart.jpeg` | **重启后**：规则数 0、运行模式回到手动（持久化失败证据） |
| `40_stats_final.jpeg` | 成功率按百分比显示（`0.0%`，修复前为裸比值 1） |

## 待补

DL-05 要求连续真实录屏覆盖 10 个环节，**当前未录制**，归档目录 `videos/` 仍为空。

逐项验证结论与缺陷根因见 `evidence/运行验证报告-模拟器.md`。
