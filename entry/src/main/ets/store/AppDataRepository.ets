/**
 * 智寓 · AppDataRepository 单一数据源 + 真实持久化（阶段四 T4-03）
 *
 * 职责：
 *   ① `IAppDataRepository`：load / flush / reset / subscribe / notify / getDiagnostics / getRuntimeMeta；
 *   ② `IStateWriter`：7 个 commit* + 3 个 append*Log，是**全工程唯一状态写入面**（设计 4.2）；
 *   ③ Q-12 日志容量 FIFO（Operation 1000 / RuleExec 1000 / Environment 2000 / SceneSwitch 500）；
 *   ④ 护栏 A：`commitRuleLogs(report)` 是规则执行日志的**唯一**提交入口；
 *   ⑤ 持久化接线：`load()` 读回 + 迁移 + 逐区降级；`markDirty()` → `WriteQueue.mark()`；
 *      内部持三套适配器（异步写面 / 同步收尾写面 / 分区编码器），META 走标量键分支。
 *
 * ★ 分层：`store/` 只能依赖 `model/`、`common/` 与 `store/` 自身（`mock/MockDataFactory` 是既有例外，
 *   默认数据工厂）。**不得** import `service/`，**不得** import `mock/TimerHost`（那会形成反向依赖）。
 *
 * ★ 三条会把用户数据写坏的坑（都在本文件内被显式处理）：
 *   ① `PreferencesStore.init()` 必须早于 `load()`，否则每个分区都判「首次启动」→ 默认态覆盖用户数据；
 *   ② 「首次启动」判据只能是 `has(KEY_01) === false`；`decodeSchemaVersion` 对坏版本号返回 0，
 *      若把 `fromVersion === 0` 当首启，一次坏写入就会抹掉用户的全部设备与规则；
 *   ③ META 是**标量分区**（`KEY-01` + `KEY-11`），不是块分区——写面必须特判，否则会落下
 *      `smartdorm.meta.schemaVersion.hdr` 这种垃圾键。
 *
 * 依据：design/系统架构设计.md 4.1/4.2/4.5、design/任务列表-第四阶段.md 1.2.1、1.6、1.7、4.6。
 */
import { AppState } from '../model/AppState';
import { Device } from '../model/Device';
import { AutomationRule } from '../model/AutomationRule';
import { Scene, DeviceStateSnapshot } from '../model/Scene';
import { EnvironmentData } from '../model/EnvironmentData';
import { AppSettings } from '../model/AppSettings';
import {
  OperationLog, EnvironmentLog, SceneSwitchLog, RuleExecutionLog, LogBundle
} from '../model/Logs';
import { CommandResult } from '../model/CommandResult';
import { RuleEvaluationReport } from '../model/Reports';
import { ResultCode, ResetScope, RunMode, LogType } from '../model/Enums';
import { StateChangeHandler, Unsubscribe, ChangeSet } from '../common/StateChangeTypes';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';
import { messageOf } from '../common/ResultMessage';
import { Fifo } from '../common/Fifo';
import { SCHEMA_VERSION } from '../common/Constants';
import { MockDataFactory } from '../mock/MockDataFactory';
import { IAppDataRepository, IStateWriter } from './RepositoryContract';
import { StoragePartition, StorageKeys, ChunkHeader } from './StorageKeys';
import { PreferencesStore } from './PreferencesStore';
import {
  WriteQueue, StateProvider, PartitionWriter, SyncPartitionWriter, PartitionEncoder, QueueStats
} from './WriteQueue';
import {
  Serializer, EncodeResult, DecodeResult, RuntimeMeta, ScenePartition, PartitionDecoder
} from './Serializer';
import { SchemaMigration, MigrationResult } from './SchemaMigration';
import { StorageDiagnostics, DiagnosticEntry, DiagnosticLevel } from './StorageDiagnostics';

/** 写面适配器需要的仓储侧能力（用接口而不是直接依赖本类，避免类声明顺序/循环依赖）。 */
interface PersistenceHost {
  /** 执行期取内存态快照（§1.2-B：入队时不取）。用属性签名以匹配箭头函数字面量（ArkTS arkts-no-untyped-obj-literals 要求）。 */
  snapshot: () => AppState;
  /** 当前运行时元信息 JSON（写 `KEY-11` 用，必须是调用时刻的最新值）。 */
  runtimeJson: () => string;
  /** 是否允许写回 `KEY-01`：迁移失败（存储版本高于应用版本）时必须为 false。 */
  allowSchemaWrite: () => boolean;
}

