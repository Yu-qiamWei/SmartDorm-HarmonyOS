/**
 * 智寓 · 串行写队列（设计 8.6 / 8.6.1、MI-16，任务列表-第四阶段 1.2 / 4.2）
 *
 * 解决三个具体问题，每个都有对应机制（不是「顺手优化」）：
 *   ① **合并**：采样每 4 s 追加一条环境日志，若每次都重写 ~43 块 ≈ 296 KB 会把 UI 拖死
 *      → 两车道 debounce（用户 200 ms / 日志 30 s 或累计 20 次写，先到者触发）。
 *   ② **串行**：允许多个 flush 并发 = 经典数据损坏（任务 A 持旧快照后完成，用旧数据覆盖新数据，
 *      日志上看不出异常）→ 内部一条 `Promise` 尾指针，任何时刻只有 1 个写任务在执行。
 *   ③ **一批只 flush 一次**：`RuleEngine.evaluate()` 的顺序是 `commitRules` → `await commitRuleLogs`，
 *      若两分区各自 `flush()`，中间被杀就留下「执行日志有、`lastSatisfied` 没有」，
 *      重启后表现为**规则重复执行** → 一个批次所有分区 `put` 完成后只调用一次 `flushOnce()`。
 *
 * ★ 快照时点：`stateProvider()` 在**任务执行期**调用，入队时不取（§1.2-B）。
 *
 * ★ 失败路径（§1.2.1 五条规定，逐条对应代码）：
 *   1. `dirty` 只在 `flushOnce()` 成功之后才删（本文件 `runCycle()` 末尾）；
 *   2. 内存态不回滚（本类不持有、不修改 `AppState`）；
 *   3. **不 throw**：`flushNow()` 返回的 Promise 总是 resolve，失败通过
 *      `stats().failures` / `stats().lastError` / `pendingPartitions()` 暴露，
 *      由仓储层（T4-03）翻译成 `ResultCode.STORAGE_ERROR`；
 *   4. `failures += 1`、`lastError` 记录分区与原因，供设置页与证据文件核查；
 *   5. 连续失败次数由 `failStreak()` 暴露，`>= FLUSH_FAIL_WARN_STREAK` 时设置页常驻告警（T4-04）。
 *
 * ★ 本类**零 `@kit.*` 依赖**（只依赖 `model/AppState`、`store/StorageKeys`、`common/*`），
 *   因此可在 Node 侧 L2 单测：合并、串行、重入去重、失败保 dirty、写入顺序（§7 第 17 项）。
 *
 * 依据：design/任务列表-第四阶段.md 1.1.1、1.2、1.2.1、1.1.2、4.2。
 */
import { AppState } from '../model/AppState';
import { StoragePartition, ChunkHeader } from './StorageKeys';
import {
  CHUNK_INDEX_MAX,
  CHUNK_FORMAT_VERSION,
  FLUSH_DEBOUNCE_LOG_MS,
  FLUSH_DEBOUNCE_USER_MS,
  FLUSH_MAX_PENDING_LOG_WRITES
} from '../common/Constants';
import { TimeUtil } from '../common/TimeUtil';

/** 执行期取快照（**禁止**在 `mark` / 入队时取，§1.2-B）。实现方 = `AppDataRepository.getState`。 */
export type StateProvider = () => AppState;

/**
 * 落盘动作拆成四个显式方法，**写入顺序因此可在 L2 用 fake writer 断言**（§1.1.1）。
 * 实现方 = `AppDataRepository` 内部的一个 writer 对象（内部转调 `PreferencesStore`）。
 */
