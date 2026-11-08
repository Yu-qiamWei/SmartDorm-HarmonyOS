/**
 * 智寓 · 规则引擎（MI-12 / SC-02 核心 / Q-10 先执行者优先）
 *
 * 求值主流程（顺序**不得调换**，见设计 4.3 / 4.4 与任务列表 T3-03）：
 *   ① `guard = new WriteGuard(); guard.reset()`                  —— 每轮新实例，不跨轮（B-1）
 *   ② `automationEnabled === false` → 立即返回带 `skipReason` 的空报告
 *      （不执行、不写日志、**不改 `lastSatisfied`**）
 *   ③ 取启用的规则 → `RuleMatcher.sortRules()`（priority↑→createdAt↑→id 字典序，复用不重写）
 *   ④ 逐规则 `satisfied = RuleMatcher.matchConditions(rule, snapshot)`
 *        · `satisfied && !lastSatisfied` → 边沿触发：动作按 `order` 升序逐个执行
 *        · `satisfied &&  lastSatisfied` → 进 `skippedDedupRules`，**不产生日志**（防刷屏）
 *        · `!satisfied`                  → 只回写 `lastSatisfied=false`
 *   ⑤ 仅为「本轮真实尝试过动作」（含冲突跳过）的触发规则生成 `RuleExecutionLog`
 *   ⑥ `repo.commitRules(nextRules, 'rule-eval')`　　← 先写规则状态
 *   ⑦ `await repo.commitRuleLogs(report)`　　　　　← 后写执行日志（护栏 A-2 唯一入口）
 *   ⑧ `report.durationMs = now - startedAt`
 *
 * ★ 为什么 ⑥ 先于 ⑦（4.3）：先写日志再写规则状态，中途异常会出现
 *   「日志说执行了、`lastSatisfied` 还是 false」→ 下一轮重复触发；反之最多丢一轮日志。
 * ★ `lastSatisfied` 回写覆盖**所有本轮被求值的启用规则**（不只是被触发的），
 *   否则未触发规则永远停在旧值，边沿判定就错了。
 * ★ 冲突状态用 `RuleExecStatus.SKIPPED_CONFLICT`（日志状态），
 *   动作结果码用 `ResultCode.CONFLICT_SKIPPED`（命令结果）——两者不混用。
 *
 * 依据：design/系统架构设计.md 4.1 MI-12、4.3、4.4、4.6，PRD FR-04-01~15 / FR-08-06。
 */
import { IRuleEngine } from './ServiceContracts';
import { RuleMatcher } from './RuleMatcher';
import { RuleActionExecutor } from './RuleActionExecutor';
import { WriteGuard } from './WriteGuard';
import { DeviceService } from './DeviceService';
import { AppDataRepository } from '../store/AppDataRepository';
import { AutomationRule } from '../model/AutomationRule';
import { AutomationAction } from '../model/AutomationAction';
import { EnvironmentData } from '../model/EnvironmentData';
import { AppSettings } from '../model/AppSettings';
import {
  RuleEvaluationReport, RuleOutcome, ActionOutcome
} from '../model/Reports';
import { RuleExecutionLog, ActionExecutionDetail } from '../model/Logs';
import { ResultCode, RuleExecStatus } from '../model/Enums';
import { CommandResult } from '../model/CommandResult';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';

export class RuleEngine implements IRuleEngine {
  private static instance: RuleEngine = new RuleEngine();

  private executor: RuleActionExecutor;

  static getInstance(): RuleEngine {
    return RuleEngine.instance;
  }

  private constructor() {
    this.executor = new RuleActionExecutor(DeviceService.getInstance());
  }

