/**
 * 智寓 · AppDataRepository 单一数据源（阶段三内存态权威副本）
 *
 * 职责：
 *   ① `IAppDataRepository`：load / getState / listDevices / findXxx / subscribe / notify；
 *   ② `IStateWriter`：7 个 commit* + 3 个 append*Log，是**全工程唯一状态写入面**（设计 4.2）；
 *   ③ Q-12 日志容量 FIFO：OperationLog 1000 / RuleExecutionLog 1000 / EnvironmentLog 2000 /
 *      SceneSwitchLog 500，裁剪逻辑统一走 `common/Fifo.ets` 纯函数；
 *   ④ 护栏 A：`commitRuleLogs(report)` 是规则执行日志的**唯一**提交入口。
 *
 * ★ 阶段三仍不落盘：所有写入只改内存态 + notify + 标记分区 dirty；
 *   PreferencesStore / Serializer / SchemaMigration / WriteQueue 全部留 ST-04。
 * ★ 页面只 subscribe + getState()，禁止直接修改 state（NFR-03 / FR-08-03 / 护栏 A-4）。
 *
 * 依据：design/系统架构设计.md 4.1、4.2、4.3、4.5，Q-12。
 */
import { AppState } from '../model/AppState';
import { Device } from '../model/Device';
import { AutomationRule } from '../model/AutomationRule';
import { Scene, DeviceStateSnapshot } from '../model/Scene';
import { EnvironmentData } from '../model/EnvironmentData';
import { AppSettings } from '../model/AppSettings';
import {
  OperationLog, EnvironmentLog, SceneSwitchLog, RuleExecutionLog
} from '../model/Logs';
import { CommandResult } from '../model/CommandResult';
import { RuleEvaluationReport } from '../model/Reports';
import { ResultCode, ResetScope, RunMode, LogType } from '../model/Enums';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';
import { messageOf, STAGE2_PLACEHOLDER_HINT } from '../common/ResultMessage';
import { Fifo } from '../common/Fifo';
import { MockDataFactory } from '../mock/MockDataFactory';
import { IAppDataRepository, IStateWriter } from './RepositoryContract';
import { StoragePartition } from './StorageKeys';

export class AppDataRepository implements IAppDataRepository, IStateWriter {
  private static instance: AppDataRepository = new AppDataRepository();

  private state: AppState = MockDataFactory.createDefaultAppState();
  private handlers: Map<string, StateChangeHandler> = new Map<string, StateChangeHandler>();

  /** 阶段四 WriteQueue 消费用：被改动的分区标记（阶段三只登记，不落盘）。 */
  private dirty: Set<string> = new Set<string>();

  static getInstance(): AppDataRepository {
    return AppDataRepository.instance;
  }

  private constructor() {
  }

  // ——————————————————————————————————————————————————————————
  // IAppDataRepository · 读面
  // ——————————————————————————————————————————————————————————

  /** MI-15 同步载入（阶段三直接返回内存默认态；ST-04 接 PreferencesStore 同步读）。 */
  load(): AppState {
    return this.state;
  }

  /** 单一权威内存态（页面只读渲染快照）。 */
  getState(): AppState {
    return this.state;
  }

  /** MI-01 设备数组（返回副本，避免页面直接改权威态）。 */
  listDevices(): Device[] {
    return this.state.devices.slice();
  }

  /** 按 id 查设备（页面详情页用，找不到返回 undefined，绝不抛异常）。 */
  findDevice(id: string): Device | undefined {
    for (let i = 0; i < this.state.devices.length; i++) {
      if (this.state.devices[i].id === id) {
        return this.state.devices[i];
      }
    }
    return undefined;
  }

  /** 按 id 查规则。 */
  findRule(id: string): AutomationRule | undefined {
    for (let i = 0; i < this.state.rules.length; i++) {
      if (this.state.rules[i].id === id) {
        return this.state.rules[i];
      }
    }
    return undefined;
  }

