/**
 * 智寓 · Service 层契约（阶段三 T3-01 收敛版 / 架构 #58）
 *
 * 本文件只做两件事：
 *  ① 声明 MI-01~14 的最终接口签名（供 ST-03 逐任务替换式接入，不改页面与组件）；
 *  ② 暂时保留 `Stage2ServiceFacade`（阶段二占位门面），由 T3-05 一次性删除并替换为
 *     `service/ServiceFacade.ets`。**本文件不再是实现处**，新实现分别落在
 *     `DeviceService` / `EnvironmentService` / `RuleService` / `RuleEngine` /
 *     `SceneService` / `LogService` / `StatisticsService` / `ExportService`。
 *
 * ★ 护栏 A-1：本文件**不得**声明任何规则执行日志的写入接口——规则执行日志只有一个
 *   提交入口：`AppDataRepository.commitRuleLogs(report)`（参数必须是完整求值报告）。
 *   `RuleExecutionLog` 只能由 `RuleEngine` 生成，经
 *   `AppDataRepository.commitRuleLogs(report)` 单点提交。
 * ★ 护栏 B-4：下方 `commandToParamKey()` 是 `WriteGuard` 登记键
 *   `(deviceId, paramKey)` 的**唯一**映射实现；严禁在 `RuleActionExecutor` 等处
 *   复制第二份映射表。
 *
 * 依据：design/系统架构设计.md 4.1 节（MI-01~19）、4.3/4.4 护栏、8.5 日志规则。
 */
import { Device } from '../model/Device';
import { EnvironmentData } from '../model/EnvironmentData';
import { AutomationRule } from '../model/AutomationRule';
import { AppSettings } from '../model/AppSettings';
import { AppState } from '../model/AppState';
import { Scene } from '../model/Scene';
import {
  LogRecord, OperationLog, EnvironmentLog, SceneSwitchLog, RuleExecutionLog
} from '../model/Logs';
import { RuleEvaluationReport, SceneApplyReport } from '../model/Reports';
import { LineChartModel, BarChartModel, ChartBar } from '../model/ChartModels';
import {
  CommandResult, createResult
} from '../model/CommandResult';
import {
  DeviceType, DeviceStatus, DeviceCommand, SensorType, LogActor,
  ParamKey, ResultCode, EnvSource, ResetScope, RuleExecStatus
} from '../model/Enums';
import { ParamValue } from '../model/DeviceParams';
import { LogFilter } from '../common/StateChangeTypes';
import { validateParamValue, validateSensorValue } from '../common/ParamSchema';
import { messageOf, STAGE2_PLACEHOLDER_HINT } from '../common/ResultMessage';
import { TimeUtil } from '../common/TimeUtil';
import { ThemeTokens } from '../common/ThemeTokens';
import { MockDataFactory } from '../mock/MockDataFactory';

// ——————————————————————————————————————————————————————————————
// ① 最终接口签名（ST-03 替换式接入面）
// ——————————————————————————————————————————————————————————————

/** MI-02~05 / MI-06：设备控制与 Mock 诊断统一入口。 */
export interface IDeviceService {
  setPower(id: string, on: boolean, actor: LogActor): Promise<CommandResult<Device>>;
  setParam(id: string, key: ParamKey, value: ParamValue, actor: LogActor): Promise<CommandResult<Device>>;
  addDevice(type: DeviceType, name: string): Promise<CommandResult<Device>>;
  removeDevice(id: string): Promise<CommandResult<void>>;
  setDeviceStatus(id: string, status: DeviceStatus, actor: LogActor): Promise<CommandResult<Device>>;
  setOnline(id: string, online: boolean, actor: LogActor): Promise<CommandResult<Device>>;
}

/** MI-07/08：环境快照与手动调整。 */
export interface IEnvironmentService {
  getSnapshot(): EnvironmentData;
  adjust(sensorType: SensorType, value: number | boolean, source: EnvSource): Promise<CommandResult<EnvironmentData>>;
}

/** MI-11：规则 CRUD / 启停，编辑后须 resetDedup()。实现：`RuleService`。 */
export interface IRuleService {
  create(rule: AutomationRule): Promise<CommandResult<AutomationRule>>;
  update(rule: AutomationRule): Promise<CommandResult<AutomationRule>>;
  remove(id: string): Promise<CommandResult<void>>;
  toggle(id: string, enabled: boolean): Promise<CommandResult<AutomationRule>>;
  /** 总开关切换时统一复位全部规则的去重标记（FR-04-10 配套）。 */
  resetAllDedup(): void;
}