  /** MI-12 求值入口：永久返回结构化报告，绝不抛异常给调用方（采样链路不能被打断）。 */
  async evaluate(snapshot: EnvironmentData): Promise<RuleEvaluationReport> {
    const startedAt: number = TimeUtil.now();
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const settings: AppSettings = repo.getState().settings;
    const allRules: AutomationRule[] = repo.getState().rules;

    // ① 本轮唯一 guard（B-1：不跨轮、不做单例）
    const guard: WriteGuard = new WriteGuard();
    guard.reset();

    // ② 总开关关闭：不执行、不写日志、不改 lastSatisfied
    if (!settings.automationEnabled) {
      const blocked: RuleEvaluationReport = RuleEngine.emptyReport(
        snapshot, settings, allRules.length,
        '自动化总开关已关闭，本轮不执行任何规则'
      );
      blocked.durationMs = TimeUtil.now() - startedAt;
      return blocked;
    }

    // ③ 启用规则 + 确定性排序（复用 T3-01 的 RuleMatcher.sortRules，不重写）
    const enabledRules: AutomationRule[] = [];
    for (let i = 0; i < allRules.length; i++) {
      if (allRules[i].enabled) {
        enabledRules.push(allRules[i]);
      }
    }
    const ordered: AutomationRule[] = RuleMatcher.sortRules(enabledRules);

    const triggeredRules: string[] = [];
    const skippedDedupRules: string[] = [];
    const skippedConflictRules: string[] = [];
    const outcomes: RuleOutcome[] = [];
    const newLogs: RuleExecutionLog[] = [];
    const rewritten: Map<string, AutomationRule> = new Map<string, AutomationRule>();

    for (let i = 0; i < ordered.length; i++) {
      const rule: AutomationRule = ordered[i];
      const satisfied: boolean = RuleMatcher.matchConditions(rule, snapshot);

      // 条件不成立：只回写去重标记
      if (!satisfied) {
        rewritten.set(rule.id, RuleEngine.withDedup(rule, false));
        continue;
      }
      // 持续满足：边沿去重，不执行、不写日志
      if (rule.lastSatisfied) {
        skippedDedupRules.push(rule.id);
        rewritten.set(rule.id, RuleEngine.withDedup(rule, true));
        continue;
      }

      // ④ 边沿触发：动作按 order 升序串行执行
      const ruleStartedAt: number = TimeUtil.now();
      const executed: ActionOutcome[] = [];
      const skippedActions: ActionOutcome[] = [];
      const actions: AutomationAction[] = RuleEngine.sortActions(rule.actions);
      for (let j = 0; j < actions.length; j++) {
        const action: AutomationAction = actions[j];
        const settled: Promise<ActionOutcome> = this.executor.execute(action, guard, rule.id);
        // 单个动作异常不得中断整轮：用 rejection 处理器把它收敛为 FAILED 结果
        const outcome: ActionOutcome = await settled.then(
          (value: ActionOutcome): ActionOutcome => value,
          (): ActionOutcome => RuleEngine.failedOutcome(action)
        );
        if (outcome.code === ResultCode.CONFLICT_SKIPPED) {
          skippedActions.push(outcome);
        } else {
          executed.push(outcome);
        }
      }

      const status: RuleExecStatus = RuleEngine.statusOf(executed, skippedActions);
      const durationMs: number = TimeUtil.now() - ruleStartedAt;
      const errorMsg: string = RuleEngine.errorOf(executed, skippedActions);
      const attempted: number = executed.length + skippedActions.length;

      triggeredRules.push(rule.id);
      if (skippedActions.length > 0) {
        skippedConflictRules.push(rule.id);
      }
      const ruleOutcome: RuleOutcome = {
        ruleId: rule.id,
        ruleName: rule.name,
        satisfied: true,
        status: status,
        actionOutcomes: executed.concat(skippedActions),
        errorMsg: errorMsg
      };
      outcomes.push(ruleOutcome);

      // ⑤ 只有「真实尝试过动作」的规则才产出执行日志
      if (attempted > 0) {
        newLogs.push(
          this.buildExecutionLog(rule, snapshot, executed, skippedActions, status, errorMsg, durationMs)
        );
      }
      rewritten.set(
        rule.id,
        RuleEngine.afterTrigger(rule, TimeUtil.now())
      );
    }

    // 全量回写：被求值的启用规则用新对象，停用规则原样保留（未参与本轮求值）
    const nextRules: AutomationRule[] = [];
    for (let i = 0; i < allRules.length; i++) {
      const rule: AutomationRule = allRules[i];
      const next: AutomationRule | undefined = rewritten.get(rule.id);
      nextRules.push(next === undefined ? rule : next);
    }

    const report: RuleEvaluationReport = {
      evaluatedAt: startedAt,
      snapshot: snapshot,
      automationEnabled: settings.automationEnabled,
      skipReason: '',
      totalRules: allRules.length,
      triggeredRules: triggeredRules,
      skippedDedupRules: skippedDedupRules,
      skippedConflictRules: skippedConflictRules,
      outcomes: outcomes,
      newLogs: newLogs,
      durationMs: 0
    };

    // ⑥ 先写规则状态
    repo.commitRules(nextRules, 'rule-eval');
    // ⑦ 后写执行日志（护栏 A-2 唯一入口；内部按 FIFO 1000 裁剪）
    const committed: CommandResult<void> = await repo.commitRuleLogs(report);
    if (!committed.success) {
      // 日志提交失败不改变本轮已生效的设备状态，但必须在报告里留下痕迹
      report.skipReason = '执行日志提交失败：' + committed.message;
    }
    // ⑧ 真实耗时（在 ⑦ 之后赋值，报告对象按引用返回给调用方）
    report.durationMs = TimeUtil.now() - startedAt;
    return report;
  }