/**
 * 异步写面（`WriteQueue.PartitionWriter`）。
 *
 * 四个方法严格按 §1.1.1 的顺序被调用：块 → 块头（提交点）→ 删孤儿块 → 整批 flush。
 * **META 特判**：`KEY-01` 与 `KEY-11` 是标量键，没有块也没有 `.hdr`。
 */
class RepoPartitionWriter implements PartitionWriter {
  private prefs: PreferencesStore = PreferencesStore.getInstance();
  private observed: Map<string, number>;
  private host: PersistenceHost;

  constructor(observed: Map<string, number>, host: PersistenceHost) {
    this.observed = observed;
    this.host = host;
  }

  async writeChunks(p: StoragePartition, chunks: string[]): Promise<void> {
    if (p === StoragePartition.META) {
      return; // META 无块
    }
    const base: string = StorageKeys.baseOfPartition(p);
    for (let i = 0; i < chunks.length; i++) {
      await this.prefs.put(StorageKeys.chunkKey(base, i), chunks[i]);
      this.note(base, i);
    }
  }

  async writeHeader(p: StoragePartition, header: ChunkHeader): Promise<void> {
    if (p === StoragePartition.META) {
      // 标量分支：版本号是**纯字符串**（迁移第一步要能用一次 getSync 判版本），
      // 运行时元信息是 JSON。迁移失败时**不写回 KEY-01**，否则会把旧数据标成新版本。
      if (this.host.allowSchemaWrite()) {
        await this.prefs.put(StorageKeys.KEY_01_SCHEMA_VERSION, String(SCHEMA_VERSION));
      }
      await this.prefs.put(StorageKeys.KEY_11_RUNTIME, this.host.runtimeJson());
      return;
    }
    const base: string = StorageKeys.baseOfPartition(p);
    await this.prefs.put(StorageKeys.headerKey(base), Serializer.encodeHeader(header));
  }

  /**
   * 步 3：删掉索引 ≥ `keepCount` 的残块。
   *
   * 上界 `cMax = max(观测最大, keepCount)`：观测最大来自加载期扫描（`allKeys()` 一次）
   * 与历次写入，两者取大才能清掉「上一轮写到第 7 块、这一轮只写 2 块」留下的 5 个孤儿。
   */
  async trimChunks(p: StoragePartition, keepCount: number): Promise<void> {
    if (p === StoragePartition.META) {
      return;
    }
    const base: string = StorageKeys.baseOfPartition(p);
    const seen: number = this.seenOf(base);
    const cMax: number = seen > keepCount ? seen : keepCount;
    for (let i = keepCount; i <= cMax; i++) {
      const key: string = StorageKeys.chunkKey(base, i);
      if (this.prefs.has(key)) {
        await this.prefs.del(key);
      }
    }
    this.observed.set(base, keepCount - 1);
  }

  async flushOnce(): Promise<void> {
    await this.prefs.flushAsync();
  }

  private note(base: string, index: number): void {
    const seen: number = this.seenOf(base);
    if (index > seen) {
      this.observed.set(base, index);
    }
  }

  private seenOf(base: string): number {
    const raw: number | undefined = this.observed.get(base);
    return raw === undefined ? -1 : raw;
  }
}

/**
 * 同步收尾写面（`WriteQueue.SyncPartitionWriter`）。
 *
 * 为什么必须单独一套：`onDestroy` / `onWindowStageDestroy` 返回后事件循环不再推进，
 * `await` 之后的代码不会执行，异步写必然丢。这里全程 `putSync` / `flushSync`。
 */
class RepoSyncWriter implements SyncPartitionWriter {
  private prefs: PreferencesStore = PreferencesStore.getInstance();
  private observed: Map<string, number>;
  private host: PersistenceHost;

  constructor(observed: Map<string, number>, host: PersistenceHost) {
    this.observed = observed;
    this.host = host;
  }

  writeChunks(p: StoragePartition, chunks: string[]): void {
    if (p === StoragePartition.META) {
      return;
    }
    const base: string = StorageKeys.baseOfPartition(p);
    for (let i = 0; i < chunks.length; i++) {
      this.prefs.putSync(StorageKeys.chunkKey(base, i), chunks[i]);
      this.note(base, i);
    }
  }