export interface PartitionWriter {
  /** 步 1：写 `c0000..c(n-1)`（先写块，块头仍是旧 n，被杀只留孤儿块，旧数据完好）。 */
  writeChunks(p: StoragePartition, chunks: string[]): Promise<void>;
  /** 步 2：写 `<base>.hdr`（**提交点**，必须最后写头）。 */
  writeHeader(p: StoragePartition, header: ChunkHeader): Promise<void>;
  /**
   * 步 3：保证该分区「只保留前 `keepCount` 块」，删除所有索引 ≥ `keepCount` 的残块。
   * 实现方自行跟踪「已知最大序号」（加载期观测值 ∪ 历次写入值），本方法必须**幂等**。
   */
  trimChunks(p: StoragePartition, keepCount: number): Promise<void>;
  /** 步 4：整批一次落盘（等价 `preferences.flush()`）；**一批只调用一次**。 */
  flushOnce(): Promise<void>;
}

/**
 * 收尾同步写面（`onDestroy` / `onWindowStageDestroy` 用，§4.2 `flushNowSync`）。
 *
 * 为什么单独一个接口：`PartitionWriter` 全是 `Promise`，同步收尾路径不能 await，
 * 而 `onDestroy` 之后事件循环不再推进，异步写必然丢。同步面走 `putSync` / `flushSync`。
 */
export interface SyncPartitionWriter {
  writeChunks(p: StoragePartition, chunks: string[]): void;
  writeHeader(p: StoragePartition, header: ChunkHeader): void;
  trimChunks(p: StoragePartition, keepCount: number): void;
  flushOnce(): void;
}

/**
 * 分区编码器：把分区的当前内存态编成块字符串数组（第 0 项即 `c0000`）。
 *
 * 为什么由外部注入而不是本类直接调 `Serializer`：`ChunkHeader` 刻意定义在
 * `StorageKeys`（T4-01），就是为了让 T4-01 **不反向依赖** T4-02 的 `Serializer`。
 * T4-03 接线时以适配器实现本接口（`encodePartition(...).chunks`），块头由本类自建。
 */
export interface PartitionEncoder {
  encodeChunks(p: StoragePartition, state: AppState): string[];
}

/** 队列观测快照（设置页「持久化管理」区与证据文件读取）。 */
export interface QueueStats {
  pendingPartitions: string[];
  running: boolean;
  writeCycles: number;
  failures: number;
  lastError: string;
}

export class WriteQueue {
  private static instance: WriteQueue = new WriteQueue();

  /** 用户车道：点一下按钮就期待落盘（FR-07-07、10.4 步骤 5）。 */
  private static readonly USER_LANE: StoragePartition[] = [
    StoragePartition.META,
    StoragePartition.DEVICES,
    StoragePartition.RULES,
    StoragePartition.SCENES,
    StoragePartition.SETTINGS,
    StoragePartition.RETURN_SNAPSHOT
  ];

  private provider: StateProvider | undefined = undefined;
  private writer: PartitionWriter | undefined = undefined;
  private encoder: PartitionEncoder | undefined = undefined;
  private syncWriter: SyncPartitionWriter | undefined = undefined;

  /** 待执行集合：按分区合并，同分区重复 dirty 只保留一次（天然「最后一次胜出」）。 */
  private dirty: Set<StoragePartition> = new Set<StoragePartition>();
  /** 单链尾指针：任何时刻只有 1 个写任务在执行。 */
  private chain: Promise<void> = Promise.resolve();
  /** 正在进行的 flush（重入时返回同一个 Promise）。 */
  private current: Promise<void> | undefined = undefined;
  private busy: boolean = false;

  private userTimer: number = -1;
  private logTimer: number = -1;
  /** 日志车道的累计写次数（到 `FLUSH_MAX_PENDING_LOG_WRITES` 立即触发）。 */
  private logMarks: number = 0;

  private cycles: number = 0;
  private failures: number = 0;
  private streak: number = 0;
  private lastError: string = '';

  static getInstance(): WriteQueue {
    return WriteQueue.instance;
  }

  private constructor() {
  }

  // ——————————————————————————————————————————————————————————
  // 装配
  // ——————————————————————————————————————————————————————————

  /** 注入快照源与异步写面（T4-03 在 `AppDataRepository` 构造/初始化时调用一次）。 */
  configure(provider: StateProvider, writer: PartitionWriter): void {
    this.provider = provider;
    this.writer = writer;
  }

