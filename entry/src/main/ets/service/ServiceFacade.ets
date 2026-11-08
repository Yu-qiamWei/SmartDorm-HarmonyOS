/**
 * 智寓 · 页面唯一门面（T3-05 / 设计 4.1 组合根）
 *
 * 页面与组件**只允许**依赖本类与 `AppDataRepository`（只读 / 订阅）。
 * 本类方法名与阶段二占位门面**逐字相同**，因此页面侧
 * 只改 import 行与门面标识符，调用形态与业务语句零改动。
 *
 * ★ 本类不含业务判断：所有方法都是**一行委托**，真实实现分别在
 *   `DeviceService` / `EnvironmentService` / `RuleService` / `RuleEngine` /
 *   `SceneService` / `LogService` / `StatisticsService` / `ExportService` /
 *   `AppDataRepository`。
 * ★ 本类**不实现 `IStateWriter`**：门面自己不写状态，`commit*` 只发生在各 service 内部
 *   （护栏 A-4：页面/组件拿不到写权限，门面也不代为转写）。
 * ★ 唯一的两处「组合」职责（不是业务逻辑，而是把分散的服务接在一起）：
 *   ① `initialize(context)` 完成**全部依赖注入**（只此一处，页面与服务互不 new 对方）：
 *      `ExportService` 的应用上下文、`DeviceService` 的 Mock 只读查询、
 *      `EnvironmentService` 的求值触发（指向 `RuleEngine.evaluate`）；
 *   ② `updateSettings()` 后同步环境模拟开关与采样间隔（否则 FR-03-07 的总开关形同虚设，
 *      设置页与首页会各说一套）；总开关切换时按 FR-04-10 复位全部规则的去重标记。
 *
 * 依据：design/系统架构设计.md 4.1/4.2、4.7；design/任务列表-第三阶段.md T3-05。
 */
import { common } from '@kit.AbilityKit';
import { AppDataRepository } from '../store/AppDataRepository';
import { DeviceService } from './DeviceService';
import { EnvironmentService, EvaluationTrigger } from './EnvironmentService';
import { RuleService } from './RuleService';
import { RuleEngine } from './RuleEngine';
import { SceneService } from './SceneService';
import { LogService } from './LogService';
import { StatisticsService } from './StatisticsService';
import { ExportService } from './ExportService';
import { Device } from '../model/Device';
import { EnvironmentData } from '../model/EnvironmentData';
import { AutomationRule } from '../model/AutomationRule';
import { AppSettings } from '../model/AppSettings';
import { AppState } from '../model/AppState';
import { Scene } from '../model/Scene';
import {
  LogRecord, OperationLog, EnvironmentLog, RuleExecutionLog
} from '../model/Logs';
import { RuleEvaluationReport, SceneApplyReport } from '../model/Reports';
import { LineChartModel, BarChartModel, ChartBar } from '../model/ChartModels';
import { CommandResult, okResult, noChangeResult } from '../model/CommandResult';
import {
  DeviceType, DeviceStatus, SensorType, LogActor, ParamKey, EnvSource, ResetScope
} from '../model/Enums';
import { ParamValue } from '../model/DeviceParams';
import { LogFilter } from '../common/StateChangeTypes';
import { ThemeTokens } from '../common/ThemeTokens';
import { DEFAULT_SAMPLE_INTERVAL_MS } from '../common/Constants';
import { TimerHost } from '../mock/TimerHost';
import { EnvironmentSimulator } from '../mock/EnvironmentSimulator';

export class ServiceFacade {
  private static instance: ServiceFacade = new ServiceFacade();

  static getInstance(): ServiceFacade {
    return ServiceFacade.instance;
  }

  private constructor() {
  }

  // ——————————————————————————————————————————————————————————
  // 组合根：全部依赖注入只在这里发生（页面不得注入、服务不得互相 new）
  // ——————————————————————————————————————————————————————————