  writeHeader(p: StoragePartition, header: ChunkHeader): void {
    if (p === StoragePartition.META) {
      if (this.host.allowSchemaWrite()) {
        this.prefs.putSync(StorageKeys.KEY_01_SCHEMA_VERSION, String(SCHEMA_VERSION));
      }
      this.prefs.putSync(StorageKeys.KEY_11_RUNTIME, this.host.runtimeJson());
      return;
    }
    const base: string = StorageKeys.baseOfPartition(p);
    this.prefs.putSync(StorageKeys.headerKey(base), Serializer.encodeHeader(header));
  }

  trimChunks(p: StoragePartition, keepCount: number): void {
    if (p === StoragePartition.META) {
      return;
    }
    const base: string = StorageKeys.baseOfPartition(p);
    const seen: number = this.seenOf(base);
    const cMax: number = seen > keepCount ? seen : keepCount;
    for (let i = keepCount; i <= cMax; i++) {
      const key: string = StorageKeys.chunkKey(base, i);
      if (this.prefs.has(key)) {
        this.prefs.delSync(key);
      }
    }
    this.observed.set(base, keepCount - 1);
  }

  flushOnce(): void {
    this.prefs.flushSyncNow();
  }

  private note(base: string, index: number): void {
    const seen: number = this.seenOf(base);
    if (index > seen) {
      this.observed.set(base, index);
    }
  }

  private seenOf(base: string): number {
    const raw: number | undefined = this.observed.get(base);
    return raw === undefined ? -1 : raw;
  }
}

/** 分区编码器（`WriteQueue.PartitionEncoder`）：把分区编成块字符串数组；META 返回 0 块。 */
class RepoEncoder implements PartitionEncoder {
  encodeChunks(p: StoragePartition, state: AppState): string[] {
    if (p === StoragePartition.META) {
      return [];
    }
    const encoded: EncodeResult = Serializer.encodePartition(p, state);
    return encoded.chunks;
  }
}

export class AppDataRepository implements IAppDataRepository, IStateWriter {
  private static instance: AppDataRepository = new AppDataRepository();

  /** 九个「块分区」（META 不在其中：它是标量分区）。 */
  private static readonly CHUNKED_PARTITIONS: StoragePartition[] = [
    StoragePartition.DEVICES,
    StoragePartition.RULES,
    StoragePartition.SCENES,
    StoragePartition.SETTINGS,
    StoragePartition.ENVIRONMENT,
    StoragePartition.OPERATION_LOGS,
    StoragePartition.RULE_EXEC_LOGS,
    StoragePartition.ENVIRONMENT_LOGS,
    StoragePartition.RETURN_SNAPSHOT
  ];

  /** 构造期的默认态（唯一一次 `createDefaultAppState()`）；`load()` 的降级兜底复用它，不再重复生成。 */
  private defaults: AppState = MockDataFactory.createDefaultAppState();
  private state: AppState = this.defaults;
  private handlers: Map<string, StateChangeHandler> = new Map<string, StateChangeHandler>();

  private loaded: boolean = false;
  private runtimeMeta: RuntimeMeta = Serializer.defaultRuntime(TimeUtil.now());
  /** 迁移失败（存储版本高于应用版本）时为 false：禁止写回 `KEY-01`。 */
  private schemaWritable: boolean = true;
  /** 各 base 观测到的最大块序号（`trimChunks` 的 `cMax` 依据）。 */
  private observedMax: Map<string, number> = new Map<string, number>();

  private queue: WriteQueue = WriteQueue.getInstance();

  static getInstance(): AppDataRepository {
    return AppDataRepository.instance;
  }

  private constructor() {
    const host: PersistenceHost = {
      snapshot: (): AppState => this.state,
      runtimeJson: (): string => Serializer.encodeRuntime(this.runtimeMeta),
      allowSchemaWrite: (): boolean => this.schemaWritable
    };
    this.queue.configure(host.snapshot, new RepoPartitionWriter(this.observedMax, host));
    this.queue.setEncoder(new RepoEncoder());
    this.queue.setSyncWriter(new RepoSyncWriter(this.observedMax, host));
  }