  /** 注入分区编码器（T4-02 的 `Serializer` 适配器）。未注入时 flush 保留 dirty 并记失败。 */
  setEncoder(encoder: PartitionEncoder): void {
    this.encoder = encoder;
  }

  /** 注入同步收尾写面（`onDestroy` 路径）。未注入时 `flushNowSync()` 保留 dirty 并记失败。 */
  setSyncWriter(writer: SyncPartitionWriter): void {
    this.syncWriter = writer;
  }

  // ——————————————————————————————————————————————————————————
  // 入队：两车道 debounce + 按分区合并
  // ——————————————————————————————————————————————————————————

  /**
   * 标记分区待写。**不返回 Promise**（业务写入面是同步的 `void`，不能 await）。
   *
   * 合并窗口从「本车道第一次 mark」开始计时，窗口内后续 mark 只合并、不重置计时器：
   * 若每次都重置，4 s 一次的采样会让 30 s 日志窗口永不触发（这正是 20 次兜底存在的原因）。
   */
  mark(partitions: StoragePartition[]): void {
    if (partitions.length === 0) {
      return;
    }
    let userLane: boolean = false;
    let logLane: boolean = false;
    for (let i = 0; i < partitions.length; i++) {
      const p: StoragePartition = partitions[i];
      this.dirty.add(p);
      if (WriteQueue.isUserLane(p)) {
        userLane = true;
      } else {
        logLane = true;
        this.logMarks = this.logMarks + 1;
      }
    }
    if (this.logMarks >= FLUSH_MAX_PENDING_LOG_WRITES) {
      this.logMarks = 0;
      this.fireAndForget();
      return;
    }
    this.armTimers(userLane, logLane);
  }

  // ——————————————————————————————————————————————————————————
  // 强制 flush
  // ——————————————————————————————————————————————————————————

  /**
   * 强制立即落盘（未指定分区则写全部 dirty）。
   *
   * 重入去重：同一时刻的第二次调用返回**同一个** `Promise`，不排队重复写（§1.2-B）。
   * 若在写周期进行中追加了分区，它们保持 dirty，由周期结束后的 `armTimersForRemaining()` 兜住。
   *
   * 返回的 Promise **总是 resolve**；失败经 `stats()` 暴露（见文件头第 3 条）。
   */
  flushNow(partitions?: StoragePartition[]): Promise<void> {
    if (partitions !== undefined) {
      for (let i = 0; i < partitions.length; i++) {
        this.dirty.add(partitions[i]);
      }
    }
    this.cancelTimers();
    this.logMarks = 0;

    const active: Promise<void> | undefined = this.current;
    if (active !== undefined) {
      return active;
    }

    const next: Promise<void> = this.chain.then((): Promise<void> => this.runCycle());
    this.current = next;
    const clearCurrent = (): void => {
      if (this.current === next) {
        this.current = undefined;
      }
    };
    next.then(clearCurrent, clearCurrent);
    // 尾指针吞掉异常形态，保证后续任务不会被前一个任务卡死（`runCycle` 本身不抛）。
    this.chain = next.then((): void => {
    }, (): void => {
    });
    return next;
  }