  /**
   * 生成一条执行日志（**全工程唯一构造 `RuleExecutionLog` 的方法**，护栏 A-3）。
   */
  private buildExecutionLog(
    rule: AutomationRule,
    snapshot: EnvironmentData,
    executed: ActionOutcome[],
    skipped: ActionOutcome[],
    status: RuleExecStatus,
    errorMsg: string,
    durationMs: number
  ): RuleExecutionLog {
    const log: RuleExecutionLog = {
      id: IdGenerator.log(),
      timestamp: TimeUtil.now(),
      ruleId: rule.id,
      ruleName: rule.name,
      snapshot: snapshot,
      matchedConditions: RuleMatcher.matchedConditions(rule, snapshot),
      executedActions: RuleEngine.detailsOf(rule, executed),
      skippedActions: RuleEngine.detailsOf(rule, skipped),
      status: status,
      errorMsg: errorMsg,
      durationMs: durationMs
    };
    return log;
  }

  // ——————————————————————————————————————————————————————
  // 内部：状态判定与对象变换
  // ——————————————————————————————————————————————————————

  /**
   * 执行状态判定（DM-08）：
   *   全部动作冲突跳过 → SKIPPED_CONFLICT
   *   无任何成功 → FAILED
   *   全部成功 → SUCCESS
   *   其余 → PARTIAL
   * 口径说明：`NO_CHANGE`（幂等，目标态已达成）计入**成功**，
   * 因为它 `success=true` 且设备态与目标一致；把它算失败会把「本来就对」误报为失败。
   */
  private static statusOf(executed: ActionOutcome[], skipped: ActionOutcome[]): RuleExecStatus {
    const attempted: number = executed.length + skipped.length;
    if (attempted === 0) {
      return RuleExecStatus.FAILED; // 规则无动作（契约上不应出现），标记失败而非静默
    }
    if (skipped.length === attempted) {
      return RuleExecStatus.SKIPPED_CONFLICT;
    }
    let success: number = 0;
    for (let i = 0; i < executed.length; i++) {
      if (RuleEngine.isSuccessCode(executed[i].code)) {
        success = success + 1;
      }
    }
    if (success === 0) {
      return RuleExecStatus.FAILED;
    }
    return success === attempted ? RuleExecStatus.SUCCESS : RuleExecStatus.PARTIAL;
  }

  private static isSuccessCode(code: ResultCode): boolean {
    return code === ResultCode.OK || code === ResultCode.NO_CHANGE;
  }

  /** 失败/冲突原因汇总；全成功时为空串（日志里不写无意义文案）。 */
  private static errorOf(executed: ActionOutcome[], skipped: ActionOutcome[]): string {
    const parts: string[] = [];
    for (let i = 0; i < executed.length; i++) {
      if (!RuleEngine.isSuccessCode(executed[i].code)) {
        parts.push(executed[i].command + ':' + executed[i].code);
      }
    }
    if (skipped.length > 0) {
      parts.push('冲突跳过 ' + skipped.length + ' 个动作');
    }
    return parts.join('; ');
  }

