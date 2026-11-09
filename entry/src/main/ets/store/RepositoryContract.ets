/**
 * 智寓 · AppDataRepository 契约（MI-01/15/16/17/18 / 设计 4.1、4.2）
 *
 * 两个 interface 分开声明（设计 4.2 裁决）：
 *   ① `IAppDataRepository`：与 PRD 8.x 对齐的**对外读契约**（页面可只用它），签名不再膨胀；
 *   ② `IStateWriter`：**层内写契约**，只有 `service/` 层与仓储自身可实现/调用，
 *      页面 / 组件 / mock / entryability 一律禁止（护栏 A-4 延伸），且该禁令在类型层可检查。
 *
 * 阶段三仍**不落盘**：所有 `commit*` 只写内存态 + notify + 标记分区 dirty，
 * 真实持久化（PreferencesStore / Serializer / SchemaMigration / WriteQueue）留 ST-04。
 *
 * ★ 护栏 A：`commitRuleLogs` 的参数必须是 RuleEngine 产出的完整 RuleEvaluationReport，
 * 且本文件不得声明任何规则执行日志写入方法（设计 4.3 节 A-1/A-2）。
 */
import { AppState } from '../model/AppState';
import { Device } from '../model/Device';
import { AutomationRule } from '../model/AutomationRule';
import { Scene, DeviceStateSnapshot } from '../model/Scene';
import { EnvironmentData } from '../model/EnvironmentData';
import { AppSettings } from '../model/AppSettings';
import {
  OperationLog, EnvironmentLog, SceneSwitchLog
} from '../model/Logs';
import { CommandResult } from '../model/CommandResult';
import { RuleEvaluationReport } from '../model/Reports';
import { ResetScope, RunMode } from '../model/Enums';
import { StateChangeHandler, Unsubscribe } from '../common/StateChangeTypes';
import { StoragePartition } from './StorageKeys';
import { RuntimeMeta } from './Serializer';
import { DiagnosticEntry } from './StorageDiagnostics';

/** 对外读契约（页面 / 组件只允许依赖本接口 + subscribe）。 */
export interface IAppDataRepository {
  /**
   * MI-15 同步载入内存态；首次启动返回默认数据并立即落盘，非首次读回 + 迁移 + 逐区降级。
   * `loaded` 幂等：第二次及以后直接返回 `this.state`，不重新读盘、不重新生成默认态。
   */
  load(): AppState;
  /**
   * MI-16 串行 flush，成功 `OK` / 失败 `STORAGE_ERROR`（不抛异常）。
   *
   * ★ `partition` 参数语义 = **先把该分区标记为待写，再整批落盘**，不是「只写该分区」。
   *   `WriteQueue` 的单链与「一批只 flush 一次」契约要求批次边界由队列决定，
   *   单分区直写会破坏 §1.2-C 的跨分区一致性（执行日志与 `lastSatisfied` 同批落盘）。
   */
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
  /** 持久化诊断只读快照（设置页诊断区 / 证据文件用）。 */
  getDiagnostics(): DiagnosticEntry[];
  /** `KEY-11` 运行时元信息只读快照（`bootCount` 是「读回 vs 重新生成」的最强判据）。 */
  getRuntimeMeta(): RuntimeMeta;
}

/**
 * 状态写入唯一入口（设计 4.2）。
 *
 * 谁能实现/调用：`service/` 层（`DeviceService` / `EnvironmentService` / `RuleService` /
 * `RuleEngine` / `SceneService`）与 `AppDataRepository` 自身。
 * 谁不能：`pages/` / `components/` / `mock/` / `entryability/`。
 *
 * 每个 `commit*` 的内部动作固定为三步：
 *   ① 写内存态 → ② `notify(reason, partitions)` → ③ 标记分区 dirty（阶段四 WriteQueue 消费）。
 */
export interface IStateWriter {
  /** 整体替换设备数组（DeviceService / SceneService 用）。 */
  commitDevices(devices: Device[], reason: string): void;
  /** 整体替换规则数组（RuleService / RuleEngine / DeviceService 悬空引用清理用）。 */
  commitRules(rules: AutomationRule[], reason: string): void;
  /** 整体替换场景数组（SceneService / DeviceService 悬空引用清理用）。 */
  commitScenes(scenes: Scene[], reason: string): void;
  /** 替换环境快照（EnvironmentService 用）。 */
  commitEnvironment(environment: EnvironmentData, reason: string): void;
  /** 替换设置（设置页 / 总开关联动用）。 */
  commitSettings(settings: AppSettings, reason: string): void;
  /** 记录当前场景与运行模式（SceneService 切换后调用）。 */
  commitCurrentScene(sceneId: string, mode: RunMode): void;
  /** 保存离寝前快照（KEY-10 独立分区，FR-05-04）。 */
  commitReturnSnapshot(snapshot: DeviceStateSnapshot[]): void;
  /** 追加操作日志；内部 FIFO 上限 = settings.logLimit（默认 1000）。 */
  appendOperationLog(log: OperationLog): void;
  /** 追加环境采样日志；内部 FIFO 上限 = settings.logLimit × 2（默认 2000）。 */
  appendEnvironmentLog(log: EnvironmentLog): void;
  /** 追加场景切换日志；内部 FIFO 上限固定 500。 */
  appendSceneSwitchLog(log: SceneSwitchLog): void;
}