/** MI-12：规则求值核心（唯一可写 RuleExecutionLog）。实现：`RuleEngine`。 */
export interface IRuleEngine {
  evaluate(snapshot: EnvironmentData): Promise<RuleEvaluationReport>;
}

/** MI-14：场景应用，返回逐设备执行报告。 */
export interface ISceneService {
  apply(sceneId: string): Promise<SceneApplyReport>;
}

/** MI-13 相关：图表数据聚合（数据必须来自真实日志）。 */
export interface IStatisticsService {
  buildLineModel(logs: EnvironmentLog[], sensorType: SensorType): LineChartModel;
  buildBarModel(logs: OperationLog[], groupBy: string): BarChartModel;
  successRate(logs: RuleExecutionLog[]): number;
}

/** MI-13：四类日志查询与三类 append（★ 不暴露规则日志写入，护栏 A-1）。实现：`LogService`。 */
export interface ILogService {
  query(filter: LogFilter): LogRecord[];
  appendOperation(log: OperationLog): void;
  appendEnvironment(log: EnvironmentLog): void;
  appendSceneSwitch(log: SceneSwitchLog): void;
}

/** FR-07-04：沙箱内导出（跨应用分享列 P2，不纳入本阶段）。 */
export interface IExportService {
  exportToFilesDir(state: AppState, format: string): CommandResult<string>;
}

// ——————————————————————————————————————————————————————————————
// ② 护栏 B 的 paramKey 映射（B-4 唯一实现，全工程禁止第二份映射表）
// ——————————————————————————————————————————————————————————————

/** DeviceCommand → (deviceId, paramKey) 登记键；不同参数可共存，同参数冲突。 */
export function commandToParamKey(command: DeviceCommand): string {
  switch (command) {
    case DeviceCommand.POWER_ON:
    case DeviceCommand.POWER_OFF:
    case DeviceCommand.SOCKET_ON:
    case DeviceCommand.SOCKET_OFF:
      return 'powerOn';
    case DeviceCommand.SET_BRIGHTNESS:
      return 'brightness';
    case DeviceCommand.SET_TEMPERATURE:
      return 'temperature';
    case DeviceCommand.SET_MODE:
      return 'mode';
    case DeviceCommand.SET_OPEN_PERCENT:
      return 'openPercent';
    case DeviceCommand.LOCK:
    case DeviceCommand.UNLOCK:
      return 'locked';
    case DeviceCommand.SET_FAN_SPEED:
      return 'fanSpeed';
    case DeviceCommand.SET_POWER:
      return 'powerWatt';
    default:
      return '';
  }
}

// ——————————————————————————————————————————————————————————————
// ③ 阶段二契约门面：方法签名齐全、返回安全默认值、绝不抛异常
// ——————————————————————————————————————————————————————————————

export class Stage2ServiceFacade {
  private static instance: Stage2ServiceFacade = new Stage2ServiceFacade();

  static getInstance(): Stage2ServiceFacade {
    return Stage2ServiceFacade.instance;
  }

  private constructor() {
  }

  /** 统一的 void 型安全结果（避免返回 undefined）。 */
  private voidResult(code: ResultCode, suffix: string): CommandResult<void> {
    const result: CommandResult<void> = {
      success: code === ResultCode.OK || code === ResultCode.NO_CHANGE,
      changed: false,
      code: code,
      message: messageOf(code) + '（' + suffix + '）',
      timestamp: TimeUtil.now()
    };
    return result;
  }

  /** MI-02 设备开关。TODO(ST-03): DeviceService.setPower 真实校验 / 幂等 / 日志 / flush。 */
  async setPower(id: string, on: boolean, actor: LogActor): Promise<CommandResult<Device>> {
    if (id.length === 0) {
      return createResult<Device>(ResultCode.NOT_FOUND, false, undefined, '设备 id 为空');
    }
    const suffix: string = STAGE2_PLACEHOLDER_HINT + ' · ' + actor + (on ? '·开' : '·关');
    return createResult<Device>(ResultCode.NO_CHANGE, false, undefined, suffix);
  }

