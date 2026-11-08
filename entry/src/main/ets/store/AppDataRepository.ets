/**
 * 智寓 · AppDataRepository 单一数据源（阶段二内存态最小可读实现 / T-05 集成复核）
 *
 * 阶段二职责：只持有内存态 AppState（由 MockDataFactory 提供默认数据供页面渲染），
 * 提供 load / getState / listDevices / findXxx / subscribe / notify，
 * 以及 flush / reset / commitRuleLogs 的契约占位（返回安全默认值）。
 * ★ 本阶段不接 PreferencesStore、不写序列化、不迁移、不建串行写队列（全部留 ST-04）。
 * ★ 页面只订阅变更、拿只读渲染快照，禁止直接修改 state（NFR-03 / FR-08-03）。
 *
 * 依据：design/系统架构设计.md 4.1 MI-01/15/16/17/18、8.2/8.3 订阅防泄漏。
 */
import { AppState } from '../model/AppState';
import { Device } from '../model/Device';
import { AutomationRule } from '../model/AutomationRule';
import { Scene } from '../model/Scene';
import { CommandResult } from '../model/CommandResult';
import { RuleEvaluationReport } from '../model/Reports';
import { ResultCode, ResetScope } from '../model/Enums';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';
import { messageOf, STAGE2_PLACEHOLDER_HINT } from '../common/ResultMessage';
import { MockDataFactory } from '../mock/MockDataFactory';
import { IAppDataRepository } from './RepositoryContract';
import { StoragePartition } from './StorageKeys';

export class AppDataRepository implements IAppDataRepository {
  private static instance: AppDataRepository = new AppDataRepository();

  private state: AppState = MockDataFactory.createDefaultAppState();
  private handlers: Map<string, StateChangeHandler> = new Map<string, StateChangeHandler>();

  static getInstance(): AppDataRepository {
    return AppDataRepository.instance;
  }

  private constructor() {
  }

  /** MI-15 同步载入（阶段二直接返回内存默认态；ST-04 接 PreferencesStore 同步读）。 */
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

  /** 当前订阅者数量（阶段二诊断用，可核查无泄漏）。 */
  subscriberCount(): number {
    return this.handlers.size;
  }

  /** MI-16 flush 占位：ST-04 接 WriteQueue 串行写，阶段二返回安全默认值。 */
  async flush(partition?: StoragePartition): Promise<CommandResult<void>> {
    const label: string = partition === undefined ? 'ALL' : partition;
    return AppDataRepository.voidResult(
      ResultCode.NO_CHANGE,
      STAGE2_PLACEHOLDER_HINT + ' · 分区 ' + label
    );
  }

  /** MI-17 reset 占位：返回默认状态作为安全值，不修改内存态（ST-04 接真实重置）。 */
  async reset(scope: ResetScope): Promise<CommandResult<AppState>> {
    const result: CommandResult<AppState> = {
      success: true,
      changed: false,
      code: ResultCode.NO_CHANGE,
      message: messageOf(ResultCode.NO_CHANGE) + '（' +
        STAGE2_PLACEHOLDER_HINT + ' · 重置粒度 ' + scope + '）',
      data: MockDataFactory.createDefaultAppState(),
      timestamp: TimeUtil.now()
    };
    return result;
  }

  /** 护栏 A：规则执行日志唯一提交入口（阶段二只占位，不写入任何日志）。 */
  async commitRuleLogs(report: RuleEvaluationReport): Promise<CommandResult<void>> {
    return AppDataRepository.voidResult(
      ResultCode.NO_CHANGE,
      STAGE2_PLACEHOLDER_HINT + ' · 本轮报告日志数 ' + report.newLogs.length
    );
  }

  /** 统一的 void 型安全结果，避免泛型 void 实例化与返回 undefined。 */
  private static voidResult(code: ResultCode, suffix: string): CommandResult<void> {
    const result: CommandResult<void> = {
      success: code === ResultCode.OK || code === ResultCode.NO_CHANGE,
      changed: false,
      code: code,
      message: messageOf(code) + '（' + suffix + '）',
      timestamp: TimeUtil.now()
    };
    return result;
  }
}
