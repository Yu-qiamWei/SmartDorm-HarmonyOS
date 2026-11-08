/**
 * 智寓 · 四类日志容量 FIFO 内核（Q-12 / 设计 4.5）
 *
 * ★ 纯函数 + 零 `@kit.*` 依赖：只 import `model/Enums` 与 `common/Constants`，
 *   保证可在 Node 侧独立单测（设计 10.2 L2 行 / 任务列表 §5.1 第 7 项）。
 *
 * 上限口径（设计 4.5，合计 ≤ 4500 条）：
 *   OperationLog      = settings.logLimit（默认 1000）
 *   RuleExecutionLog  = settings.logLimit（默认 1000）
 *   EnvironmentLog    = settings.logLimit × 2（默认 2000）
 *   SceneSwitchLog    = 固定 500
 *
 * trim 语义：按 `timestamp` 升序保留最新 limit 条，超限**丢最旧**；
 * 不修改入参数组，返回新数组。未超限时返回入参的浅拷贝（顺序原样保留）。
 */
import { LogType } from '../model/Enums';
import { DEFAULT_LOG_LIMIT, ENV_LOG_LIMIT_FACTOR, SCENE_LOG_LIMIT } from './Constants';

/** 可参与 FIFO 裁剪的最小契约：四类日志均带 timestamp。 */
export interface TimeStamped {
  timestamp: number;
}

export class Fifo {
  /** 按日志类型换算容量上限；logLimit ≤ 0 时回退默认 1000，避免 0 容量丢光。 */
  static limitOf(kind: LogType, logLimit: number): number {
    const base: number = logLimit > 0 ? logLimit : DEFAULT_LOG_LIMIT;
    switch (kind) {
      case LogType.OPERATION:
        return base;
      case LogType.RULE_EXECUTION:
        return base;
      case LogType.ENVIRONMENT:
        return base * ENV_LOG_LIMIT_FACTOR;
      case LogType.SCENE_SWITCH:
        return SCENE_LOG_LIMIT;
      default:
        return base;
    }
  }

  /** 超限裁剪：保序、丢最旧、返回新数组；limit ≤ 0 返回空数组（防御性，正常路径不会发生）。 */
  static trim<T extends TimeStamped>(list: T[], limit: number): T[] {
    if (limit <= 0) {
      const empty: T[] = [];
      return empty;
    }
    if (list.length <= limit) {
      return list.slice();
    }
    const sorted: T[] = list.slice();
    // Array.prototype.sort 在 ES2019 起为稳定排序，同 timestamp 保留原相对顺序。
    sorted.sort((a: T, b: T): number => a.timestamp - b.timestamp);
    return sorted.slice(sorted.length - limit);
  }

  /** 追加一条并裁剪，返回新数组（不改入参，便于仓储替换引用后触发通知）。 */
  static append<T extends TimeStamped>(list: T[], item: T, limit: number): T[] {
    const merged: T[] = list.slice();
    merged.push(item);
    return Fifo.trim(merged, limit);
  }
}