  /** 动作结果 → 日志明细（value 从规则内同 id 动作回查，保持可读且不复制映射表）。 */
  private static detailsOf(
    rule: AutomationRule,
    outcomes: ActionOutcome[]
  ): ActionExecutionDetail[] {
    const result: ActionExecutionDetail[] = [];
    for (let i = 0; i < outcomes.length; i++) {
      const outcome: ActionOutcome = outcomes[i];
      result.push({
        actionId: outcome.actionId,
        targetDeviceId: outcome.deviceId,
        command: outcome.command,
        value: RuleEngine.valueOf(rule, outcome.actionId),
        result: outcome.code,
        message: outcome.message
      });
    }
    return result;
  }

  private static valueOf(rule: AutomationRule, actionId: string): string {
    for (let i = 0; i < rule.actions.length; i++) {
      if (rule.actions[i].id === actionId) {
        return String(rule.actions[i].value);
      }
    }
    return '';
  }

  /** 动作按 order 升序（同 order 按 id 字典序，保证确定性）。 */
  private static sortActions(actions: AutomationAction[]): AutomationAction[] {
    const copy: AutomationAction[] = actions.slice();
    copy.sort((a: AutomationAction, b: AutomationAction): number => {
      if (a.order !== b.order) {
        return a.order - b.order;
      }
      if (a.id === b.id) {
        return 0;
      }
      return a.id < b.id ? -1 : 1;
    });
    return copy;
  }

  /** 复制规则并写入去重标记（不修改入参对象）。 */
  private static withDedup(rule: AutomationRule, satisfied: boolean): AutomationRule {
    const next: AutomationRule = {
      id: rule.id,
      name: rule.name,
      enabled: rule.enabled,
      logic: rule.logic,
      conditions: rule.conditions.slice(),
      actions: rule.actions.slice(),
      priority: rule.priority,
      lastSatisfied: satisfied,
      lastTriggeredAt: rule.lastTriggeredAt,
      executionCount: rule.executionCount,
      createdAt: rule.createdAt,
      updatedAt: rule.updatedAt
    };
    return next;
  }

  /** 触发后写回：lastSatisfied=true、lastTriggeredAt=now、executionCount+1。 */
  private static afterTrigger(rule: AutomationRule, now: number): AutomationRule {
    const next: AutomationRule = {
      id: rule.id,
      name: rule.name,
      enabled: rule.enabled,
      logic: rule.logic,
      conditions: rule.conditions.slice(),
      actions: rule.actions.slice(),
      priority: rule.priority,
      lastSatisfied: true,
      lastTriggeredAt: now,
      executionCount: rule.executionCount + 1,
      createdAt: rule.createdAt,
      updatedAt: rule.updatedAt
    };
    return next;
  }

  /** 动作级异常兜底结果（引擎自身不抛异常，异常折成 FAILED 明细）。 */
  private static failedOutcome(action: AutomationAction): ActionOutcome {
    const outcome: ActionOutcome = {
      actionId: action.id,
      deviceId: action.targetDeviceId,
      command: action.command,
      paramKey: '',
      code: ResultCode.UNKNOWN,
      message: '动作执行异常，已记录为失败'
    };
    return outcome;
  }

  /** 空报告骨架（总开关关闭时使用；newLogs 恒为空，绝不伪造执行记录）。 */
  private static emptyReport(
    snapshot: EnvironmentData,
    settings: AppSettings,
    totalRules: number,
    skipReason: string
  ): RuleEvaluationReport {
    const report: RuleEvaluationReport = {
      evaluatedAt: TimeUtil.now(),
      snapshot: snapshot,
      automationEnabled: settings.automationEnabled,
      skipReason: skipReason,
      totalRules: totalRules,
      triggeredRules: [],
      skippedDedupRules: [],
      skippedConflictRules: [],
      outcomes: [],
      newLogs: [],
      durationMs: 0
    };
    return report;
  }
}
