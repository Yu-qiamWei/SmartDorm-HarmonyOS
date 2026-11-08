/**
 * 智寓 · 护栏 B-1/B-3 写入登记表（Q-10「先执行者优先」的判定内核）
 *
 * ★ 纯逻辑 + 零 `@kit.*` 依赖、零 `model/` 依赖，可在 Node 侧独立单测（L2）。
 *
 * 生命周期（设计 4.4）：
 *   - 每轮 `RuleEngine.evaluate()` 内 `new WriteGuard()` + `reset()`，方法返回即丢弃；
 *   - **不跨轮、不做单例**（B-1），因此这里刻意没有 getInstance()。
 *
 * 登记键：`(deviceId, paramKey)` 二元组（B-3）。paramKey 必须来自
 * `commandToParamKey(command)` 这一唯一映射（B-4），禁止第二处映射表。
 *
 * 覆盖范围（B-7）：仅规则引擎同轮求值；场景切换与手动控制不经过本类，
 * 但它们都必须走 `DeviceService` 的统一校验与 `OperationLog`。
 */
export interface GuardEntry {
  deviceId: string;
  paramKey: string;
  ruleId: string;
}

export class WriteGuard {
  /** 复合键 `deviceId|paramKey` → 登记项；用 Map 保证 O(1) 判定。 */
  private entries_: Map<string, GuardEntry> = new Map<string, GuardEntry>();

  /** 轮首重置：清空上一轮残留（B-1，不跨轮持有）。 */
  reset(): void {
    this.entries_.clear();
  }

  /**
   * 申请写入权：本元组首次出现返回 true（先到先得），
   * 已被本轮其他规则占用则返回 false（调用方必须据此跳过，不得调用 DeviceService，B-2）。
   */
  claim(deviceId: string, paramKey: string, ruleId: string): boolean {
    const key: string = WriteGuard.keyOf(deviceId, paramKey);
    if (this.entries_.has(key)) {
      return false;
    }
    const entry: GuardEntry = {
      deviceId: deviceId,
      paramKey: paramKey,
      ruleId: ruleId
    };
    this.entries_.set(key, entry);
    return true;
  }

  /** 该元组本轮是否已被占用（只读查询，不登记）。 */
  has(deviceId: string, paramKey: string): boolean {
    return this.entries_.has(WriteGuard.keyOf(deviceId, paramKey));
  }

  /** 本轮登记明细（按插入顺序），供执行日志与诊断核查。 */
  entries(): GuardEntry[] {
    const result: GuardEntry[] = [];
    this.entries_.forEach((entry: GuardEntry): void => {
      result.push(entry);
    });
    return result;
  }

  /** 本轮已登记条数。 */
  size(): number {
    return this.entries_.size;
  }

  /** 复合键构造（唯一实现，避免两处拼键口径不一致）。 */
  private static keyOf(deviceId: string, paramKey: string): string {
    return deviceId + '|' + paramKey;
  }
}