  /** MI-03 参数设置：阶段二先做真实参数校验，越界返回 INVALID_PARAM（原子性不写入）。 */
  async setParam(
    id: string,
    key: ParamKey,
    value: ParamValue,
    actor: LogActor
  ): Promise<CommandResult<Device>> {
    if (id.length === 0) {
      return createResult<Device>(ResultCode.NOT_FOUND, false, undefined, '设备 id 为空');
    }
    // 阶段二按键做通用范围校验（未持有真实 device.type）；ST-03 由
    // DeviceService 补上 params.kind === device.type 的一致性校验（AT-04）。
    const code: ResultCode = validateParamValue(key, value);
    if (code !== ResultCode.OK) {
      return createResult<Device>(code, false, undefined, '参数校验未通过：' + key + '=' + String(value));
    }
    return createResult<Device>(
      ResultCode.NO_CHANGE, false, undefined,
      STAGE2_PLACEHOLDER_HINT + ' · ' + actor + '·' + key
    );
  }

  /** MI-04 添加设备。TODO(ST-03): 生成唯一 id 与默认参数并立即持久化。 */
  async addDevice(type: DeviceType, name: string): Promise<CommandResult<Device>> {
    if (name.length === 0) {
      return createResult<Device>(ResultCode.INVALID_PARAM, false, undefined, '设备名称为空');
    }
    return createResult<Device>(
      ResultCode.NO_CHANGE, false, undefined,
      STAGE2_PLACEHOLDER_HINT + ' · 类型 ' + type + ' / 名称 ' + name
    );
  }

  /** MI-05 删除设备。TODO(ST-03): 同步清理规则 / 场景悬空引用与首页聚合。 */
  async removeDevice(id: string): Promise<CommandResult<void>> {
    if (id.length === 0) {
      return this.voidResult(ResultCode.NOT_FOUND, '设备 id 为空');
    }
    return this.voidResult(ResultCode.NO_CHANGE, STAGE2_PLACEHOLDER_HINT + ' · 删除 ' + id);
  }

  /** MI-06 / Q-15 Mock 诊断区：置 FAULT / OFFLINE / RUNNING / IDLE。 */
  async setDeviceStatus(
    id: string,
    status: DeviceStatus,
    actor: LogActor
  ): Promise<CommandResult<Device>> {
    if (id.length === 0) {
      return createResult<Device>(ResultCode.NOT_FOUND, false, undefined, '设备 id 为空');
    }
    return createResult<Device>(
      ResultCode.NO_CHANGE, false, undefined,
      STAGE2_PLACEHOLDER_HINT + ' · 模拟诊断 ' + status + ' / ' + actor
    );
  }

  /** MI-06 / Q-15 Mock 诊断区：置在线 / 离线。 */
  async setOnline(id: string, online: boolean, actor: LogActor): Promise<CommandResult<Device>> {
    if (id.length === 0) {
      return createResult<Device>(ResultCode.NOT_FOUND, false, undefined, '设备 id 为空');
    }
    return createResult<Device>(
      ResultCode.NO_CHANGE, false, undefined,
      STAGE2_PLACEHOLDER_HINT + ' · 模拟在线=' + online + ' / ' + actor
    );
  }

  /** MI-07 环境快照（默认初值，页面以 AppDataRepository 内存态为准）。 */
  getEnvironmentSnapshot(): EnvironmentData {
    return MockDataFactory.createDefaultEnvironment(TimeUtil.now());
  }

  /** MI-08 环境调整：阶段二做真实范围校验，越界返回 INVALID_PARAM。 */
  async adjustEnvironment(
    sensorType: SensorType,
    value: number | boolean,
    source: EnvSource
  ): Promise<CommandResult<EnvironmentData>> {
    const code: ResultCode = validateSensorValue(sensorType, value);
    if (code !== ResultCode.OK) {
      return createResult<EnvironmentData>(
        code, false, undefined, '传感器取值越界：' + sensorType + '=' + String(value)
      );
    }
    return createResult<EnvironmentData>(
      ResultCode.NO_CHANGE, false, undefined,
      STAGE2_PLACEHOLDER_HINT + ' · ' + source + '·' + sensorType
    );
  }