  /**
   * 收尾同步落盘：**不经队列**，直接由 provider 取快照同步写（`onDestroy` 用）。
   *
   * 为什么不能复用异步面：`onDestroy` 返回后事件循环不再推进，`await` 之后的代码不会执行，
   * 异步写必然丢。此路径只做「尽力而为」，失败保留 dirty 并记失败，绝不抛。
   */
  flushNowSync(): void {
    this.cancelTimers();
    this.logMarks = 0;

    const targets: StoragePartition[] = this.pendingPartitions();
    if (targets.length === 0) {
      return;
    }
    const provider: StateProvider | undefined = this.provider;
    const encoder: PartitionEncoder | undefined = this.encoder;
    const writer: SyncPartitionWriter | undefined = this.syncWriter;
    if (provider === undefined || encoder === undefined || writer === undefined) {
      this.noteFailure('SYNC_WRITER_NOT_CONFIGURED');
      return;
    }

    const state: AppState = provider();
    const prepared: StoragePartition[] = [];
    for (let i = 0; i < targets.length; i++) {
      const p: StoragePartition = targets[i];
      try {
        const chunks: string[] = encoder.encodeChunks(p, state);
        if (chunks.length > CHUNK_INDEX_MAX + 1) {
          throw new Error('块数超上限 ' + (CHUNK_INDEX_MAX + 1) + '：' + chunks.length);
        }
        const header: ChunkHeader = {
          p: p,
          n: chunks.length,
          t: TimeUtil.now(),
          v: CHUNK_FORMAT_VERSION
        };
        writer.writeChunks(p, chunks);
        writer.writeHeader(p, header);
        writer.trimChunks(p, chunks.length);
        prepared.push(p);
      } catch (err) {
        this.noteFailure('SYNC_WRITE_FAILED:' + p + ':' +
          (err instanceof Error ? err.message : 'unknown-error'));
      }
    }
    if (prepared.length === 0) {
      return;
    }
    try {
      writer.flushOnce();
      for (let i = 0; i < prepared.length; i++) {
        this.dirty.delete(prepared[i]);
      }
      this.cycles = this.cycles + 1;
      this.streak = 0;
    } catch (err) {
      this.noteFailure('SYNC_FLUSH_FAILED:' +
        (err instanceof Error ? err.message : 'unknown-error'));
    }
  }

  /** 等当前链清空（L2 单测与收尾用）。`chain` 永不 reject。 */
  drain(): Promise<void> {
    return this.chain;
  }

  // ——————————————————————————————————————————————————————————
  // 观测
  // ——————————————————————————————————————————————————————————

  pendingPartitions(): StoragePartition[] {
    const result: StoragePartition[] = [];
    this.dirty.forEach((p: StoragePartition): void => {
      result.push(p);
    });
    return result;
  }

  stats(): QueueStats {
    const pending: StoragePartition[] = this.pendingPartitions();
    const names: string[] = [];
    for (let i = 0; i < pending.length; i++) {
      names.push(pending[i]);
    }
    const snapshot: QueueStats = {
      pendingPartitions: names,
      running: this.busy,
      writeCycles: this.cycles,
      failures: this.failures,
      lastError: this.lastError
    };
    return snapshot;
  }

  /** 连续失败次数（成功一次即清零）；`>= FLUSH_FAIL_WARN_STREAK` 时设置页显示常驻告警（T4-04）。 */
  failStreak(): number {
    return this.streak;
  }

  // ——————————————————————————————————————————————————————————
  // 内部：一个写周期
  // ——————————————————————————————————————————————————————————