  /**
   * 初始化门面并完成三处依赖注入。
   *
   * 由 `EntryAbility.onCreate` 调用 **一次**（`this.context` 是应用上下文的唯一持有者，
   * 所以入口职责只是「把上下文递进来」，注入动作全部在本类完成）。
   *
   * ① `ExportService.init(context)`：沙箱 `filesDir` 导出能力；
   * ② `DeviceService.installMockLookup()`：Mock 适配器的只读设备查询（幂等）；
   * ③ `EnvironmentService.setEvaluationTrigger(...)`：**采样 → 规则求值**的触发点。
   *    不注入则环境采样永远不会触发求值，整条自动化链路是死的，而这一点编译期看不出来。
   *
   * 三个 setter 本身幂等，因此本方法可重复调用（Ability 重建时安全）。
   */
  initialize(context: common.Context): void {
    ExportService.getInstance().init(context);
    DeviceService.getInstance().installMockLookup();
    const trigger: EvaluationTrigger = (snapshot: EnvironmentData): Promise<void> => {
      // 报告的返回值在此丢弃：提交（commitRules → commitRuleLogs）已在 evaluate 内部完成
      const evaluated: Promise<void> =
        RuleEngine.getInstance().evaluate(snapshot).then((): void => {
        });
      return evaluated;
    };
    EnvironmentService.getInstance().setEvaluationTrigger(trigger);
  }

  // ——————————————————————————————————————————————————————————
  // 设备控制（→ DeviceService）
  // ——————————————————————————————————————————————————————————

  /** MI-02 设备开关（真实校验链 + 幂等 + 操作日志）。 */
  setPower(id: string, on: boolean, actor: LogActor): Promise<CommandResult<Device>> {
    return DeviceService.getInstance().setPower(id, on, actor);
  }

  /** MI-03 参数设置（存在 → 在线 → 键适用 → 值区间 → 类型一致 → 幂等）。 */
  setParam(
    id: string,
    key: ParamKey,
    value: ParamValue,
    actor: LogActor
  ): Promise<CommandResult<Device>> {
    return DeviceService.getInstance().setParam(id, key, value, actor);
  }

  /** MI-04 添加设备。 */
  addDevice(type: DeviceType, name: string): Promise<CommandResult<Device>> {
    return DeviceService.getInstance().addDevice(type, name);
  }

  /** MI-05 删除设备（同时清理规则动作 / 场景 / 离寝快照的悬空引用）。 */
  removeDevice(id: string): Promise<CommandResult<void>> {
    return DeviceService.getInstance().removeDevice(id);
  }

  /** MI-06 / Q-15 Mock 诊断：置 RUNNING / IDLE / FAULT / OFFLINE。 */
  setDeviceStatus(
    id: string,
    status: DeviceStatus,
    actor: LogActor
  ): Promise<CommandResult<Device>> {
    return DeviceService.getInstance().setDeviceStatus(id, status, actor);
  }

  /** MI-06 / Q-15 Mock 诊断：置在线 / 离线。 */
  setOnline(id: string, online: boolean, actor: LogActor): Promise<CommandResult<Device>> {
    return DeviceService.getInstance().setOnline(id, online, actor);
  }

  // ——————————————————————————————————————————————————————————
  // 环境（→ EnvironmentService）
  // ——————————————————————————————————————————————————————————

  /** MI-07 当前环境快照（权威内存态，只读）。 */
  getEnvironmentSnapshot(): EnvironmentData {
    return EnvironmentService.getInstance().getSnapshot();
  }

  /** MI-08 手动调整：越界返回 INVALID_PARAM，不静默钳制。 */
  adjustEnvironment(
    sensorType: SensorType,
    value: number | boolean,
    source: EnvSource
  ): Promise<CommandResult<EnvironmentData>> {
    return EnvironmentService.getInstance().adjust(sensorType, value, source);
  }

  // ——————————————————————————————————————————————————————————
  // 规则（→ RuleService / RuleEngine）
  // ——————————————————————————————————————————————————————————

