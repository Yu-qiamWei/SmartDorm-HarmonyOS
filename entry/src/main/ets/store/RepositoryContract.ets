/**
 * 智寓 · AppDataRepository 契约占位（MI-01/15/16/17/18 / 设计 4.1）
 *
 * 阶段二只声明签名；T-05 提供内存态最小可读实现（不接 PreferencesStore）；
 * ST-04 替换为完整实现（PreferencesStore + Serializer + SchemaMigration + WriteQueue）。
 *
 * ★ 护栏 A：commitRuleLogs 的参数必须是 RuleEngine 产出的完整 RuleEvaluationReport，
 * 且本文件不得声明任何规则执行日志写入方法（设计 4.3 节 A-1/A-2）。
 */
import { AppState } from '../model/AppState';
import { Device } from '../model/Device';
import { CommandResult } from '../model/CommandResult';
import { RuleEvaluationReport } from '../model/Reports';
import { ResetScope } from '../model/Enums';
import { StateChangeHandler, Unsubscribe } from '../common/StateChangeTypes';
import { StoragePartition } from './StorageKeys';

export interface IAppDataRepository {
  /** MI-15 同步载入内存态；首次启动返回默认数据，逐区失败降级不崩溃。 */
  load(): AppState;
  /** MI-16 串行 flush（可选分区），失败返回 STORAGE_ERROR。 */
  flush(partition?: StoragePartition): Promise<CommandResult<void>>;
  /** MI-17 重置；二次确认由 UI 负责；不清空 schemaVersion。 */
  reset(scope: ResetScope): Promise<CommandResult<AppState>>;
  /** MI-18 订阅；返回稳定取消订阅函数，页面 aboutToDisappear 必须调用。 */
  subscribe(handler: StateChangeHandler): Unsubscribe;
  /** 当前权威内存态（页面只读渲染快照，禁止直接修改）。 */
  getState(): AppState;
  /** MI-01 设备数组（只读副本）。 */
  listDevices(): Device[];
  /** 护栏 A：规则执行日志唯一提交入口（参数只能是完整求值报告）。 */
  commitRuleLogs(report: RuleEvaluationReport): Promise<CommandResult<void>>;
}
