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
> - **ST-04 已通过真机运行验证**：在 API 17 模拟器（`127.0.0.1:5555`，OpenHarmony-5.0.5.165）完成 12 步冷启动重启验收——`preferences` 落盘原文可拉回、`bootCount 1→2`、`firstLaunchAt` 跨重启不变、设备/场景/设置/日志五类数据逐字段一致；`AppDataRepository.flush()` 现已为**真实写入**（非桩函数）。L2 Node 纯逻辑测试 **282 断言 0 失败**。
> - **诚实边界（不影响「代码完成 / 构建通过 / 模拟器验证通过」三态结论）**：① 规则分区端到端 UI 创建未由设备自动化覆盖（机制与已验证分区同管线，由 L2 分块 + 逐区降级统一覆盖）；② C6「手工写坏块后重启」因 `hdc shell` 无沙箱写权限无法原样复现，已用 L2 注入 + 方案 D（清空存储后冷启动不崩溃）替代；③ 导出/落盘 mtime 微序为 `@ohos.data.preferences` 的冗余回写，非数据丢失。
> - 已构建产出仍为 **未签名 HAP**（`entry-default-unsigned.hap`）；L3 DevEco Previewer 走查尚未实跑（需 GUI，属 ST-05 范畴）。
> - 第 9/10 节「运行截图 / 功能演示」证据见 `evidence/` 与 `screenshots/`（均为**真机截图**，非 Previewer、非静态图、非预设效果）。

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
| 6 | **数据统计** | 设备运行统计、规则触发次数、执行成功率、日志查询与筛选 | ✅ 服务已落地，第二张图表在收尾 |
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
├── evidence/                     # 证据归档：环境检查、构建日志、走查记录、占位清单
├── screenshots/                  # 运行截图归档（当前为空，原因见该目录 README）
├── videos/                       # 连续真实录屏归档（当前为空）
├── deliverables/                 # 最终交付包（Word 报告等）
├── scripts/                      # 辅助脚本（build-hap.bat 命令行构建）
├── hvigor/                       # hvigor wrapper
├── build-profile.json5           # 构建配置（产品、SDK 版本、签名占位）
├── oh-package.json5              # 包描述与依赖
├── hvigorfile.ts                 # 构建脚本入口
└── README.md                     # 本文件
```

**源码规模**：`entry/src/main/ets` 下共 **70 个 `.ets` 文件、约 9,300 行 ArkTS 代码**。

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

> ⚠️ 该产物为**未签名** HAP，仅供构建验证，不能直接安装到设备。真机安装需在 DevEco Studio 中配置签名（`Project Structure → Signing Configs`）后重新构建。

### 8.4 构建成功判定标准

- 出现 `Finished ::entry:default@CompileArkTS`
- 出现 `BUILD SUCCESSFUL`
- 全文**无** `ArkTS:ERROR`

> 注意：`COMPILE RESULT:SUCCESS` **不会**在成功时打印，该行仅在失败时输出 `COMPILE RESULT:FAIL {ERROR:n WARN:n}`，不能用它作为成功依据。

---

## 9. 运行截图

**当前状态：无截图。** 如实说明原因：

| 阻塞项 | 实际情况 |
| --- | --- |
| 真机 | 未接入 API 17 HarmonyOS 设备 |
| 模拟器 | 已部署镜像 API Level 与 SDK API 17 不匹配；启动时 `CheckRuntimeEnv::RunCheck` 报 `Invalid System-image Path!`，命令行方式无法拉起，需 DevEco Studio Device Manager 图形界面操作 |
| `hdc list targets` | `[Empty]` |
| Previewer | 本次为命令行会话，未启动 DevEco Studio GUI，未进行 Previewer 渲染 |

**纪律**：本仓库**不放静态示意图**、**不放伪造截图**、**不把 Previewer 截图冒充真机运行效果**。
真实截图将在接入 API 17 设备后归档至 `screenshots/`，并在文件名或随附记录中标注是否为真机。
当前逐页结论见 `evidence/Previewer走查-阶段二.md`（性质为**源码级走查**，非 UI 截图）。

---

## 10. 功能演示

**当前状态：无录屏。** 同第 9 节原因，尚不具备真实运行环境，因此**未产出**符合要求的连续真实录屏。

规划中的录屏须连续覆盖 **10 个环节**，不允许剪辑拼接、不允许预设演示数据、不允许静态图替代图表：

```
启动 → 首页 → 手动控制 → 环境变化 → 创建规则 → 触发规则
     → 查看执行记录 → 切换场景 → 查看历史 → 重启验证数据恢复