  /**
   * 一个 flush 周期 = 逐个 dirty 分区 `writeChunks` → `writeHeader` → `trimChunks`，
   * **全部分区完成后只调用一次** `flushOnce()`（§4.2 执行顺序契约，判据 A7）。
   *
   * 该方法是 `private async` 且**内部全捕获**：`flushNow()` 返回的 Promise 永不 reject。
   */
  private async runCycle(): Promise<void> {
    const targets: StoragePartition[] = this.pendingPartitions();
    if (targets.length === 0) {
      // 空批次不计周期、不调 flushOnce（避免 200 ms 定时器在已写完后空转出假周期）。
      return;
    }
    this.busy = true;

    const provider: StateProvider | undefined = this.provider;
    const encoder: PartitionEncoder | undefined = this.encoder;
    const writer: PartitionWriter | undefined = this.writer;
    if (provider === undefined || encoder === undefined || writer === undefined) {
      this.busy = false;
      this.noteFailure('WRITER_NOT_CONFIGURED');
      return; // dirty 保留，下次 mark 重试
    }

    // ★ 执行期取快照：入队时取会让旧快照覆盖新数据（§1.2-D 被否方案）。
    const state: AppState = provider();
    const prepared: StoragePartition[] = [];
    let failed: boolean = false;

    for (let i = 0; i < targets.length; i++) {
      const p: StoragePartition = targets[i];
      try {
        const chunks: string[] = encoder.encodeChunks(p, state);
        if (chunks.length > CHUNK_INDEX_MAX + 1) {
          // 不得用 5 位序号续写（会破坏 `chunkIndexOf` 解析规则），拒绝写入该分区并记失败。
          throw new Error('块数超上限 ' + (CHUNK_INDEX_MAX + 1) + '：' + chunks.length);
        }
        const header: ChunkHeader = {
          p: p,
          n: chunks.length,
          t: TimeUtil.now(),
          v: CHUNK_FORMAT_VERSION
        };
        await writer.writeChunks(p, chunks); // 步 1
        await writer.writeHeader(p, header); // 步 2（提交点）
        await writer.trimChunks(p, chunks.length); // 步 3（删孤儿块）
        prepared.push(p);
      } catch (err) {
        failed = true;
        // **不阻断其他分区**：该分区保持 dirty，其余继续（§1.2-B 失败行）。
        this.noteFailure('WRITE_FAILED:' + p + ':' +
          (err instanceof Error ? err.message : 'unknown-error'));
      }
    }

    if (prepared.length > 0) {
      try {
        await writer.flushOnce(); // 步 4：整批一次（§1.2-C）
        for (let i = 0; i < prepared.length; i++) {
          this.dirty.delete(prepared[i]); // 删只在 flush 成功之后（§1.2.1 第 1 条）
        }
        this.cycles = this.cycles + 1;
      } catch (err) {
        failed = true;
        this.noteFailure('FLUSH_FAILED:' +
          (err instanceof Error ? err.message : 'unknown-error')); // dirty 一个都不删
      }
    }

    this.busy = false;
    if (failed) {
      // 本周期有任何失败：`streak` 已在 `noteFailure()` 累加，不重置、也不武装定时器
      // （§1.2.1 重试语义：失败后靠下一次 `mark()` 自然重触发，不做定时重试）。
      return;
    }
    this.streak = 0; // 整周期无失败才算「连续失败中断」
    if (this.dirty.size > 0) {
      // 周期进行中又来了新分区：重新武装定时器，避免它们永远留在 dirty 里。
      this.armTimersForRemaining();
    }
  }

  // ——————————————————————————————————————————————————————————
  // 内部：车道与定时器
  // ——————————————————————————————————————————————————————————

  private static isUserLane(p: StoragePartition): boolean {
    return WriteQueue.USER_LANE.indexOf(p) >= 0;
  }

  private armTimers(userLane: boolean, logLane: boolean): void {
    if (userLane && this.userTimer < 0) {
      this.userTimer = setTimeout((): void => {
        this.userTimer = -1;
        this.fireAndForget();
      }, FLUSH_DEBOUNCE_USER_MS);
    }
    if (logLane && this.logTimer < 0) {
      this.logTimer = setTimeout((): void => {
        this.logTimer = -1;
        this.fireAndForget();
      }, FLUSH_DEBOUNCE_LOG_MS);
    }
  }

  private armTimersForRemaining(): void {
    let userLane: boolean = false;
    let logLane: boolean = false;
    this.dirty.forEach((p: StoragePartition): void => {
      if (WriteQueue.isUserLane(p)) {
        userLane = true;
      } else {
        logLane = true;
      }
    });
    this.armTimers(userLane, logLane);
  }

  private cancelTimers(): void {
    if (this.userTimer >= 0) {
      clearTimeout(this.userTimer);
      this.userTimer = -1;
    }
    if (this.logTimer >= 0) {
      clearTimeout(this.logTimer);
      this.logTimer = -1;
    }
  }

  /** 定时器回调里发起 flush：显式挂空回调，避免「floating promise」形态。 */
  private fireAndForget(): void {
    const pending: Promise<void> = this.flushNow();
    pending.then((): void => {
    }, (): void => {
    });
  }

  private noteFailure(detail: string): void {
    this.failures = this.failures + 1;
    this.streak = this.streak + 1;
    this.lastError = detail;
  }
}