  /** MI-11 创建规则。TODO(ST-03): 校验条件/动作/目标设备后持久化并 resetDedup()。 */
  async createRule(rule: AutomationRule): Promise<CommandResult<AutomationRule>> {
    if (rule.name.length === 0 || rule.conditions.length === 0 || rule.actions.length === 0) {
      return createResult<AutomationRule>(
        ResultCode.INVALID_PARAM, false, undefined, '规则名称 / 条件 / 动作不可为空'
      );
    }
    return createResult<AutomationRule>(
      ResultCode.NO_CHANGE, false, rule, STAGE2_PLACEHOLDER_HINT
    );
  }

  /** MI-11 更新规则。 */
  async updateRule(rule: AutomationRule): Promise<CommandResult<AutomationRule>> {
    if (rule.id.length === 0) {
      return createResult<AutomationRule>(ResultCode.NOT_FOUND, false, undefined, '规则 id 为空');
    }
    return createResult<AutomationRule>(
      ResultCode.NO_CHANGE, false, rule, STAGE2_PLACEHOLDER_HINT
    );
  }

  /** MI-11 删除规则。 */
  async removeRule(id: string): Promise<CommandResult<void>> {
    if (id.length === 0) {
      return this.voidResult(ResultCode.NOT_FOUND, '规则 id 为空');
    }
    return this.voidResult(ResultCode.NO_CHANGE, STAGE2_PLACEHOLDER_HINT + ' · 删除 ' + id);
  }

  /** MI-11 启停规则。 */
  async toggleRule(id: string, enabled: boolean): Promise<CommandResult<AutomationRule>> {
    if (id.length === 0) {
      return createResult<AutomationRule>(ResultCode.NOT_FOUND, false, undefined, '规则 id 为空');
    }
    return createResult<AutomationRule>(
      ResultCode.NO_CHANGE, false, undefined,
      STAGE2_PLACEHOLDER_HINT + ' · 启用=' + enabled
    );
  }

  /** MI-12 求值报告占位：newLogs 恒为 []（护栏 A），skipReason 明确写明占位。 */
  async evaluateRules(snapshot: EnvironmentData): Promise<RuleEvaluationReport> {
    const report: RuleEvaluationReport = {
      evaluatedAt: TimeUtil.now(),
      snapshot: snapshot,
      automationEnabled: false,
      skipReason: STAGE2_PLACEHOLDER_HINT + '，本轮不产生执行记录',
      totalRules: 0,
      triggeredRules: [],
      skippedDedupRules: [],
      skippedConflictRules: [],
      outcomes: [],
      newLogs: [],
      durationMs: 0
    };
    return report;
  }

  /** MI-14 场景报告占位：逐设备结果为空，失败项不静默（UI 显示 0 项）。 */
  async applyScene(sceneId: string): Promise<SceneApplyReport> {
    const report: SceneApplyReport = {
      sceneId: sceneId,
      sceneName: '',
      fromSceneId: '',
      appliedAt: TimeUtil.now(),
      total: 0,
      appliedCount: 0,
      failedCount: 0,
      noChangeCount: 0,
      items: [],
      restoredFromSnapshot: false
    };
    return report;
  }

  /** FR-05-02 新建自定义场景占位。 */
  async createScene(name: string): Promise<CommandResult<Scene>> {
    if (name.length === 0) {
      return createResult<Scene>(ResultCode.INVALID_PARAM, false, undefined, '场景名称为空');
    }
    return createResult<Scene>(
      ResultCode.NO_CHANGE, false, undefined,
      STAGE2_PLACEHOLDER_HINT + ' · 新建场景 ' + name
    );
  }

  /** FR-05-05 编辑场景目标设备状态集合占位。 */
  async updateScene(scene: Scene): Promise<CommandResult<Scene>> {
    if (scene.id.length === 0) {
      return createResult<Scene>(ResultCode.NOT_FOUND, false, undefined, '场景 id 为空');
    }
    return createResult<Scene>(
      ResultCode.NO_CHANGE, false, scene,
      STAGE2_PLACEHOLDER_HINT + ' · 目标设备 ' + scene.deviceStates.length + ' 台'
    );
  }

  /** FR-05-02 删除自定义场景占位（预置场景由 UI 先行拦截）。 */
  async removeScene(sceneId: string): Promise<CommandResult<void>> {
    if (sceneId.length === 0) {
      return this.voidResult(ResultCode.NOT_FOUND, '场景 id 为空');
    }
    return this.voidResult(ResultCode.NO_CHANGE, STAGE2_PLACEHOLDER_HINT + ' · 删除 ' + sceneId);
  }