```

产出后归档至 `videos/`。**在完成真机录制前，本仓库任何位置均不宣称"演示已完成"。**

---

## 11. 持久化说明

### 11.1 设计（已定稿，见 `design/系统架构设计.md`）

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

### 11.2 当前实现状态（如实）

| 项 | 状态 |
| --- | --- |
| `StorageKeys` 键常量与分区枚举 | ✅ 已定稿 |
| `AppDataRepository.load()` 内存装配 | ✅ 已实现 |
| `commit*` / `append*Log` 内存侧写入 | ✅ 已实现 |
| **`flush()` 真实落盘** | ❌ **未实现**，当前为显式桩函数，返回 `NO_CHANGE` 并注明"阶段四接串行写队列" |
| 版本迁移 / 分块序列化 / 重启恢复验收 | ❌ 属 ST-04，未开始 |

> 因此：**当前版本退出应用后数据不会保留**。这是已知且已声明的限制，不是缺陷隐瞒。
> ST-04 完成后将执行强制 8 步验收：`启动 → 改状态 → 建规则 → 保存 → 退出 → 重启 → 逐项验证 6 类数据一致 → 读取失败不崩溃`，证据归档至 `evidence/`。

---

## 12. 测试说明

### 12.1 测试分层

| 层 | 内容 | 状态 |
| --- | --- | --- |
| L1 构建门禁 | 每个任务完成后必须 `BUILD SUCCESSFUL` 且零 `ArkTS:ERROR`，构建日志归档 | ✅ 已执行，日志见 `evidence/构建日志-阶段二.md`、`evidence/构建日志-阶段三.md` |
| L2 服务层逻辑测试 | 不依赖 UIAbility 的纯逻辑用例，用 DevEco 内置 TypeScript 编译器做零依赖类型检查 + 断言执行 | ⏳ 方案已定稿（`design/测试执行方案-阶段五.md`），部分待脚本化 |
| L3 持久化验收 | 强制 8 步重启一致性验收 | ❌ 阻塞于 ST-04 |
| L4 真机 / 模拟器运行测试 | 正常 / 边界 / 异常三类用例真机执行，六要素留证 | ❌ 阻塞于设备 |

### 12.2 用例分类（共 22 条，详见 `design/测试执行方案-阶段五.md`）

| 类别 | 覆盖重点 |
| --- | --- |
| 正常用例 TC-N | 手动控制设备、环境刷新、创建并触发规则、切换场景、日志查询、统计聚合 |
| 边界用例 TC-B | 参数取边界值（亮度 0/100、温度 16/30、窗帘 0/100）、条件恰好满足持续时长、日志达到上限后 FIFO |
| 异常用例 TC-E | 参数越界拒绝、规则条件永假、动作执行失败、设备离线、读取持久化数据损坏不崩溃 |

每条用例须留**六要素**：用例编号、前置条件、操作步骤、预期结果、实际结果、证据路径。

### 12.3 已知构建门禁局限（重要）

hvigor 的 `CompileArkTS` **只对入口可达闭包内的文件做类型检查**，未被任何页面/服务引用到的 `.ets` 文件即使类型错误也能 `BUILD SUCCESSFUL`。
本项目通过"临时类型检查中枢"方式逐轮收口，并在 `evidence/构建日志-阶段三.md` 中如实记录该局限与验证手法，**不把 `BUILD SUCCESSFUL` 当作全量类型正确的证据**。

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
| 软件需求说明书 | [`docs/软件需求说明书.md`](docs/软件需求说明书.md) | 12 项成节，含需求池、用例、数据字典、评分映射 |
| 系统架构设计 | [`design/系统架构设计.md`](design/系统架构设计.md) | 103 条文件清单、接口签名、数据模型、API 17 实测核验清单 |
| 类图 / 时序图 | [`design/class-diagram.mermaid`](design/class-diagram.mermaid)、[`design/sequence-diagram.mermaid`](design/sequence-diagram.mermaid) | Mermaid 源文件 |
| 阶段任务列表 | `design/任务列表-第二/三/四阶段.md` | 任务分解与验收标准 |
| 测试执行方案 | [`design/测试执行方案-阶段五.md`](design/测试执行方案-阶段五.md) | 22 条用例与执行分桶 |
| 环境检查记录 | [`evidence/环境检查记录-阶段一.md`](evidence/环境检查记录-阶段一.md) | 本机实测基线 |
| 构建日志 | [`evidence/构建日志-阶段二.md`](evidence/构建日志-阶段二.md)、[`evidence/构建日志-阶段三.md`](evidence/构建日志-阶段三.md) | 逐次构建耗时与产物大小 |
| 阶段报告 | [`stages/阶段一_环境检查与需求设计.md`](stages/阶段一_环境检查与需求设计.md)、[`stages/阶段二报告.md`](stages/阶段二报告.md) | 各阶段产出与遗留问题 |

---

## 附录 · 进度看板

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| ST-01 | 环境检查与需求设计 | ✅ 完成 |
| ST-02 | 基础工程与 UI 开发 | ✅ 完成（未真机验证） |
| ST-03 | 核心业务逻辑（8 对象 / 服务层 / 规则引擎） | ✅ 主体完成，UI 手机断点适配收尾中 |
| ST-04 | 数据持久化 | ⏳ 进行中 |
| ST-05 | 测试与修复 | ⏸ 待启动（部分阻塞于设备） |
| ST-06 | GitHub 与项目文档（含 Word 报告） | ⏳ 仓库已建立，报告待编写 |
| ST-07 | 最终交付 | ⏸ 待启动 |

---

<p align="center">
  <sub>智寓 SmartDorm · HarmonyOS 5.0.5 / API 17 · ArkTS + ArkUI · 个人独立完成</sub>
</p>
