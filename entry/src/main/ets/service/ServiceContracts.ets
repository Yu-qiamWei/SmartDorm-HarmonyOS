/**
 * 智寓 · Service 层契约（阶段三 T3-05 收口版 / 架构 #58）
 *
 * 本文件只做两件事：
 *  ① 声明 MI-01~14 的最终接口签名（供实现类显式 `implements`，跨层依赖只认接口）；
 *  ② `commandToParamKey()` —— 护栏 B 的唯一映射实现。
 *
 * ★ 阶段二占位门面类已于 T3-05 **删除**（见提交 `refactor(service): replace ...`），
 *   页面唯一门面改为 `service/ServiceFacade.ets`（真实实现委托）。删除后本文件不再 import
 *   `mock/MockDataFactory`、`common/IdGenerator` 等运行时依赖，因此可在 Node 侧
 *   直接做 L2 单测（阶段五）。
 * ★ 护栏 A-1：本文件**不得**声明任何规则执行日志的写入接口——规则执行日志只有一个
 *   提交入口：`AppDataRepository.commitRuleLogs(report)`（参数必须是完整求值报告）。
 * ★ 护栏 B-4：下方 `commandToParamKey()` 是 `WriteGuard` 登记键
 *   `(deviceId, paramKey)` 的**唯一**映射实现；严禁在 `RuleActionExecutor` 等处
 *   复制第二份映射表。
 *
 * 依据：design/系统架构设计.md 4.1 节（MI-01~19）、4.3/4.4 护栏、8.5 日志规则。
 */
import { Device } from '../model/Device';
import { EnvironmentData } from '../model/EnvironmentData';
import { AutomationRule } from '../model/AutomationRule';
import { AppState } from '../model/AppState';
import { Scene } from '../model/Scene';
import {
  LogRecord, OperationLog, EnvironmentLog, SceneSwitchLog
} from '../model/Logs';
import { RuleEvaluationReport, SceneApplyReport } from '../model/Reports';
import { CommandResult } from '../model/CommandResult';
import {
  DeviceType, DeviceStatus, DeviceCommand, SensorType, LogActor,
  ParamKey, EnvSource
} from '../model/Enums';
import { ParamValue } from '../model/DeviceParams';
import { LogFilter } from '../common/StateChangeTypes';

// ——————————————————————————————————————————————————————————————
// ① 最终接口签名（实现类的显式 implements 面）
// ——————————————————————————————————————————————————————————————

/** MI-02~05 / MI-06：设备控制与 Mock 诊断统一入口。实现：`DeviceService`。 */
export interface IDeviceService {
  setPower(id: string, on: boolean, actor: LogActor): Promise<CommandResult<Device>>;
  setParam(id: string, key: ParamKey, value: ParamValue, actor: LogActor): Promise<CommandResult<Device>>;
  addDevice(type: DeviceType, name: string): Promise<CommandResult<Device>>;
  removeDevice(id: string): Promise<CommandResult<void>>;
  setDeviceStatus(id: string, status: DeviceStatus, actor: LogActor): Promise<CommandResult<Device>>;
  setOnline(id: string, online: boolean, actor: LogActor): Promise<CommandResult<Device>>;
}

/** MI-07/08：环境快照与手动调整。实现：`EnvironmentService`。 */
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

/** MI-14：场景应用，返回逐设备执行报告。实现：`SceneService`。 */
export interface ISceneService {
  apply(sceneId: string): Promise<SceneApplyReport>;
  create(name: string): Promise<CommandResult<Scene>>;
  update(scene: Scene): Promise<CommandResult<Scene>>;
  remove(sceneId: string): Promise<CommandResult<void>>;
}

/**
 * MI-13 相关：图表数据聚合（数据必须来自真实日志）。实现：`StatisticsService`。
 * ★ 契约本体已抽出到 `service/StatisticsContract.ets`（零 `@kit.*` 依赖），此处 re-export
 *   仅为保持既有 import 路径可用。原因见该文件头注释：
 *   ArkTS 不支持结构化类型 + `StatisticsService` 必须保持 L2 可测（零 Kit）。
 */
export { IStatisticsService } from './StatisticsContract';

/** MI-13：四类日志查询与三类 append（★ 不暴露规则日志写入，护栏 A-1）。实现：`LogService`。 */
export interface ILogService {
  query(filter: LogFilter): LogRecord[];
  appendOperation(log: OperationLog): void;
  appendEnvironment(log: EnvironmentLog): void;
  appendSceneSwitch(log: SceneSwitchLog): void;
}

/** FR-07-04：沙箱内导出（跨应用分享列 P2，不纳入本阶段）。实现：`ExportService`。 */
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