  // ——————————————————————————————————————————————————————————
  // MI-15 load：读回 + 迁移 + 逐区降级（同步、幂等）
  // ——————————————————————————————————————————————————————————

  /**
   * 载入内存态（同步）。算法顺序见 §1.6 与 T4-03 工作单，**不可重排**。
   *
   * 幂等：第二次调用直接返回 `this.state`。若重复生成默认态，`devices[].id` 会全部换掉，
   * 「重启恢复」与「重新初始化」就再也无法区分（C3 判据直接失效）。
   */
  load(): AppState {
    if (this.loaded) {
      return this.state;
    }
    const store: PreferencesStore = PreferencesStore.getInstance();
    if (!store.isReady()) {
      // A5 硬保险：未 init 就 load —— 绝不落盘，也绝不覆盖任何已经存在的数据（读不到就不知道有没有）
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.ERROR, 'STORE_NOT_READY', '持久化句柄未就绪，本次以默认态运行且不落盘');
      this.loaded = true;
      return this.state;
    }

    const startedAt: number = TimeUtil.now();
    const now: number = startedAt;

    // ① 键名枚举：只调一次（getAllSync 会把约 1.3 MB 的 value 一起读出来）
    const enumStart: number = TimeUtil.now();
    const allKeys: string[] = store.allKeys();
    const enumCost: number = TimeUtil.now() - enumStart;
    StorageDiagnostics.getInstance().record(
      DiagnosticLevel.INFO, 'LOAD_ENUM', '枚举键名 ' + allKeys.length + ' 个，耗时 ' + enumCost + 'ms');