  /** MI-11 创建规则（校验条件 / 动作 / 目标设备后入库，`lastSatisfied=false`）。 */
  createRule(rule: AutomationRule): Promise<CommandResult<AutomationRule>> {
    return RuleService.getInstance().create(rule);
  }

  /** MI-11 更新规则（保留累计统计，`lastSatisfied` 强制复位）。 */
  updateRule(rule: AutomationRule): Promise<CommandResult<AutomationRule>> {
    return RuleService.getInstance().update(rule);
  }

  /** MI-11 删除规则。 */
  removeRule(id: string): Promise<CommandResult<void>> {
    return RuleService.getInstance().remove(id);
  }

  /** MI-11 启停规则（停用 → 启用后必须能再次触发）。 */
  toggleRule(id: string, enabled: boolean): Promise<CommandResult<AutomationRule>> {
    return RuleService.getInstance().toggle(id, enabled);
  }

  /** MI-12 规则求值（确定性排序 → AND 求值 → 边沿去重 → 冲突护栏 → 报告）。 */
  evaluateRules(snapshot: EnvironmentData): Promise<RuleEvaluationReport> {
    return RuleEngine.getInstance().evaluate(snapshot);
  }

  // ——————————————————————————————————————————————————————————
  // 场景（→ SceneService）
  // ——————————————————————————————————————————————————————————

  /** MI-14 场景切换：逐设备串行下发，失败聚合进 `items[]`，不中断不回滚。 */
  applyScene(sceneId: string): Promise<SceneApplyReport> {
    return SceneService.getInstance().apply(sceneId);
  }

  /** FR-05-02 新建自定义场景。 */
  createScene(name: string): Promise<CommandResult<Scene>> {
    return SceneService.getInstance().create(name);
  }

  /** FR-05-05 编辑场景目标设备状态集合。 */
  updateScene(scene: Scene): Promise<CommandResult<Scene>> {
    return SceneService.getInstance().update(scene);
  }

  /** FR-05-02 删除自定义场景（预置场景由服务层 `isPreset` 拒绝）。 */
  removeScene(sceneId: string): Promise<CommandResult<void>> {
    return SceneService.getInstance().remove(sceneId);
  }

  // ——————————————————————————————————————————————————————————
  // 日志与统计（→ LogService / StatisticsService）
  // ——————————————————————————————————————————————————————————

  /** MI-13 日志查询（`[from,to]` + 类型 + deviceId/ruleId，按时间升序）。 */
  queryLogs(filter: LogFilter): LogRecord[] {
    return LogService.getInstance().query(filter);
  }

  /** FR-06-02 折线图模型：点数 == 传入日志条数，不补点不插值。 */
  buildLineModel(logs: EnvironmentLog[], sensorType: SensorType): LineChartModel {
    return StatisticsService.getInstance().buildLineModel(logs, sensorType);
  }

  /**
   * FR-06-03 柱状图模型（按设备类型分组计数）。
   *
   * 形参 `groupBy` 保留阶段二签名以维持页面调用语句不变，**已不再参与计算**：
   * `OperationLog` 只有 `deviceId`、没有设备类型字段，分组必须借真实 `Device.type`，
   * 因此这里从仓储补设备数组后转调真实实现。
   */
  buildBarModel(logs: OperationLog[], groupBy: string): BarChartModel {
    const devices: Device[] = AppDataRepository.getInstance().getState().devices;
    return StatisticsService.getInstance().buildBarModel(logs, devices);
  }

  /** 环境实时读数柱状图（当前内存态读数，非演示数据点）。 */
  buildLiveEnvironmentBarModel(environment: EnvironmentData): BarChartModel {
    const bars: ChartBar[] = [
      { label: '温度', value: environment.temperature },
      { label: '湿度', value: environment.humidity },
      { label: '光照/100', value: environment.illuminance / 100 },
      { label: 'AQI', value: environment.airQuality },
      { label: '有人', value: environment.humanPresence ? 1 : 0 }
    ];
    const model: BarChartModel = {
      title: '当前环境读数（实时内存态）',
      unit: '读数',
      bars: bars,
      color: ThemeTokens.ACCENT
    };
    return model;
  }