  /** 按 id 查场景。 */
  findScene(id: string): Scene | undefined {
    for (let i = 0; i < this.state.scenes.length; i++) {
      if (this.state.scenes[i].id === id) {
        return this.state.scenes[i];
      }
    }
    return undefined;
  }

  /** MI-18 订阅：返回稳定的取消订阅函数（SK-01/02），用 Map 自维护回调表。 */
  subscribe(handler: StateChangeHandler): Unsubscribe {
    const key: string = IdGenerator.withPrefix('sub');
    this.handlers.set(key, handler);
    const unsubscribe: Unsubscribe = (): void => {
      this.handlers.delete(key);
    };
    return unsubscribe;
  }

  /** 通知所有订阅者刷新只读快照（页面据此更新 @State）。 */
  notify(reason: string, partitions: string[]): void {
    const change: ChangeSet = {
      reason: reason,
      timestamp: TimeUtil.now(),
      affectedPartitions: partitions
    };
    this.handlers.forEach((handler: StateChangeHandler): void => {
      handler(change);
    });
  }

  /** 当前订阅者数量（诊断用，可核查无泄漏）。 */
  subscriberCount(): number {
    return this.handlers.size;
  }

  /** 已标记 dirty 的分区（阶段四 WriteQueue 消费；阶段三仅供诊断）。 */
  dirtyPartitions(): string[] {
    const result: string[] = [];
    this.dirty.forEach((item: string): void => {
      result.push(item);
    });
    return result;
  }

  /**
   * MI-16 flush：阶段三仍未真实落盘。返回 NO_CHANGE 并显式注明阶段四接串行写队列
   * （任务列表 §1.2 口径），不产生「已保存」的假象。
   */
  async flush(partition?: StoragePartition): Promise<CommandResult<void>> {
    const label: string = partition === undefined ? 'ALL' : partition;
    return AppDataRepository.voidResult(
      ResultCode.NO_CHANGE,
      '内存态已是最新，阶段四接入串行写队列后真实落盘 · 分区 ' + label,
      false
    );
  }

  /** MI-17 reset：阶段三仍只返回默认态作为安全值，不改内存态（ST-04 接真实重置）。 */
  async reset(scope: ResetScope): Promise<CommandResult<AppState>> {
    const result: CommandResult<AppState> = {
      success: true,
      changed: false,
      code: ResultCode.NO_CHANGE,
      message: messageOf(ResultCode.NO_CHANGE) + '（' + STAGE2_PLACEHOLDER_HINT +
        ' · 重置粒度 ' + scope + '）',
      data: MockDataFactory.createDefaultAppState(),
      timestamp: TimeUtil.now()
    };
    return result;
  }

  /**
   * 护栏 A-2：规则执行日志唯一提交入口。
   * 只接收完整 `RuleEvaluationReport`，内部把 `report.newLogs` 追加进 ruleExecutions，
   * 按 Q-12 上限（默认 1000）FIFO 裁剪；空报告不产生任何变更。
   */
  async commitRuleLogs(report: RuleEvaluationReport): Promise<CommandResult<void>> {
    if (report.newLogs.length === 0) {
      return AppDataRepository.voidResult(
        ResultCode.NO_CHANGE, '本轮无新增规则执行日志', false
      );
    }
    const limit: number = Fifo.limitOf(LogType.RULE_EXECUTION, this.state.settings.logLimit);
    const merged: RuleExecutionLog[] =
      this.state.logs.ruleExecutions.concat(report.newLogs);
    this.state.logs.ruleExecutions = Fifo.trim(merged, limit);
    this.markDirty(StoragePartition.RULE_EXEC_LOGS);
    this.notify('log-rule-execution', [StoragePartition.RULE_EXEC_LOGS]);
    return AppDataRepository.voidResult(
      ResultCode.OK,
      '新增 ' + report.newLogs.length + ' 条执行日志，上限 ' + limit,
      true
    );
  }

