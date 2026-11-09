# 智寓 —— HarmonyOS 智能宿舍管家

> 面向大学生宿舍的智能设备管理 + 环境监测 + **自动化规则编排**应用。
> 全部设备与传感器由 Mock 层模拟，但**设备控制、条件判断、状态变化、规则联动均为真实可运行业务逻辑**，不存在预设假效果。

![status](https://img.shields.io/badge/status-开发中-yellow)
![platform](https://img.shields.io/badge/HarmonyOS-5.0.5%20%2F%20API%2017-007DFF)
![lang](https://img.shields.io/badge/ArkTS-ArkUI-3178C6)

---

> ## ⚠️ 状态声明（务必先读）
>
> - 本文档对应 **ST-01 ~ ST-04 已完成** 的真实进度；**ST-05（测试执行）进行中**。
> - **ST-04 已通过 API 17 模拟器设备端运行验证**：在 API 17 模拟器（`127.0.0.1:5555`，OpenHarmony-5.0.5.165）完成 12 步冷启动重启验收——`preferences` 落盘原文可拉回、`bootCount 1→2`、`firstLaunchAt` 跨重启不变、设备/场景/设置/日志五类数据逐字段一致；`AppDataRepository.flush()` 现已为**真实写入**（非桩函数）。L2 Node 纯逻辑测试 **307 断言 0 失败**（`evidence/l2-阶段五.txt`；282 为阶段四快照 `l2-阶段四.txt`）。ST-05：L2 307 断言全通过；L4 前两批 10 个用例已判定并归档（含部分达成 / 未达成如实标注）；第三批 7 个用例与修复后 HAP 回归执行中；DL-05 连续真实录屏（物理真机演示）经用户 2026-11-09 裁定**豁免**、不再作为交付前置；L3 Previewer 走查尚未实跑。
> - **诚实边界（不影响「代码完成 / 构建通过 / 模拟器验证通过」三态结论）**：① 规则分区端到端 UI 创建未由设备自动化覆盖（机制与已验证分区同管线，由 L2 分块 + 逐区降级统一覆盖）；② C6「手工写坏块后重启」因 `hdc shell` 无沙箱写权限无法原样复现，已用 L2 注入 + 方案 D（清空存储后冷启动不崩溃）替代；③ 导出/落盘 mtime 微序为 `@ohos.data.preferences` 的冗余回写，非数据丢失。
> - 已构建产出仍为 **未签名 HAP**（`entry-default-unsigned.hap`）；L3 DevEco Previewer 走查尚未实跑（需 GUI，属 ST-05 范畴）。
> - 第 9/10 节「运行截图 / 功能演示」证据见 `evidence/` 与 `screenshots/`（均为 **API 17 模拟器设备端实拍（hdc 采集）**，非 Previewer、非静态图、非预设效果；**非物理真机，不得据此宣称物理真机运行通过**，**物理真机运行演示经用户 2026-11-09 裁定豁免、未执行**；报告图 6.1/6.2 改由 API 17 模拟器 `hdc` 设备端实拍证据覆盖，须如实标注非物理真机）。

---

## 1. 项目名称

| 项 | 内容 |
| --- | --- |
| 中文名称 | 智寓 —— HarmonyOS 智能宿舍管家 |
| 英文 / 包名 | SmartDorm / `com.smartdorm.harmony` |
| 选题方向 | 主题三：**智能场景规则编排与交互仿真系统** |
| 代码仓库 | <https://github.com/Yu-qiamWei/SmartDorm-HarmonyOS> |
| GitHub 账号 | `Yu-qiamWei` |
| 开发方式 | 个人独立完成（需求、架构、编码、测试、文档、Git 全流程单人承担） |
| 应用版本 | 1.0.0（versionCode 1000000） |

---

## 2. 项目介绍

宿舍是大学生每天生活时间最长的空间，但空调、灯光、窗帘、插座等设备彼此孤立，学生只能逐个手动开关，既费事又容易忘关导致浪费。市面上的智能家居 App 多绑定厂商私有硬件与云端账号，无法用于课程实践，也难以覆盖"宿舍"这一多人共用、场景高频切换的真实环境。

**智寓**把宿舍里的一整套设备抽象成软件对象，在**纯软件仿真**的前提下，把"智能"落在**规则引擎**上：用户用图形化条件-动作编辑器描述"当 [温度 > 28℃ 且 有人] 持续 [5 分钟] → 则 [开空调 制冷 24℃]"，应用按固定周期评估所有规则，命中即真实执行设备指令、写执行日志、驱动界面与图表联动。设备状态、环境读数、规则执行、操作留痕构成一个闭环，**每一步都可被观察、可被追溯、可被复现**。

项目刻意选择"仿真"而非"接硬件"，是为了让评分者与使用者**无需任何外部设备**即可完整验证系统行为；同时 Mock 层被严格限制在"产生传感器读数 / 模拟设备物理响应"这一薄边界内，向上暴露的接口与真实 IoT 设备完全一致，未来替换为真实设备驱动不需要改动业务层。

---

## 3. 开发背景

| 维度 | 说明 |
| --- | --- |
| 课程要求 | 《移动应用开发基础》期末大作业，要求使用 **ArkTS + ArkUI + Ability Kit** 完成一个可真实运行的 HarmonyOS 原生应用，禁止预设假效果、禁止装饰性按钮 |
| 技术背景 | HarmonyOS NEXT 起 Stage 模型与 ArkTS 强类型成为唯一路径，`@ohos.data.preferences` 等系统能力以 Kit 形式收敛；本项目全部 API 均按 **API 17 官方声明文件逐项实测核验**后写入，不引用旧版或废弃接口 |
| 现实痛点 | 宿舍用电浪费与"忘关设备"是普遍问题；多人共用环境下，规则冲突（两条规则同时操作同一设备同一参数）必须有确定的仲裁策略，否则行为不可预测 |
| 设计取向 | ① 业务逻辑与 UI 严格分层，页面无写权限；② 规则评估结果确定性可复现（排序键固定、冲突先到先得）；③ 一切"看起来智能"的效果都必须能追到一条真实日志 |

---

## 4. 功能

### 4.1 功能模块

| # | 模块 | 主要能力 | 实现状态 |
| --- | --- | --- | --- |
| 1 | **首页控制中心** | 全局总开关、场景快捷入口、关键设备一键控制、环境概览、规则触发摘要 | ✅ 页面与逻辑已落地 |
| 2 | **设备管理** | 设备列表 / 详情、开关与参数调节（亮度、温度、档位、窗帘开合度）、参数越界拒绝并记日志 | ✅ 页面与服务已落地 |
| 3 | **环境监测** | 温度、湿度、光照、AQI、人体存在 5 类读数、周期刷新、趋势折线图 | ✅ 页面与服务已落地 |
| 4 | **自动化规则编排** | 多条件（与/或）组合、条件持续时长、多动作顺序执行、启停、优先级 | ✅ 引擎/服务已落地，编辑页已落地 |
| 5 | **场景模式** | 场景一键切换、场景内设备状态批量应用、切换留痕 | ✅ 页面与服务已落地 |
| 6 | **数据统计** | 设备运行统计、规则触发次数、执行成功率、日志查询与筛选 | ✅ 页面与服务已落地；温度趋势折线图、设备操作次数等图表见 `screenshots/31_stats_charts.jpeg` |
| 7 | **设置** | 自动化总开关、模拟周期、日志清理、数据导出、关于 | ✅ 页面已落地 |

### 4.2 规则引擎能力（本项目的核心）

| 能力 | 说明 |
| --- | --- |
| 多条件组合 | AND / OR 两种组合方式；单条件支持 `> >= < <= == !=` 六种比较符 |
| 持续时长 | 条件需连续满足 N 秒才触发，避免抖动误触发 |
| 边沿触发 | 条件由"不满足"变为"满足"才执行；**持续成立不重复执行**（去重） |
| 顺序执行 | 多动作按定义顺序串行执行，前一步失败不阻断后续并逐一记录 |
| 冲突仲裁 | 同一轮评估中多条规则操作**同一设备的同一参数**时，按 `优先级↑ → createdAt↑ → id` 确定性排序，**先到者执行，后者标记 `SKIPPED_CONFLICT`** |
| 执行留痕 | 每次评估产出 `RuleExecutionLog`（命中/跳过/冲突/失败 + 原因 + 时间戳） |
| 幂等保护 | 通过 `WriteGuard` 保证一条动作指令在同一轮评估中不被重复认领 |

### 4.3 与"假效果"的边界

- ✅ **真实**：条件比较、去重判定、冲突仲裁、设备状态变更、日志写入、图表聚合、页面刷新
- ⚠️ **模拟（Mock 层，边界清晰）**：`EnvironmentSimulator` 按设定周期产生符合物理常识的传感器读数；`MockDeviceAdapter` 模拟设备收到指令后的物理响应。二者仅实现"读传感器 / 执行设备指令"两类接口，**不参与任何业务判断**

---

## 5. 技术架构

### 5.1 分层结构（5 层 + 应用入口）

```
┌──────────────────────────────────────────────────────────┐
│  L1  页面展示层  pages/ + components/                     │
│      ArkUI 声明式 UI，只读状态、只发指令，无写权限          │
├──────────────────────────────────────────────────────────┤
│  L2  业务逻辑层  service/                                 │
│      DeviceService / EnvironmentService / RuleService     │
│      RuleEngine / RuleMatcher / RuleActionExecutor        │
│      SceneService / StatisticsService / LogService        │
│      ExportService / WriteGuard                           │
├──────────────────────────────────────────────────────────┤
│  L3  数据模型层  model/                                   │
│      Device / EnvironmentData / AutomationRule            │
│      AutomationCondition / AutomationAction / Scene       │
│      OperationLog / RuleExecutionLog（8 个核心对象）       │
├──────────────────────────────────────────────────────────┤
│  L4  数据存储层  store/                                   │
│      AppDataRepository（单一数据入口 + 串行写入队列）       │
│      StorageKeys / PreferencesOptions / RepositoryContract │
├──────────────────────────────────────────────────────────┤
│  L5  Mock 仿真层  mock/                                    │
│      EnvironmentSimulator / MockDeviceAdapter              │
│      MockDataFactory / TimerHost（全局单例定时器）          │
└──────────────────────────────────────────────────────────┘
             ▲ 依赖方向严格单向：L1 → L2 → L3 / L4 / L5
             │ 入口层 entryability/EntryAbility.ets
             │ 通过 ServiceFacade.initialize(context) 集中注入依赖
```

### 5.2 关键运行时机制

| 机制 | 实现要点 |
| --- | --- |
| 单一数据入口 | 所有状态变更经 `AppDataRepository`，页面与组件**只读**，写入权仅属于 L2 服务层 |
| 串行写入队列 | 写操作排队执行，避免并发覆盖与半写状态 |
| 变更四面一致 | 内存 `AppState` → 订阅通知 → 持久化 → 界面刷新，四侧同步推进 |
| 统一返回类型 | 所有服务方法返回 `CommandResult<T>`，成功/失败/冲突/非法参数统一编码，不抛裸异常 |
| 依赖集中注入 | `ServiceFacade.initialize(context)` 一次性完成 `ExportService.init` / `DeviceService.installMockLookup` / `EnvironmentService.setEvaluationTrigger`，`EntryAbility.onCreate` 为唯一调用点 |
| 定时器单例 | `TimerHost` 全局唯一，避免多页面重复起停导致评估周期漂移 |

### 5.3 主要技术选型

| 层 | 技术 |
| --- | --- |
| 语言 / UI | ArkTS（严格模式）+ ArkUI 声明式语法 |
| 应用模型 | Stage 模型，`UIAbility` 作为唯一入口 |
| 持久化 | `@ohos.data.preferences`（键值型，分区分键 + 分块序列化） |
| 状态管理 | `@State` / `@Prop` / `@Link` / `AppStorage` + 自定义订阅分发 |
| 图表 | 自绘组件（`LineChart` / `BarChart`，`Canvas` 绘制，无第三方图表库） |
| 第三方依赖 | **运行时零依赖**；仅 `@ohos/hypium`、`@ohos/hamock` 作为测试期 devDependencies |

---

## 6. 开发环境

> 以下为**本机实测基线**，非虚构版本。

| 项 | 版本 / 取值 |
| --- | --- |
| 操作系统 | Windows 10 / 11 (win32) |
| IDE | DevEco Studio **5.0.13.240** |
| HarmonyOS SDK | **5.0.5（API 17）**，`compatibleSdkVersion` / `targetSdkVersion` 均为 `5.0.5(17)` |
| 构建工具 | hvigor **5.17.6** |
| Node.js | **v22.22.2** |
| 工程模型 | `modelVersion: 5.0.0`，Stage 模型，`runtimeOS: HarmonyOS` |
| 目标设备类型 | `phone` / `tablet` / `2in1`（以手机为主要适配目标） |
| 版本控制 | Git，远程托管 GitHub（HTTPS 协议） |

### 6.1 环境注意事项（实测踩坑，供复现者参考）

1. **`DEVECO_SDK_HOME` 必须指向 SDK 根目录**，即 `D:\DevEco Studio\sdk`，**不能**指向 `sdk\default`。
   指向 `sdk\default` 会导致 hvigor 报 `SDK component missing. Please verify the integrity of your SDK.`
   原因：`hvigor-ohos-plugin` 在 `_isHarmonyOS = true` 时**不会读取** `local.properties`，SDK 根只认环境变量。
2. **`local.properties` 已被 `.gitignore` 排除**，克隆后需自行生成或由 DevEco Studio 自动创建。
3. **不要把日志或脚本写进工程根的 `build\` 目录**——hvigor 每次构建都会删除该目录。

---

## 7. 目录说明

```
SmartDorm-HarmonyOS/
├── AppScope/                     # 应用级配置与资源（app.json5、应用图标）
├── entry/                        # 主模块（entry HAP）
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/     # 应用入口 EntryAbility（唯一 UIAbility）
│   │   │   ├── pages/            # L1 页面层，10 个页面
│   │   │   ├── components/       # L1 可复用组件（chart / common / device / env / rule / scene）
│   │   │   ├── service/          # L2 业务逻辑层，14 个服务与引擎
│   │   │   ├── model/            # L3 数据模型层，8 个核心对象 + 枚举/结果/报表
│   │   │   ├── store/            # L4 数据存储层（仓库、键定义、选项）
│   │   │   ├── mock/             # L5 Mock 仿真层（环境模拟、设备适配、定时器）
│   │   │   └── common/           # 公共基础层（常量、路由、主题、ID、FIFO 等）
│   │   ├── resources/            # 字符串、颜色、图片、页面路由表
│   │   └── module.json5          # 模块与 Ability 声明
│   └── build/                    # 构建产物（已 gitignore）
├── docs/                         # 软件需求说明书（PRD，12 项成节）
├── design/                       # 系统架构设计、类图/时序图、各阶段任务列表、测试执行方案
├── stages/                       # 各阶段阶段报告
├── tests/l2/                     # L2 Node 侧纯逻辑断言：gen.js / run.js / t4*.js 判据 / stubs
├── evidence/                     # 证据归档：环境检查、逐阶段构建日志、阶段四验收报告、L2 断言输出、
│                                 #   preferences 落盘原文（prefs_*）、导出快照（export_*）、设备侧 UI dump（device/）
├── screenshots/                  # 设备端实拍截图归档（API 17 模拟器，见第 9 节与本目录 README）
├── videos/                       # 连续真实录屏归档（当前为空：DL-05 物理真机演示经用户裁定豁免，不再作为交付前置，见第 10 节）
├── deliverables/                 # 最终交付包（Word 报告等）
├── scripts/                      # 辅助脚本（build-hap.bat 命令行构建、设备采集 / 布局脚本）
├── hvigor/                       # hvigor wrapper
├── build-profile.json5           # 构建配置（产品、SDK 版本，当前未配置签名）
├── oh-package.json5              # 包描述与依赖
├── hvigorfile.ts                 # 构建脚本入口
└── README.md                     # 本文件
```

**源码规模（实测）**：`entry/src/main/ets` 下共 **75 个 `.ets` 文件、约 12,981 行 ArkTS 代码**（含 ST-04 持久化层与 ST-05 缺陷修复后的增量）。

---

## 8. 编译运行方法

### 8.1 前置条件

- DevEco Studio 5.0.13.240 或更高
- HarmonyOS SDK **5.0.5（API 17）** 已安装
- Node.js ≥ 18（实测 v22.22.2）
- 目标设备 / 模拟器 API Level **等于 17**（低版本会因 API 不匹配无法安装）

### 8.2 方式一：DevEco Studio（推荐）

1. `File → Open`，选择工程根目录 `SmartDorm-HarmonyOS`
2. 等待 `Sync` 完成（首次会生成 `local.properties` 与 `oh_modules`）
3. 选择真机或 API 17 模拟器作为运行目标
4. 点击 `Run 'entry'`（`Shift + F10`）

### 8.3 方式二：命令行构建 HAP

```bash
# Windows
scripts\build-hap.bat
```

脚本等价于：

```bash
export DEVECO_SDK_HOME="D:/DevEco Studio/sdk"   # 注意：SDK 根目录，不是 sdk/default
node "D:/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
     --mode module -p product=default assembleHap --no-daemon
```

产物路径：`entry/build/default/outputs/default/entry-default-unsigned.hap`

> ⚠️ 该产物为**未签名** HAP（工程未配置 `signingConfigs`，hvigor 日志提示 `Will skip sign 'hos_hap'`）。**实测**：该未签名包在 API 17 模拟器 `127.0.0.1:5555` 上通过 `hdc install -r` **直接安装成功**（该模拟器未强制签名校验），见 `evidence/运行验证报告-模拟器.md` §2.3。此结论**仅对当前模拟器成立，不能推广为"真机也不需要签名"**；正式真机分发仍需在 DevEco Studio 配置签名（`Project Structure → Signing Configs`）后重新构建。

### 8.4 安装 / 启动 / 重启（API 17 设备，实测命令）

```bash
hdc list targets                       # 期望可见 127.0.0.1:5555
hdc shell param get const.ohos.apiversion   # 期望 17
hdc install -r entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell aa start -a EntryAbility -b com.smartdorm.harmony
hdc shell ps -ef | grep smartdorm      # 确认进程拉起
```

冷启动 / 重启验证（阶段四 12 步验收实测原文，见 `evidence/阶段四验收报告.md` §3.2）：

```bash
hdc shell bm clean -d                  # 清空应用数据
hdc shell aa force-stop com.smartdorm.harmony
hdc shell aa start -a EntryAbility -b com.smartdorm.harmony
```

### 8.5 复跑 L2 纯逻辑断言

```bash
node tests/l2/run.js
```

无需设备，`gen.js` 生成 `.gen/src` → DevEco 自带 tsc 编译 → 逐桶执行断言，阶段五实测 **307 断言 0 失败**（输出归档 `evidence/l2-阶段五.txt`）。详见 `tests/l2/README.md` 与第 12 节。

### 8.6 构建成功判定标准

- 出现 `Finished ::entry:default@CompileArkTS`
- 出现 `BUILD SUCCESSFUL`
- 全文**无** `ArkTS:ERROR`

> 注意：`COMPILE RESULT:SUCCESS` **不会**在成功时打印，该行仅在失败时输出 `COMPILE RESULT:FAIL {ERROR:n WARN:n}`，不能用它作为成功依据。

---

## 9. 运行截图

**已归档设备端实拍截图**，位于 `screenshots/`，全部来自运行中的 **API 17 设备（模拟器 `127.0.0.1:5555`，`OpenHarmony-5.0.5.165`）**，由 `hdc shell snapshot_display` 采集、`hdc file recv` 取回，分辨率 1260 × 2720 px，**未裁剪拼接、非 Previewer 渲染、非静态设计稿、非预设假效果**。采集方式与逐文件对照见 `screenshots/README.md` 与 `evidence/运行验证报告-模拟器.md`。

> **载体诚实边界**：本批截图的运行载体为 API 17 **模拟器**（`const.product.model = emulator`），**不是物理真机**；可据此说明"应用在 API 17 设备端真实运行"，但**不得据此宣称"真机运行通过"**，也不作为报告图 6.1 / 6.2 的物理真机证据；**物理真机运行演示经用户 2026-11-09 裁定豁免、未执行**，报告图 6.1 / 6.2 改由本批 API 17 模拟器设备端实拍证据覆盖并如实标注载体。

| 功能域 | 代表截图（`screenshots/` 下真实文件） | 对应观察点 |
| --- | --- | --- |
| 首页控制中心 | `01_home.jpeg`、`20_index_after_fix.jpeg`、`34_index_after_scene.jpeg` | 环境概览、6 类设备卡片、运行模式回显、修复前后标题/数值折行对比 |
| 设备管理 | `02_device_list.jpeg`、`03_device_detail.jpeg`、`07_bright_reject.jpeg`、`08_delete_confirm.jpeg` | 列表 / 详情、亮度越界被拒 Toast、删除二次确认 |
| 环境监测 | `09_environment.jpeg`、`09_rule.jpeg` | 5 类传感器读数与采样 |
| 自动化规则编排 | `12_rule_edit.jpeg`、`23_rule_list_one.jpeg`、`28_two_rules.jpeg`、`24_eval_triggered.jpeg`、`29_rule_triggered.jpeg`、`10_eval_report.jpeg` | 规则创建 / 列表 / 两条规则 / 求值报告（去重跳过） |
| 执行记录与统计 | `30_exec_log.jpeg`、`31_stats_charts.jpeg`、`40_stats_final.jpeg` | 四类计数、温度趋势折线图、三张图表连续区间、成功率百分比 |
| 场景模式 | `32_scene_list.jpeg`、`33_scene_switched.jpeg`、`06_scene_study.jpeg` | 4 个预置场景、切换后 `当前运行模式：STUDY` |
| 设置与持久化 | `02_settings.jpeg`、`35_settings.jpeg`、`38_after_restart.jpeg` | 设置页、重启后数据回读 |
| ST-05 L4 第一批用例 | `st05_n01_home_before.jpeg` / `st05_n01_home_after.jpeg` / `st05_n01_log_history.jpeg`、`st05_n04_home_sleep.jpeg`、`st05_n05_brightness80.jpeg` / `st05_n05_home_return.jpeg`、`st05_e01_nochange_toast2.jpeg` | 手动开灯、场景批量变更、回寝恢复用户预设、重复开启无变更 |

阶段四 **12 步冷启动重启验收**的截图清单与逐字段比对见 `evidence/阶段四验收报告.md` §3.2 / §3.6。

---

## 10. 功能演示

### 10.1 连续真实录屏（DL-05）：用户裁定豁免物理真机演示，保留需求描述并如实标注

**用户 2026-11-09 裁定「本项目不需要实机演示」并明确「继续完成真机模拟」**：据此**豁免物理真机运行展示类交付**——DL-05 连续真实录屏、报告图 6.1 / 图 6.2 的真机截图要求不再作为交付前置。**DL-05 的 P0 需求描述与 10 环节验收标准原样保留并如实标注已豁免**，不写成「已完成」、不以 Previewer 截图 / 静态图 / 分环节截图冒充物理真机录屏；改由 **API 17 模拟器经 `hdc` 的设备端真实执行证据**（逐环节实拍截图 + 状态导出 + PRD 第 16 章表 5.1 真实结果）覆盖验证，**测试判据一条不降**。`videos/` 目录当前为空系豁免结果，非「待完成缺陷」。录屏 10 环节（需求原始描述，保留）：

```
启动 → 首页 → 手动控制 → 环境变化 → 创建规则 → 触发规则
     → 查看执行记录 → 切换场景 → 查看历史 → 重启验证数据恢复
```

产出后归档至 `videos/`。

### 10.2 分环节设备端证据链（已完成，非录屏）

连续录屏虽未产出，但上述关键环节已有**设备端实拍截图 + 状态导出**的分环节证据，可用于核对流程真实性：

| 环节 | 现有证据 |
| --- | --- |
| 启动 / 首页 | `screenshots/01_home.jpeg`、`20_index_after_fix.jpeg`；`evidence/运行验证报告-模拟器.md` §3 启动链路日志 |
| 手动控制 | `screenshots/st05_n01_home_before.jpeg` → `st05_n01_home_after.jpeg`；`evidence/device/st05_n01_before.json` / `st05_n01_after.json` |
| 环境变化 / 创建规则 / 触发规则 | `screenshots/09_environment.jpeg`、`23_rule_list_one.jpeg`、`24_eval_triggered.jpeg`、`29_rule_triggered.jpeg`、`10_eval_report.jpeg` |
| 查看执行记录 / 切换场景 / 查看历史 | `screenshots/30_exec_log.jpeg`、`31_stats_charts.jpeg`、`33_scene_switched.jpeg`、`st05_n04_home_sleep.jpeg` |
| 重启验证数据恢复 | `screenshots/38_after_restart.jpeg`；`evidence/阶段四验收报告.md` §3.2（12 步逐字段比对）；`evidence/export_before.json` / `export_after.json` / `prefs_before` / `prefs_after` |

> 分环节证据**不等价于**连续物理真机录屏；DL-05 物理真机演示经用户裁定豁免，改由本节 API 17 模拟器 `hdc` 设备端证据链覆盖验证。截图载体为 API 17 模拟器、非物理真机，见第 9 节载体诚实边界。

---

## 11. 持久化说明

### 11.1 设计要点（方案基线，见 `design/系统架构设计.md`；以下方案均已在 ST-04 落地，落地状态见 11.2）

| 设计点 | 方案 |
| --- | --- |
| 底层能力 | `@ohos.data.preferences`（键值型） |
| 唯一入口 | 全部读写经 `AppDataRepository`，页面与组件无写权限 |
| 分区存储 | 按 `StoragePartition` 分区（设备 / 环境 / 规则 / 场景 / 日志 / 设置），分区独立键 |
| 串行写入 | 写操作进队列串行执行，避免并发覆盖与半写 |
| 分块序列化 | 单值超过 `CHUNK_MAX_CHARS = 7000` 时切块存储，读取时按序拼接，规避 `MAX_VALUE_LENGTH = 8192` 上限 |
| 运行期元数据 | `smartdorm.meta.runtime` 单独记录版本号与写入形态 |
| 合并刷盘 | 同一轮内多次变更合并为一次 `flush`（MI-16），减少 I/O |
| 加载一致性 | 三级校验：版本号 → 分区块完整性 → 反序列化结构校验，任一失败降级为空态并记日志，**不崩溃** |
| 日志上限 | `OperationLog` 1000 / `RuleExecutionLog` 1000 / `EnvironmentLog` 2000 / `SceneSwitchLog` 500，FIFO 淘汰 |

### 11.2 ST-04 实现状态（已落地，代码完成 ✅ / 构建通过 ✅ / 设备端验证通过 ✅）

`AppDataRepository.flush()` **已为真实写入**（不再是桩函数）；应用退出后数据保留。实现清单与签名对照见 `evidence/阶段四验收报告.md` §一。

| 实现点 | 落地情况 |
| --- | --- |
| 分区分键 | `StorageKeys` 定义 **9 个分区**、分块键 / 头键生成与 chunk 索引解析；`smartdorm.<partition>.hdr` + `.cNNNN` |
| 分块序列化 | `Serializer` 分块编码（头 + 块四字段 `p/i/t/d`）、运行时元信息 `smartdorm.meta.runtime` 编解码、版本迁移头校验；规避 `MAX_VALUE_LENGTH = 8192` |
| 串行写队列 | `WriteQueue` 单链串行、分区合并、两路防抖、执行期快照、失败保 dirty |
| 版本迁移 | `SchemaMigration` `v0→v1` 迁移、版本越界拒绝写回 |
| **导出前落盘** | `ExportService.exportToFilesDir` 改为 `async Promise<CommandResult<string>>`，**首行 `await AppDataRepository.getInstance().flush()`**；落盘失败即中止导出并返回 `STORAGE_ERROR`，绝不谎报成功（4 处签名联动改异步） |
| 仓储接线 | `AppDataRepository.load()` / `flush()` / `saveNowSync()` / `reset()` / `getDiagnostics()` / `getRuntimeMeta()`，**9 分区逐分区降级** |
| 生命周期收尾 | `EntryAbility.onCreate` → init + load；`onBackground` → flush；`onDestroy` → `saveNowSync()` 同步落盘 |
| 逐分区降级 | 三级校验（版本号 → 分区块完整性 → 反序列化结构校验），某一分区失败仅该区降级为空态并写诊断，**不影响其他分区、不崩溃** |
| 日志上限 | `OperationLog` 1000 / `RuleExecutionLog` 1000 / `EnvironmentLog` 2000 / `SceneSwitchLog` 500，FIFO 淘汰 |

#### 11.2.1 12 步冷启动重启验收（已通过）

`bm clean -d` → `aa start` 冷启动 → 记录首指纹 → 改设备 / 建规则 / 触发 / 切场景 / 改设置 / 造日志 → 手动保存（提示「保存结果：操作成功（已落盘，残留待写分区 0 个）」）→ `aa force-stop` 真实杀进程 → `aa start` 冷启动 → 逐字段比对。实测结论：

- `bootCount` **1 → 2**，`firstLaunchAt` **跨重启不变**（`1794210264259`），证明运行时元信息写入并被读回；
- `devices[0].id` / `createdAt` **完全一致**（证明是读回而非重新生成）、`powerOn=false` 与设定一致；
- `currentMode=STUDY`、`currentSceneId`、`logLimit=1100`、`simulationEnabled=true` 逐项一致；
- 落盘原文 `prefs_before` / `prefs_after` 可拉回，含 `.hdr` / `.c0000` 分块键，体积 146 085 B → 158 390 B 随数据增长；**12 项字段全部 PASS**。

#### 11.2.2 降级与诚实边界（如实标注，不改变三态结论）

| 项 | 结论 |
| --- | --- |
| 方案 C（解码侧，L2 注入坏块 / 坏头 / 坏版本） | ✅ 逐分区独立降级，`tests/l2/t402_*.js` / `t403_repository.js` 覆盖 |
| 方案 D（`bm clean -d` 清空存储后冷启动） | ✅ 进程正常拉起（未崩溃）、回默认态、诊断可见 |
| C6「手工写坏块后重启」 | ⚠️ **设备侧未能原样复现**：`hdc shell` 为 `uid=2000(shell)`，对应用沙箱 `Permission denied`；已用 L2 注入 + 方案 D 替代，**不计入通过** |
| 规则分区端到端 UI 创建 | ⚠️ 提交控件在设备自动化中未触发，`rules` 分区始终为 0 条；但其使用与设备/场景**完全相同的分块管线**（L2 K 系列 + 逐区降级覆盖），属「机制已验证、端到端 UI 创建未跑通」，不冒领通过 |
| 导出 / 落盘 mtime 微序 | `@ohos.data.preferences` 导出后一次冗余回写（内容相同），非数据丢失；内容一致性由三份导出交叉印证 |

**证据清单**：`evidence/阶段四验收报告.md`、`evidence/阶段四-构建日志.txt`（`BUILD SUCCESSFUL`、CompileArkTS 18 s 169 ms、0 个 `ArkTS:ERROR`、HAP 1 437 310 bytes）、`evidence/l2-阶段四.txt`（282 断言）、`evidence/l2-阶段五.txt`（307 断言）、`export_before.json` / `export_after.json` / `exp_latest.json`、`prefs_before` / `prefs_after` / `prefs_clean`、`extract_meta.js`。

---

## 12. 测试说明

### 12.1 测试分层与当前进度（ST-05 进行中，未收口）

| 层 | 内容 | 当前状态 | 证据 |
| --- | --- | --- | --- |
| L1 构建门禁 | 每任务完成后必须 `BUILD SUCCESSFUL` 且零 `ArkTS:ERROR`，构建日志归档 | ✅ 已执行并通过（阶段二 / 三 / 四） | `evidence/构建日志-阶段二.md`、`构建日志-阶段三.md`、`阶段四-构建日志.txt` |
| **L2 纯逻辑断言** | Node 侧零依赖类型检查 + 断言，覆盖键拼接 / 写队列 / 分块编解码 / 版本迁移 / 诊断缓冲 / 规则业务判据；不依赖 UIAbility | ✅ **307 断言 0 失败**（阶段五最新，`evidence/l2-阶段五.txt`；阶段四快照为 282 断言 `l2-阶段四.txt`） | `evidence/l2-阶段五.txt` |
| L3 持久化验收 | 12 步冷启动重启一致性 + 逐分区降级 | ✅ 已通过（ST-04，见第 11.2 节） | `evidence/阶段四验收报告.md` |
| L3 DevEco Previewer 走查 | 10 页 UI 渲染走查（需 GUI） | ⏳ **尚未实跑**，属 ST-05 范畴 | `evidence/Previewer走查-阶段二.md`（性质为源码级走查，非 UI 截图） |
| **L4 设备端运行测试** | 正常 / 边界 / 异常三类用例在 API 17 设备端执行，六要素留证 | ⏳ **进行中**：**前两批 10 个用例已判定并归档**（含部分达成 / 未达成如实标注，见 PRD 第 16 章表 5.1）；**第三批 7 个用例与修复后 HAP 回归执行中**；**不写「已全部通过」** | `evidence/device/st05_*`、`screenshots/st05_*`、PRD 第 16 章表 5.1 |

> **纪律**：ST-05 尚未收口，上表未列出「全部通过」；未执行的用例一律如实标注「进行中 / 尚未实跑」，**不虚构测试结论**。L4 运行载体为 API 17 模拟器 `127.0.0.1:5555`（见第 9 节载体诚实边界）。

### 12.2 用例分类与判据

用例体系见 `design/测试执行方案-阶段五.md`（V1.3 口径：分 L2 主判定 / L4 设备端 / Previewer 走查三类），PRD 第 16 章表 5.1 为结果登记处。

| 类别 | 覆盖重点 |
| --- | --- |
| 正常用例 TC-N | 手动控制设备、环境刷新、创建并触发规则、切换场景、日志查询、统计聚合 |
| 边界用例 TC-B | 参数取边界值（亮度 0/100、温度 16/30、窗帘 0/100）、条件恰好满足持续时长、日志达到上限后 FIFO |
| 异常用例 TC-E | 参数越界拒绝、规则条件永假、动作执行失败、设备离线、读取持久化数据损坏不崩溃 |

每条用例须留**六要素**：用例编号、前置条件 / Mock 输入、操作步骤、预期结果、**实际结果**、**证据路径**。实际结果 / 是否通过 / 证据路径三列**只对已真实执行的用例填写**，未执行的保留空白，严禁预填。

**L4 前两批已判定用例（共 10 个，已归档；含部分达成 / 未达成如实标注）**，其中第一批 4 例：TC-N-01 手动开灯（附 1 个已转工程师修复的首页卡片原地刷新缺陷）、TC-N-04 场景批量改多设备、TC-N-05 回寝恢复用户预设（判据亮度 75 因 UI 步进固定 ±10 等价替换为 80，如实标注）、TC-E-01 重复开启返回 `NO_CHANGE` 不写冗余日志。第二批 5 例及全部逐用例实际结果 / 证据路径见 PRD 第 16 章表 5.1；**第三批 7 个用例与修复后 HAP 回归执行中，未判通过**。

### 12.3 复跑命令（真实可复现）

```bash
# L2 纯逻辑断言（Node v22.22.2，无需设备）：gen.js 生成 .gen → DevEco tsc 编译 → 逐桶断言
node tests/l2/run.js

# L1 命令行构建（输出未签名 HAP）
scripts\build-hap.bat

# L4 设备端安装 / 启动（API 17 设备，实测原文见 evidence/运行验证报告-模拟器.md）
hdc install -r entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell aa start -a EntryAbility -b com.smartdorm.harmony
```

### 12.4 已知构建门禁局限（重要）

hvigor 的 `CompileArkTS` **只对入口可达闭包内的文件做类型检查**，未被任何页面/服务引用到的 `.ets` 文件即使类型错误也能 `BUILD SUCCESSFUL`。
本项目通过"临时类型检查中枢"方式逐轮收口，并在 `evidence/构建日志-阶段三.md` 中如实记录该局限与验证手法，**不把 `BUILD SUCCESSFUL` 当作全量类型正确的证据**。阶段四还实测到 1 个仅被 ArkTS 编译器发现、被 tsc 宽松放行的 `arkts-no-untyped-obj-literals` 错误（已修复后重建 0 错误），见 `evidence/阶段四验收报告.md` §2.2。

---

## 13. 贡献说明

### 13.1 开发方式

本项目为**个人独立完成的期末大作业，不存在多人分工**。
页面展示层、业务逻辑层、数据模型层、数据存储层、Mock 仿真层、公共基础层、应用入口、测试与证据、文档与交付——**全部模块 100% 由本人一人承担**。若报告中出现"产品经理 / 架构师 / 工程师"等角色表述，系 AI 辅助协作时的角色化工作流描述，**不代表存在团队分工**。

### 13.2 提交规范

采用 Conventional Commits 风格，`type(scope): subject`，按阶段真实提交，**禁止一次性打包提交、禁止伪造提交记录**：

| type | 含义 |
| --- | --- |
| `feat` | 新增功能（页面、服务、引擎） |
| `fix` | 缺陷修复 |
| `refactor` | 重构（不改行为） |
| `docs` | 文档、设计、证据 |
| `chore` | 构建、配置、忽略规则 |
| `test` | 测试相关 |

### 13.3 安全约定

- 仓库**不含**任何 Token / 密码 / 私钥 / 签名证书，`.gitignore` 已排除 `local.properties`、构建产物、`.hvigor`、`.workbuddy`、`*.p12`、`*.cer`、`*.pem`、`*.log`、`.env` 等
- 所有 GitHub 操作通过官方 OAuth 授权完成，**凭据不入库、不入日志、不入提交记录**

### 13.4 反馈

本项目为课程作业，暂不接受外部 PR。如发现问题，欢迎提 Issue 说明复现步骤。

---

## 附录 · 文档索引

| 文档 | 路径 | 说明 |
| --- | --- | --- |
| 软件需求说明书 | [`docs/软件需求说明书.md`](docs/软件需求说明书.md) | 12 项成节，含需求池、用例、数据字典、评分映射、第 16 章测试基线 |
| 系统架构设计 | [`design/系统架构设计.md`](design/系统架构设计.md) | 文件清单、接口签名、数据模型、API 17 实测核验清单 |
| 类图 / 时序图 | [`design/class-diagram.mermaid`](design/class-diagram.mermaid)、[`design/sequence-diagram.mermaid`](design/sequence-diagram.mermaid) | Mermaid 源文件 |
| 阶段任务列表 | `design/任务列表-第二/三/四阶段.md` | 任务分解与验收标准 |
| 测试执行方案 | [`design/测试执行方案-阶段五.md`](design/测试执行方案-阶段五.md) | V1.3 口径：L2 / L4 / Previewer 三类分桶与判据 |
| 环境检查记录 | [`evidence/环境检查记录-阶段一.md`](evidence/环境检查记录-阶段一.md) | 本机实测基线 |
| 构建日志 | [`evidence/构建日志-阶段二.md`](evidence/构建日志-阶段二.md)、[`evidence/构建日志-阶段三.md`](evidence/构建日志-阶段三.md)、`evidence/阶段四-构建日志.txt` | 逐次构建耗时与产物大小 |
| **阶段四验收报告** | [`evidence/阶段四验收报告.md`](evidence/阶段四验收报告.md) | 代码 / 构建 / 设备端三态终判、12 步重启逐字段比对、降级证据与诚实边界 |
| **运行验证报告（模拟器）** | [`evidence/运行验证报告-模拟器.md`](evidence/运行验证报告-模拟器.md) | 设备标识、API 17 校验、安装 / 启动、逐页走查与缺陷根因 |
| **L2 断言输出** | `evidence/l2-阶段四.txt`（282）、`evidence/l2-阶段五.txt`（307） | Node 侧纯逻辑断言原始输出 |
| **落盘 / 导出证据** | `evidence/prefs_before`、`prefs_after`、`prefs_clean`、`export_before.json`、`export_after.json`、`exp_latest.json` | preferences 原文与导出快照 |
| **设备端截图索引** | [`screenshots/README.md`](screenshots/README.md) | 采集方式、载体诚实边界、逐文件对照 |
| 阶段报告 | [`stages/阶段一_环境检查与需求设计.md`](stages/阶段一_环境检查与需求设计.md)、[`stages/阶段二报告.md`](stages/阶段二报告.md) | 各阶段产出与遗留问题 |

---

## 附录 · 进度看板

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| ST-01 | 环境检查与需求设计 | ✅ 完成 |
| ST-02 | 基础工程与 UI 开发 | ✅ 完成；API 17 设备端（模拟器）实拍截图已覆盖，物理真机运行演示经用户裁定豁免、未执行 |
| ST-03 | 核心业务逻辑（8 对象 / 服务层 / 规则引擎） | ✅ 完成（ST-05 期间仍有 UI 缺陷修复提交） |
| ST-04 | 数据持久化 | ✅ 完成：代码完成 / 构建通过 / 设备端验证通过（12 步重启验收） |
| ST-05 | 测试与修复 | ⏳ **进行中**：L2 307 断言 0 失败；L4 前两批 10 个用例已判定并归档（含部分达成 / 未达成如实标注）；第三批 7 个用例与修复后 HAP 回归执行中；L3 Previewer 走查尚未实跑 |
| ST-06 | GitHub 与项目文档（含 Word 报告） | ⏳ 进行中：README 已按 DL-04 完成 13 项对齐；Word 报告待编写 |
| ST-07 | 最终交付 | ⏸ 待启动 |

> 运行载体为 API 17 模拟器 `127.0.0.1:5555`（`OpenHarmony-5.0.5.165`），**非物理真机**；**物理真机运行演示经用户 2026-11-09 裁定豁免、未执行**；DL-05 连续真实录屏与报告图 6.1 / 6.2 的物理真机截图不再作为交付前置，改由 API 17 模拟器 `hdc` 设备端实拍与执行证据覆盖并如实标注载体，见第 9、10 节。

---

<p align="center">
  <sub>智寓 SmartDorm · HarmonyOS 5.0.5 / API 17 · ArkTS + ArkUI · 个人独立完成</sub>
</p>