    // ② 首启判据：只认「KEY-01 不存在」；版本号不可解析 ≠ 首启
    const firstLaunch: boolean = !store.has(StorageKeys.KEY_01_SCHEMA_VERSION);
    const rawVersion: string = store.getRaw(StorageKeys.KEY_01_SCHEMA_VERSION);
    const fromVersion: number = Serializer.decodeSchemaVersion(rawVersion);
    if (!firstLaunch && fromVersion === 0) {
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.ERROR, 'VERSION_UNREADABLE',
        '版本键内容不可解析（原文长度 ' + rawVersion.length + '），按 v0 迁移但**不当作首次启动**，已解码数据全部保留');
    }

    // ③ 观测最大块序号（一次性从键名算出，供 trimChunks 的 cMax 使用）
    for (let i = 0; i < AppDataRepository.CHUNKED_PARTITIONS.length; i++) {
      const base: string = StorageKeys.baseOfPartition(AppDataRepository.CHUNKED_PARTITIONS[i]);
      let seen: number = -1;
      for (let k = 0; k < allKeys.length; k++) {
        const idx: number = StorageKeys.chunkIndexOf(allKeys[k], base);
        if (idx > seen) {
          seen = idx;
        }
      }
      if (seen >= 0) {
        this.observedMax.set(base, seen);
      }
    }

    // ④ 逐分区读（一个分区坏不许牵连其他分区）
    const defaults: AppState = this.defaults;
    const needInit: StoragePartition[] = [];

    const devices: Device[] = AppDataRepository.take<Device[]>(
      this.readPartition<Device[]>(StoragePartition.DEVICES, Serializer.decodeDevices, allKeys),
      defaults.devices, StoragePartition.DEVICES, needInit);
    const rules: AutomationRule[] = AppDataRepository.take<AutomationRule[]>(
      this.readPartition<AutomationRule[]>(StoragePartition.RULES, Serializer.decodeRules, allKeys),
      defaults.rules, StoragePartition.RULES, needInit);
    const scenesResult: DecodeResult<ScenePartition> = this.readPartition<ScenePartition>(
      StoragePartition.SCENES, Serializer.decodeScenes, allKeys);
    let scenes: Scene[] = defaults.scenes;
    let sceneSwitches: SceneSwitchLog[] = [];
    if (scenesResult.ok && scenesResult.data !== undefined) {
      scenes = scenesResult.data.scenes;
      sceneSwitches = scenesResult.data.sceneSwitches;
    } else {
      AppDataRepository.noteDegrade(scenesResult, StoragePartition.SCENES, needInit);
    }

    const settings: AppSettings = AppDataRepository.take<AppSettings>(
      this.readPartition<AppSettings>(StoragePartition.SETTINGS, Serializer.decodeSettings, allKeys),
      defaults.settings, StoragePartition.SETTINGS, needInit);
    const environment: EnvironmentData = AppDataRepository.take<EnvironmentData>(
      this.readPartition<EnvironmentData>(
        StoragePartition.ENVIRONMENT, Serializer.decodeEnvironment, allKeys),
      defaults.environment, StoragePartition.ENVIRONMENT, needInit);
    const operations: OperationLog[] = AppDataRepository.take<OperationLog[]>(
      this.readPartition<OperationLog[]>(
        StoragePartition.OPERATION_LOGS, Serializer.decodeOperationLogs, allKeys),
      defaults.logs.operations, StoragePartition.OPERATION_LOGS, needInit);
    const ruleExecutions: RuleExecutionLog[] = AppDataRepository.take<RuleExecutionLog[]>(
      this.readPartition<RuleExecutionLog[]>(
        StoragePartition.RULE_EXEC_LOGS, Serializer.decodeRuleExecLogs, allKeys),
      defaults.logs.ruleExecutions, StoragePartition.RULE_EXEC_LOGS, needInit);
    const environmentLogs: EnvironmentLog[] = AppDataRepository.take<EnvironmentLog[]>(
      this.readPartition<EnvironmentLog[]>(
        StoragePartition.ENVIRONMENT_LOGS, Serializer.decodeEnvironmentLogs, allKeys),
      defaults.logs.environment, StoragePartition.ENVIRONMENT_LOGS, needInit);
    const returnSnapshot: DeviceStateSnapshot[] = AppDataRepository.take<DeviceStateSnapshot[]>(
      this.readPartition<DeviceStateSnapshot[]>(
        StoragePartition.RETURN_SNAPSHOT, Serializer.decodeReturnSnapshot, allKeys),
      defaults.returnSnapshot, StoragePartition.RETURN_SNAPSHOT, needInit);

    const logs: LogBundle = {
      operations: operations,
      ruleExecutions: ruleExecutions,
      environment: environmentLogs,
      sceneSwitches: sceneSwitches
    };

    // ⑤ KEY-11 运行时元信息
    const runtimeRead: DecodeResult<RuntimeMeta> =
      Serializer.decodeRuntime(store.getRaw(StorageKeys.KEY_11_RUNTIME));
    const runtime: RuntimeMeta = runtimeRead.ok && runtimeRead.data !== undefined
      ? runtimeRead.data : Serializer.defaultRuntime(now);

    // ⑥ 组合候选态（currentMode / currentSceneId 只来自 KEY-11）
    const candidate: AppState = {
      schemaVersion: fromVersion,
      devices: devices,
      rules: rules,
      scenes: scenes,
      settings: settings,
      environment: environment,
      logs: logs,
      returnSnapshot: returnSnapshot,
      currentMode: runtime.currentMode,
      currentSceneId: runtime.currentSceneId
    };

    // ⑦ 迁移（失败时保留候选原态、禁止写回 KEY-01）
    const migration: MigrationResult = SchemaMigration.migrate(candidate, fromVersion);
    let migrated: AppState = candidate;
    if (migration.error !== '') {
      this.schemaWritable = false;
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.WARN, 'MIGRATION_SKIPPED', migration.error);
    } else {
      migrated = migration.state;
    }

    // ⑧ 运行时元信息推进（bootCount / lastLaunchAt / firstLaunchAt）
    const nextRuntime: RuntimeMeta = {
      currentSceneId: runtime.currentSceneId,
      currentMode: runtime.currentMode,
      firstLaunchAt: firstLaunch ? now : runtime.firstLaunchAt,
      lastLaunchAt: now,
      bootCount: firstLaunch ? 1 : runtime.bootCount + 1
    };
    this.runtimeMeta = nextRuntime;

    // ⑨ 装入内存态
    this.state = migrated;
    this.loaded = true;

    // ⑩ 落盘（不 await：load 是同步的）
    if (firstLaunch) {
      const all: StoragePartition[] = AppDataRepository.allPartitions();
      this.queue.mark(all);
    } else {
      this.queue.mark([StoragePartition.META]);
      if (needInit.length > 0) {
        this.queue.mark(needInit);
      }
    }

    StorageDiagnostics.getInstance().record(
      DiagnosticLevel.INFO, 'LOAD_DONE',
      '耗时 ' + (now - startedAt) + 'ms 首启=' + firstLaunch + ' 版本 ' + fromVersion + '→' +
        this.state.schemaVersion + ' 待初始化分区 ' + needInit.length + ' 个');
    return this.state;
  }

  // ——————————————————————————————————————————————————————————
  // MI-16 flush / 收尾同步落盘
  // ——————————————————————————————————————————————————————————

  /**
   * 委托 `WriteQueue.flushNow()`。
   *
   * `flushNow()` 的 Promise **永不 reject**（失败经 `stats().failures` 暴露），
   * 所以这里用「failures 增量」翻译成 `ResultCode`：
   * 增量 > 0 → `STORAGE_ERROR`（内存态不动、分区仍 dirty，§1.2.1 五条）。
   */
  async flush(partition?: StoragePartition): Promise<CommandResult<void>> {
    const before: number = this.queue.stats().failures;
    if (partition !== undefined) {
      this.queue.mark([partition]);
    }
    await this.queue.flushNow();
    const after: number = this.queue.stats().failures;
    const pending: number = this.queue.pendingPartitions().length;
    if (after > before) {
      const stats: QueueStats = this.queue.stats();
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.ERROR, 'FLUSH_FAILED',
        '连续失败 ' + this.queue.failStreak() + ' 次，残留 ' + pending + ' 个分区：' + stats.lastError);
      return AppDataRepository.voidResult(
        ResultCode.STORAGE_ERROR,
        messageOf(ResultCode.STORAGE_ERROR) + '（连续失败 ' + this.queue.failStreak() + ' 次）',
        false);
    }
    return AppDataRepository.voidResult(
      ResultCode.OK, '已落盘，残留待写分区 ' + pending + ' 个', false);
  }

  /**
   * 收尾同步落盘（`onDestroy` / `onWindowStageDestroy` 用）。
   *
   * 为什么不能在生命周期末尾用 `flush()`：Ability 销毁后事件循环不再推进，
   * `await` 之后的代码不会执行，异步写必然丢；这里全程 `putSync` / `flushSync`。
   */
  saveNowSync(): CommandResult<void> {
    const before: number = this.queue.stats().failures;
    this.queue.flushNowSync();
    const after: number = this.queue.stats().failures;
    const pending: number = this.queue.pendingPartitions().length;
    if (after > before) {
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.ERROR, 'SYNC_FLUSH_FAILED',
        '收尾同步落盘失败，残留 ' + pending + ' 个分区');
      return AppDataRepository.voidResult(
        ResultCode.STORAGE_ERROR, messageOf(ResultCode.STORAGE_ERROR) + '（收尾残留 ' + pending + ' 个分区）',
        false);
    }
    return AppDataRepository.voidResult(
      ResultCode.OK, '收尾同步落盘完成，残留 ' + pending + ' 个分区', false);
  }

  // ——————————————————————————————————————————————————————————
  // MI-17 reset：七步（§1.7）
  // ——————————————————————————————————————————————————————————

  /**
   * 重置（七步：算目标态 → 换内存态 → 标 dirty → 逐键覆写 → 批量收缩 → 一次 flush → 广播）。
   *
   * 失败处理：内存态**不回滚**（已重置就不假装没重置），分区保持 dirty 下次自动重试，
   * 返回 `STORAGE_ERROR`。
   *
   * ★ 明确不做（防越界）：不 `pause()` 定时器、不清 `WriteGuard`、不遍历规则置
   *   `lastSatisfied = false`。前两项属 `service/` 与 `mock/`（`store/` import 它们会破坏分层），
   *   第三项随规则数组重建天然归零；`TimerHost` 的暂停/恢复由设置页在 `reset()` 前后自行负责。
   */
  async reset(scope: ResetScope): Promise<CommandResult<AppState>> {
    let next: AppState;
    let partitions: StoragePartition[];

    if (scope === ResetScope.LOGS_ONLY) {
      const emptyLogs: LogBundle = {
        operations: [],
        ruleExecutions: [],
        environment: [],
        sceneSwitches: []
      };
      next = {
        schemaVersion: this.state.schemaVersion,
        devices: this.state.devices,
        rules: this.state.rules,
        scenes: this.state.scenes,
        settings: this.state.settings,
        environment: this.state.environment,
        logs: emptyLogs,
        returnSnapshot: this.state.returnSnapshot,
        currentMode: this.state.currentMode,
        currentSceneId: this.state.currentSceneId
      };
      partitions = [
        StoragePartition.OPERATION_LOGS,
        StoragePartition.RULE_EXEC_LOGS,
        StoragePartition.ENVIRONMENT_LOGS,
        StoragePartition.SCENES
      ];
    } else {
      next = MockDataFactory.createDefaultAppState();
      partitions = AppDataRepository.allPartitions();
      const now: number = TimeUtil.now();
      this.runtimeMeta = Serializer.defaultRuntime(now);
      this.schemaWritable = true;
    }

    this.state = next;
    this.queue.mark(partitions);
    const names: string[] = [];
    for (let i = 0; i < partitions.length; i++) {
      names.push(partitions[i]);
    }
    this.notify('reset', names);

    const flushed: CommandResult<void> = await this.flush();
    const result: CommandResult<AppState> = {
      success: flushed.code === ResultCode.OK,
      changed: true,
      code: flushed.code,
      message: flushed.code === ResultCode.OK
        ? '已重置（' + scope + '）并落盘'
        : messageOf(ResultCode.STORAGE_ERROR) + '（重置已生效，但落盘失败，将自动重试）',
      data: next,
      timestamp: TimeUtil.now()
    };
    return result;
  }

  // ——————————————————————————————————————————————————————————
  // 只读诊断
  // ——————————————————————————————————————————————————————————

  /** 持久化诊断只读快照（设置页 / 证据文件）。 */
  getDiagnostics(): DiagnosticEntry[] {
    return StorageDiagnostics.getInstance().list();
  }

  /** `KEY-11` 运行时元信息（`bootCount` 是「读回 vs 重新生成」的最强判据）。 */
  getRuntimeMeta(): RuntimeMeta {
    const copy: RuntimeMeta = {
      currentSceneId: this.runtimeMeta.currentSceneId,
      currentMode: this.runtimeMeta.currentMode,
      firstLaunchAt: this.runtimeMeta.firstLaunchAt,
      lastLaunchAt: this.runtimeMeta.lastLaunchAt,
      bootCount: this.runtimeMeta.bootCount
    };
    return copy;
  }

  // ——————————————————————————————————————————————————————————
  // IAppDataRepository · 读面
  // ——————————————————————————————————————————————————————————

  /** 单一权威内存态（页面只读渲染快照）。 */
  getState(): AppState {
    return this.state;
  }

  /** MI-01 设备数组（返回副本，避免页面直接改权威态）。 */
  listDevices(): Device[] {
    return this.state.devices.slice();
  }

  /** 按 id 查设备（找不到返回 undefined，绝不抛异常）。 */
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

  /**
   * 尚未落盘的分区（委托 `WriteQueue.pendingPartitions()`）。
   *
   * ★ 必须委托：`dirty` 集合现在归队列所有，仓储自己维护一份只会永远返回空数组，
   *   让设置页/证据看到假的「无待写」。
   */
  dirtyPartitions(): string[] {
    const pending: StoragePartition[] = this.queue.pendingPartitions();
    const names: string[] = [];
    for (let i = 0; i < pending.length; i++) {
      names.push(pending[i]);
    }
    return names;
  }

  /**
   * 当前连续写失败次数（委托 `WriteQueue.failStreak()`）。
   *
   * 为什么单独开一个只读方法：连续失败是「存储不可用」的唯一可靠信号
   * （`FLUSH_FAIL_WARN_STREAK = 3` 触发降级提示），设置页诊断区与 L2 断言都要读它，
   * 但 `IAppDataRepository` 契约里不需要这条，故只留在具体类上，不进接口。
   */
  storageFailStreak(): number {
    return this.queue.failStreak();
  }

  /** 写队列快照（诊断与 L2 断言用；`IAppDataRepository` 不暴露，UI 不依赖）。 */
  queueStats(): QueueStats {
    return this.queue.stats();
  }

  /**
   * 护栏 A-2：规则执行日志唯一提交入口。
   * 只接收完整 `RuleEvaluationReport`，内部把 `report.newLogs` 追加进 ruleExecutions，
   * 按 Q-12 上限（默认 1000）FIFO 裁剪；空报告不产生任何变更。
   */
  async commitRuleLogs(report: RuleEvaluationReport): Promise<CommandResult<void>> {
    if (report.newLogs.length === 0) {
      return AppDataRepository.voidResult(
        ResultCode.NO_CHANGE, '本轮无新增规则执行日志', false);
    }
    const limit: number = Fifo.limitOf(LogType.RULE_EXECUTION, this.state.settings.logLimit);
    const merged: RuleExecutionLog[] =
      this.state.logs.ruleExecutions.concat(report.newLogs);
    this.state.logs.ruleExecutions = Fifo.trim(merged, limit);
    this.markDirty(StoragePartition.RULE_EXEC_LOGS);
    this.notify('rule-logs', [StoragePartition.RULE_EXEC_LOGS]);
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
    this.runtimeMeta.currentSceneId = sceneId;
    this.runtimeMeta.currentMode = mode;
    // currentSceneId / currentMode 是顶层指针，随 META 分区（KEY-01 + KEY-11）落盘。
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

  /**
   * 标脏：**唯一**入口，委托 `WriteQueue.mark()`。
   *
   * 时序注意（C9 走查点）：`RuleEngine.evaluate()` 是「先 `commitRules` 再 `await commitRuleLogs`」，
   * 两次 mark 之间没有任何 `await flush()`，因此规则与执行日志落在**同一个**队列批次里 ——
   * 这正是「执行日志有、`lastSatisfied` 没有」这个跨分区不一致问题的机制性解法。
   */
  private markDirty(partition: StoragePartition): void {
    this.queue.mark([partition]);
  }

  /** 读一个块分区：块头 + 该分区全部块原文 → `assemblePartition`（含三级一致性校验）。 */
  private readPartition<T>(p: StoragePartition, decode: PartitionDecoder<T>,
    allKeys: string[]): DecodeResult<T> {
    const store: PreferencesStore = PreferencesStore.getInstance();
    const base: string = StorageKeys.baseOfPartition(p);
    const headerRaw: string = store.getRaw(StorageKeys.headerKey(base));
    const raws: string[] = [];
    for (let i = 0; i < allKeys.length; i++) {
      const idx: number = StorageKeys.chunkIndexOf(allKeys[i], base);
      if (idx >= 0) {
        raws.push(store.getRaw(allKeys[i]));
      }
    }
    return Serializer.assemblePartition<T>(p, headerRaw, raws, decode);
  }

  /** 三个分区列表常量：十个逻辑分区（META 在内）。 */
  private static allPartitions(): StoragePartition[] {
    const all: StoragePartition[] = [
      StoragePartition.META,
      StoragePartition.DEVICES,
      StoragePartition.RULES,
      StoragePartition.SCENES,
      StoragePartition.SETTINGS,
      StoragePartition.ENVIRONMENT,
      StoragePartition.OPERATION_LOGS,
      StoragePartition.RULE_EXEC_LOGS,
      StoragePartition.ENVIRONMENT_LOGS,
      StoragePartition.RETURN_SNAPSHOT
    ];
    return all;
  }

  /** 解码结果 → 取值；失败走降级（`EMPTY` 不记 ERROR，那是首启正常现象）。 */
  private static take<T>(result: DecodeResult<T>, fallback: T, partition: StoragePartition,
    needInit: StoragePartition[]): T {
    if (result.ok && result.data !== undefined) {
      return result.data;
    }
    AppDataRepository.noteDegrade(result, partition, needInit);
    return fallback;
  }

  /** 降级记账：`EMPTY` = 从没写过（不报错）；其余前缀 = 损坏（报 ERROR）。 */
  private static noteDegrade<T>(result: DecodeResult<T>, partition: StoragePartition,
    needInit: StoragePartition[]): void {
    needInit.push(partition);
    if (result.error.indexOf('EMPTY') === 0) {
      return; // 首启 / 从未写过该分区，正常现象
    }
    const prefix: string = AppDataRepository.errorCodeOf(result.error);
    StorageDiagnostics.getInstance().record(
      DiagnosticLevel.ERROR, prefix, partition + ' 降级为默认值：' + result.error);
  }

  /** 取 `error` 的稳定前缀（`CODE: 细节` → `CODE`）。 */
  private static errorCodeOf(error: string): string {
    const at: number = error.indexOf(':');
    if (at <= 0) {
      return 'PARTITION_CORRUPT';
    }
    return error.substring(0, at);
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
