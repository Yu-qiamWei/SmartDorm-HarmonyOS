/**
 * 智寓 · 规则纯逻辑内核（排序 / AND 求值 / 边沿去重）
 *
 * ★ 零 `@kit.*` 依赖：只 import `model/`，可在 Node 侧独立单测（设计 10.2 L2 行）。
 *   这是 L2 验证路径成立的前提——`RuleEngine` 因写日志必然引入 `IdGenerator`
 *   （`@kit.ArkTS`），Node 侧无法解析，故纯逻辑必须物理外置到本文件。
 *
 * ★ 阈值判定唯一归口（设计 4.8）：`matchConditions()` 是全工程**唯一**的条件比较实现，
 *   `EnvironmentService` / 页面 / 图表都不得再次比较阈值。
 *
 * 依据：design/系统架构设计.md 4.1 MI-12、FR-04-02/09/10、Q-10。
 */
import { AutomationRule } from '../model/AutomationRule';
import { AutomationCondition } from '../model/AutomationCondition';
import { EnvironmentData } from '../model/EnvironmentData';
import { Operator, SensorType } from '../model/Enums';

export class RuleMatcher {
  /**
   * 确定性排序：priority 升序（小者优先）→ createdAt 升序 → id 字典序。
   * 返回新数组，**不修改入参**；三关键字全覆盖保证任意两条规则顺序唯一（TC-E-06 前提）。
   */
  static sortRules(rules: AutomationRule[]): AutomationRule[] {
    const copy: AutomationRule[] = rules.slice();
    copy.sort((a: AutomationRule, b: AutomationRule): number => {
      if (a.priority !== b.priority) {
        return a.priority - b.priority;
      }
      if (a.createdAt !== b.createdAt) {
        return a.createdAt - b.createdAt;
      }
      if (a.id === b.id) {
        return 0;
      }
      return a.id < b.id ? -1 : 1;
    });
    return copy;
  }

  /**
   * 条件求值：P0 固定 AND（`ConditionLogic.AND`），全部条件成立才算命中。
   * 条件为空时返回 false——「至少 1 条条件」是契约，空条件不应被视为恒真而误触发。
   */
  static matchConditions(rule: AutomationRule, env: EnvironmentData): boolean {
    if (rule.conditions.length === 0) {
      return false;
    }
    for (let i = 0; i < rule.conditions.length; i++) {
      if (!RuleMatcher.evaluateCondition(rule.conditions[i], env)) {
        return false;
      }
    }
    return true;
  }

  /** 命中的条件子集（写入 RuleExecutionLog.matchedConditions，供事后核查）。 */
  static matchedConditions(rule: AutomationRule, env: EnvironmentData): AutomationCondition[] {
    const result: AutomationCondition[] = [];
    for (let i = 0; i < rule.conditions.length; i++) {
      const condition: AutomationCondition = rule.conditions[i];
      if (RuleMatcher.evaluateCondition(condition, env)) {
        result.push(condition);
      }
    }
    return result;
  }

  /** 单条件判定：GT / LT 比较数值读数；IS_TRUE / IS_FALSE 只读 humanPresence。 */
  static evaluateCondition(condition: AutomationCondition, env: EnvironmentData): boolean {
    switch (condition.operator) {
      case Operator.IS_TRUE:
        return env.humanPresence;
      case Operator.IS_FALSE:
        return !env.humanPresence;
      case Operator.GT:
        return RuleMatcher.numericOf(condition.sensorType, env) > condition.threshold;
      case Operator.LT:
        return RuleMatcher.numericOf(condition.sensorType, env) < condition.threshold;
      default:
        return false;
    }
  }

  /**
   * 边沿触发判定（FR-04-10）：仅 `false → true` 触发一次。
   * `(false,true)=true`，其余三种组合一律 false（持续满足不重复触发）。
   */
  static isEdgeTriggered(lastSatisfied: boolean, satisfied: boolean): boolean {
    return !lastSatisfied && satisfied;
  }

  /** 去重标记推进：求值后 `lastSatisfied` 恒等于本轮命中结果（不留中间态）。 */
  static nextDedupFlag(prevSatisfied: boolean, satisfied: boolean): boolean {
    return satisfied;
  }

  /**
   * 重置去重标记：编辑 / 启停 / 总开关切换后调用，使边沿重新武装（FR-04-09/10）。
   * 返回**新数组**（每条规则为新对象），不修改入参，便于仓储整体替换后 notify。
   */
  static resetDedup(rules: AutomationRule[]): AutomationRule[] {
    const result: AutomationRule[] = [];
    for (let i = 0; i < rules.length; i++) {
      const rule: AutomationRule = rules[i];
      const next: AutomationRule = {
        id: rule.id,
        name: rule.name,
        enabled: rule.enabled,
        logic: rule.logic,
        conditions: rule.conditions.slice(),
        actions: rule.actions.slice(),
        priority: rule.priority,
        lastSatisfied: false,
        lastTriggeredAt: rule.lastTriggeredAt,
        executionCount: rule.executionCount,
        createdAt: rule.createdAt,
        updatedAt: rule.updatedAt
      };
      result.push(next);
    }
    return result;
  }

  /** 传感器数值读数统一入口（布尔型映射为 1/0，仅用于 GT/LT 的防御性比较）。 */
  static numericOf(sensorType: SensorType, env: EnvironmentData): number {
    switch (sensorType) {
      case SensorType.TEMPERATURE:
        return env.temperature;
      case SensorType.HUMIDITY:
        return env.humidity;
      case SensorType.ILLUMINANCE:
        return env.illuminance;
      case SensorType.AIR_QUALITY:
        return env.airQuality;
      case SensorType.HUMAN_PRESENCE:
        return env.humanPresence ? 1 : 0;
      default:
        return 0;
    }
  }
}
