/**
 * 智寓 · 持久化诊断环形缓冲（设计 8.6 / 任务列表-第四阶段 §4.5）
 *
 * 用途：把「加载降级」「块缺失/多余」「单条守卫丢弃」「写失败」这些**否则不可见**的事件
 * 记在内存里，供设置页诊断区（T4-04，FR-07-08）与阶段五证据文件直接读取。
 *
 * 三条设计约束：
 *   ① **不落盘**：诊断若落盘，写失败 → 记诊断 → 又触发写失败，会形成自噬循环；
 *   ② **不用 IdGenerator**：它依赖系统侧随机数能力，一旦引入本类就失去 Node 侧可测性；
 *      改用自增 `seq`（从 1 起），环形淘汰后 `seq` 继续递增，因此 `list()` 首条 `seq`
 *      就能直接反映「已经滚掉多少条」；
 *   ③ **只返回副本**：`list()` 必须给调用方新数组 + 新条目对象，页面改它不能污染缓冲。
 *
 * 本类零系统 API 依赖（不 import 任何 Kit 模块），可在 Node 侧单测（判据 B8）。
 *
 * 依据：design/任务列表-第四阶段.md 1.1.3、1.2.1、4.5。
 */
import { DIAGNOSTIC_CAPACITY } from '../common/Constants';

/** 诊断级别。 */
export enum DiagnosticLevel {
  INFO = 'INFO',
  WARN = 'WARN',
  ERROR = 'ERROR'
}

/** 单条诊断记录。 */
export interface DiagnosticEntry {
  seq: number; // 自增序号，从 1 起，环形淘汰后继续递增
  timestamp: number; // epoch ms
  level: DiagnosticLevel;
  code: string; // 短码：ENTRY_DROPPED / CHUNK_MISSING / EXTRA_CHUNK / DECODE_FAILED / WRITE_FAILED ...
  detail: string; // 人类可读细节（含分区名、索引列表、条数等）
}

export class StorageDiagnostics {
  private static instance: StorageDiagnostics = new StorageDiagnostics();

  /** 环形缓冲（用数组 + 头部滑移实现，容量固定 DIAGNOSTIC_CAPACITY）。 */
  private entries: DiagnosticEntry[] = [];
  private nextSeq: number = 1;

  static getInstance(): StorageDiagnostics {
    return StorageDiagnostics.instance;
  }

  private constructor() {
  }

  /**
   * 记一条诊断。超过 `DIAGNOSTIC_CAPACITY` 时**丢最旧**（`shift()` 一次一条）。
   *
   * `timestamp` 用 `Date.now()` 而不是 `TimeUtil`，是为了让本类保持零 import
   * （`TimeUtil.now()` 就是 `Date.now()`，两者取值一致）。
   */
  record(level: DiagnosticLevel, code: string, detail: string): void {
    const entry: DiagnosticEntry = {
      seq: this.nextSeq,
      timestamp: Date.now(),
      level: level,
      code: code,
      detail: detail
    };
    this.nextSeq = this.nextSeq + 1;
    this.entries.push(entry);
    while (this.entries.length > DIAGNOSTIC_CAPACITY) {
      this.entries.shift();
    }
  }

  /** 按 `seq` 升序返回**副本**（时间升序 == seq 升序，因为 `seq` 单调递增）。 */
  list(): DiagnosticEntry[] {
    const copy: DiagnosticEntry[] = [];
    for (let i = 0; i < this.entries.length; i++) {
      const src: DiagnosticEntry = this.entries[i];
      const item: DiagnosticEntry = {
        seq: src.seq,
        timestamp: src.timestamp,
        level: src.level,
        code: src.code,
        detail: src.detail
      };
      copy.push(item);
    }
    return copy;
  }

  /** 当前条数（≤ `DIAGNOSTIC_CAPACITY`）。 */
  size(): number {
    return this.entries.length;
  }

  /** 清空（重置/测试用）；`seq` **不**回零，保持「累计发生过多少条」的语义。 */
  clear(): void {
    this.entries = [];
  }
}