  // ——————————————————————————————————————————————————————————
  // IStateWriter · 写面（仅 service/ 层调用）
  // ——————————————————————————————————————————————————————————

  commitDevices(devices: Device[], reason: string): void {
    this.state.devices = devices.slice();
    this.markDirty(StoragePartition.DEVICES);
    this.notify(reason, [StoragePartition.DEVICES]);
  }

  commitRules(rules: AutomationRule[], reason: string): void {
    this.state.rules = rules.slice();
    this.markDirty(StoragePartition.RULES);
    this.notify(reason, [StoragePartition.RULES]);
  }

  commitScenes(scenes: Scene[], reason: string): void {
    this.state.scenes = scenes.slice();
    this.markDirty(StoragePartition.SCENES);
    this.notify(reason, [StoragePartition.SCENES]);
  }

  commitEnvironment(environment: EnvironmentData, reason: string): void {
    this.state.environment = environment;
    this.markDirty(StoragePartition.ENVIRONMENT);
    this.notify(reason, [StoragePartition.ENVIRONMENT]);
  }

  commitSettings(settings: AppSettings, reason: string): void {
    this.state.settings = settings;
    this.markDirty(StoragePartition.SETTINGS);
    this.notify(reason, [StoragePartition.SETTINGS]);
  }

  commitCurrentScene(sceneId: string, mode: RunMode): void {
    this.state.currentSceneId = sceneId;
    this.state.currentMode = mode;
    // currentSceneId / currentMode 是顶层指针，随 META 分区（KEY-01 元信息区）落盘。
    this.markDirty(StoragePartition.META);
    this.notify('scene-current', [StoragePartition.META]);
  }

  commitReturnSnapshot(snapshot: DeviceStateSnapshot[]): void {
    this.state.returnSnapshot = snapshot.slice();
    this.markDirty(StoragePartition.RETURN_SNAPSHOT);
    this.notify('return-snapshot', [StoragePartition.RETURN_SNAPSHOT]);
  }

  appendOperationLog(log: OperationLog): void {
    const limit: number = Fifo.limitOf(LogType.OPERATION, this.state.settings.logLimit);
    this.state.logs.operations = Fifo.append(this.state.logs.operations, log, limit);
    this.markDirty(StoragePartition.OPERATION_LOGS);
    this.notify('log-operation', [StoragePartition.OPERATION_LOGS]);
  }

  appendEnvironmentLog(log: EnvironmentLog): void {
    const limit: number = Fifo.limitOf(LogType.ENVIRONMENT, this.state.settings.logLimit);
    this.state.logs.environment = Fifo.append(this.state.logs.environment, log, limit);
    this.markDirty(StoragePartition.ENVIRONMENT_LOGS);
    this.notify('log-environment', [StoragePartition.ENVIRONMENT_LOGS]);
  }

  appendSceneSwitchLog(log: SceneSwitchLog): void {
    const limit: number = Fifo.limitOf(LogType.SCENE_SWITCH, this.state.settings.logLimit);
    this.state.logs.sceneSwitches = Fifo.append(this.state.logs.sceneSwitches, log, limit);
    // SceneSwitchLog 随场景分区 KEY-04 一并序列化（设计 8.1），无独立分区。
    this.markDirty(StoragePartition.SCENES);
    this.notify('log-scene-switch', [StoragePartition.SCENES]);
  }

  // ——————————————————————————————————————————————————————————
  // 内部工具
  // ——————————————————————————————————————————————————————————

  private markDirty(partition: StoragePartition): void {
    this.dirty.add(partition);
  }

  /** 统一的 void 型安全结果，避免泛型 void 实例化与返回 undefined。 */
  private static voidResult(code: ResultCode, suffix: string, changed: boolean): CommandResult<void> {
    const result: CommandResult<void> = {
      success: code === ResultCode.OK || code === ResultCode.NO_CHANGE,
      changed: changed,
      code: code,
      message: messageOf(code) + '（' + suffix + '）',
      timestamp: TimeUtil.now()
    };
    return result;
  }
}
