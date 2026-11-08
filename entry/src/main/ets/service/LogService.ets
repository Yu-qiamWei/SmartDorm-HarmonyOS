/**
 * 智寓 · 日志服务（MI-13 / FR-06-01/04）
 *
 * 职责边界：
 *   ① `query(filter)` 在真实内存态日志上做区间 + 类型 + deviceId/ruleId 过滤（不返回 null）；
 *   ② 三类 append 委托 `AppDataRepository.append*Log()`（FIFO 落点在仓储，见设计 4.5）。
 *
 * ★ 护栏 A-1：本类**不定义**任何规则执行日志写入方法。`RuleExecutionLog` 只能由
 *   `RuleEngine` 生成并经 `AppDataRepository.commitRuleLogs(report)` 单点提交。
 * ★ 分层：本类只读 `IAppDataRepository` 读面 + `IStateWriter` 的三类 append，
 *   不直接改 `state`，保证「单一写入面」不被绕过（设计 4.2）。
 *
 * 依据：design/系统架构设计.md 4.1 MI-13、4.3 护栏 A、4.5 日志容量。
 */
import { ILogService } from './ServiceContracts';
import { AppDataRepository } from '../store/AppDataRepository';
import { LogFilter } from '../common/StateChangeTypes';
import {
  LogRecord, LogBundle, OperationLog, EnvironmentLog, SceneSwitchLog, RuleExecutionLog
} from '../model/Logs';
import { LogType } from '../model/Enums';

export class LogService implements ILogService {
  private static instance: LogService = new LogService();

  static getInstance(): LogService {
    return LogService.instance;
  }

  private constructor() {
  }

  /**
   * MI-13 日志查询。
   * 过滤维度：`[from, to]` 时间闭区间、`types` 类型白名单、`deviceId`（仅 OperationLog 有该字段）、
   * `ruleId`（仅 RuleExecutionLog 有该字段）。空数据集返回 `[]`，绝不返回 null/undefined。
   * 返回按 `timestamp` 升序（稳定排序，同刻保留加入顺序）。
   */
  query(filter: LogFilter): LogRecord[] {
    const bundle: LogBundle = AppDataRepository.getInstance().getState().logs;
    const from: number = filter.from === undefined ? 0 : filter.from;
    const to: number = filter.to === undefined ? Number.MAX_SAFE_INTEGER : filter.to;
    const types: LogType[] | undefined = filter.types;
    const deviceId: string = filter.deviceId === undefined ? '' : filter.deviceId;
    const ruleId: string = filter.ruleId === undefined ? '' : filter.ruleId;
    const result: LogRecord[] = [];

    if (LogService.wanted(types, LogType.OPERATION)) {
      for (let i = 0; i < bundle.operations.length; i++) {
        const item: OperationLog = bundle.operations[i];
        if (!LogService.inRange(item.timestamp, from, to)) {
          continue;
        }
        if (deviceId.length > 0 && item.deviceId !== deviceId) {
          continue;
        }
        result.push(item);
      }
    }

    if (LogService.wanted(types, LogType.RULE_EXECUTION)) {
      for (let i = 0; i < bundle.ruleExecutions.length; i++) {
        const item: RuleExecutionLog = bundle.ruleExecutions[i];
        if (!LogService.inRange(item.timestamp, from, to)) {
          continue;
        }
        if (ruleId.length > 0 && item.ruleId !== ruleId) {
          continue;
        }
        result.push(item);
      }
    }

    if (LogService.wanted(types, LogType.ENVIRONMENT)) {
      for (let i = 0; i < bundle.environment.length; i++) {
        const item: EnvironmentLog = bundle.environment[i];
        if (!LogService.inRange(item.timestamp, from, to)) {
          continue;
        }
        result.push(item);
      }
    }

    if (LogService.wanted(types, LogType.SCENE_SWITCH)) {
      for (let i = 0; i < bundle.sceneSwitches.length; i++) {
        const item: SceneSwitchLog = bundle.sceneSwitches[i];
        if (!LogService.inRange(item.timestamp, from, to)) {
          continue;
        }
        result.push(item);
      }
    }

    result.sort((a: LogRecord, b: LogRecord): number => a.timestamp - b.timestamp);
    return result;
  }

  /** 操作日志（actor 区分 USER/RULE/SCENE/SYSTEM，由调用方传入真实 actor）。 */
  appendOperation(log: OperationLog): void {
    AppDataRepository.getInstance().appendOperationLog(log);
  }

  /** 环境采样日志（source 区分 MANUAL/SIMULATED/INIT）。 */
  appendEnvironment(log: EnvironmentLog): void {
    AppDataRepository.getInstance().appendEnvironmentLog(log);
  }

  /** 场景切换日志（每次切换 1 条，含 from/to 与成功/失败计数）。 */
  appendSceneSwitch(log: SceneSwitchLog): void {
    AppDataRepository.getInstance().appendSceneSwitchLog(log);
  }

  /** 类型白名单判定：未指定 types 视为全选。 */
  private static wanted(types: LogType[] | undefined, kind: LogType): boolean {
    if (types === undefined || types.length === 0) {
      return true;
    }
    return types.indexOf(kind) >= 0;
  }

  /** 时间闭区间判定。 */
  private static inRange(timestamp: number, from: number, to: number): boolean {
    return timestamp >= from && timestamp <= to;
  }
}