  /** FR-06 规则成功率：只统计 SUCCESS，空集按 0/0 = 0。 */
  successRate(logs: RuleExecutionLog[]): number {
    return StatisticsService.getInstance().successRate(logs);
  }

  // ——————————————————————————————————————————————————————————
  // 设置 / 导出 / 重置 / 持久化（→ AppDataRepository / ExportService）
  // ——————————————————————————————————————————————————————————

  /**
   * FR-07 设置项更新：写内存态 + notify，并同步环境模拟的开关与间隔。
   *
   * 为什么需要同步：`TimerHost` 只在 `EntryAbility.onCreate` 读一次 `settings`，
   * 若设置页改了开关而无人通知定时器，总开关就成了装饰性按钮（违反 FR-08-01）。
   * 总开关（自动化）切换时按 FR-04-10 复位全部规则的去重标记，避免关闭期间
   * 残留的 `lastSatisfied=true` 把重新开启后的第一轮拦掉。
   */
  updateSettings(settings: AppSettings): CommandResult<AppSettings> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const previous: AppSettings = repo.getState().settings;
    const changed: boolean =
      previous.automationEnabled !== settings.automationEnabled ||
      previous.simulationEnabled !== settings.simulationEnabled ||
      previous.sampleIntervalMs !== settings.sampleIntervalMs ||
      previous.logLimit !== settings.logLimit;
    if (!changed) {
      return noChangeResult<AppSettings>(previous, '设置项未变化');
    }
    repo.commitSettings(settings, 'settings-update');
    if (previous.automationEnabled !== settings.automationEnabled) {
      RuleService.getInstance().resetAllDedup();
    }
    ServiceFacade.syncSampling(previous, settings);
    return okResult<AppSettings>(settings, '设置已保存');
  }

  /** FR-07-04 导出到沙箱 `filesDir/exports/`（未注入上下文时返回 STORAGE_ERROR，不崩溃）。 */
  exportState(state: AppState, format: string): CommandResult<string> {
    return ExportService.getInstance().exportToFilesDir(state, format);
  }

  /** MI-17 数据重置（阶段三仅返回默认态，不写内存态；ST-04 接真实重置）。 */
  resetData(scope: ResetScope): Promise<CommandResult<AppState>> {
    return AppDataRepository.getInstance().reset(scope);
  }

  /** MI-16 串行 flush（阶段三仍返回 NO_CHANGE，ST-04 接 WriteQueue 后真实落盘）。 */
  flush(): Promise<CommandResult<void>> {
    return AppDataRepository.getInstance().flush();
  }

  // ——————————————————————————————————————————————————————————
  // 内部：环境模拟与定时器的同步
  // ——————————————————————————————————————————————————————————

  /**
   * 让 `TimerHost` / `EnvironmentSimulator` 与最新设置保持一致。
   * 间隔变更时必须先 `pause()` 再 `start()`：`resume()` 只在句柄为 -1 时重建定时器，
   * 运行中的定时器不会自动采用新间隔。
   */
  private static syncSampling(previous: AppSettings, next: AppSettings): void {
    const intervalMs: number =
      next.sampleIntervalMs > 0 ? next.sampleIntervalMs : DEFAULT_SAMPLE_INTERVAL_MS;
    const simulator: EnvironmentSimulator = EnvironmentSimulator.getInstance();
    if (!next.simulationEnabled) {
      simulator.stop();
      return;
    }
    const intervalUnchanged: boolean =
      previous.simulationEnabled && previous.sampleIntervalMs === next.sampleIntervalMs;
    if (!intervalUnchanged) {
      TimerHost.getInstance().pause();
    }
    simulator.start(intervalMs);
  }
}