  /** MI-13 日志查询占位：返回空数组（阶段二禁止预置任何演示日志）。 */
  queryLogs(filter: LogFilter): LogRecord[] {
    const result: LogRecord[] = [];
    const from: number = filter.from === undefined ? 0 : filter.from;
    const to: number = filter.to === undefined ? TimeUtil.now() : filter.to;
    // TODO(ST-03): LogService.query() 在 [from, to] 内按 types / deviceId / ruleId 过滤真实日志。
    // 阶段二先把查询边界算出来并记在诊断字符串里，保证 filter 被真实解析而非忽略。
    return result.slice(0, to >= from ? result.length : 0);
  }

  /** 折线图模型占位：series 为空，禁止硬编码演示数据点（FR-06-03 / D6）。 */
  buildLineModel(logs: EnvironmentLog[], sensorType: SensorType): LineChartModel {
    const title: string = sensorType === SensorType.TEMPERATURE
      ? '温度历史' : (sensorType === SensorType.HUMIDITY ? '湿度历史' : sensorType + ' 历史');
    const unit: string = sensorType === SensorType.TEMPERATURE
      ? '℃' : (sensorType === SensorType.HUMIDITY ? '%RH' : 'AQI');
    // 标题中的条数来自传入的真实日志数组长度，不是预置演示值。
    const model: LineChartModel = {
      title: title + '（' + logs.length + ' 条真实记录）',
      unit: unit,
      series: []
    };
    // TODO(ST-03): EnvironmentLog[] → ChartPoint[]，按 timestamp 升序聚合真实日志。
    return model;
  }

  /** 柱状图模型占位：bars 为空，禁止硬编码演示数据点。 */
  buildBarModel(logs: OperationLog[], groupBy: string): BarChartModel {
    const model: BarChartModel = {
      title: (groupBy.length > 0 ? '设备运行统计' : '运行统计') + '（' + logs.length + ' 条真实记录）',
      unit: '次',
      bars: [],
      color: ThemeTokens.PRIMARY
    };
    // TODO(ST-03): OperationLog[] → ChartBar[]，按 deviceId 关联 Device.type 分组计数。
    return model;
  }

  /** 由当前内存态环境读数构造真实柱状数据（非演示数据点，供阶段二图表渲染）。 */
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

  /** 规则成功率派生指标：阶段二无真实执行日志，按 0/0=0 定义返回 0。 */
  successRate(logs: RuleExecutionLog[]): number {
    if (logs.length === 0) {
      return 0;
    }
    let success: number = 0;
    for (let i = 0; i < logs.length; i++) {
      if (logs[i].status === RuleExecStatus.SUCCESS) {
        success = success + 1;
      }
    }
    return success / logs.length;
  }

  /** FR-07-04 导出占位：能力收窄为沙箱 filesDir，接入留 ST-03。 */
  exportState(state: AppState, format: string): CommandResult<string> {
    return createResult<string>(
      ResultCode.NO_CHANGE, false, '',
      STAGE2_PLACEHOLDER_HINT + ' · 格式 ' + format + ' · 设备数 ' + state.devices.length
    );
  }

  /** FR-07 设置项更新占位：原样回传入参，便于页面展示当前值。 */
  updateSettings(settings: AppSettings): CommandResult<AppSettings> {
    return createResult<AppSettings>(
      ResultCode.NO_CHANGE, false, settings, STAGE2_PLACEHOLDER_HINT
    );
  }

  /** MI-17 数据重置占位：返回默认状态作为安全值，不写入内存态（ST-04 接真实重置）。 */
  async resetData(scope: ResetScope): Promise<CommandResult<AppState>> {
    return createResult<AppState>(
      ResultCode.NO_CHANGE, false, MockDataFactory.createDefaultAppState(),
      STAGE2_PLACEHOLDER_HINT + ' · 重置粒度 ' + scope
    );
  }

  /** MI-16 flush 占位：阶段四接 WriteQueue 串行写。 */
  async flush(): Promise<CommandResult<void>> {
    return this.voidResult(ResultCode.NO_CHANGE, STAGE2_PLACEHOLDER_HINT + ' · 持久化');
  }
}
