/**
 * 智寓 · 规则求值报告 / 场景执行报告（MI-12 / MI-14 / 设计 3.10）
 *
 * ★ 护栏 A：RuleEvaluationReport.newLogs 是 RuleExecutionLog 的唯一提交载体，
 * 只由 RuleEngine 生成，经 AppDataRepository.commitRuleLogs(report) 单点提交。
 * 依据：design/系统架构设计.md 3.10 节、4.3 节 A-2/A-3。
 */
import { EnvironmentData } from './EnvironmentData';
import { RuleExecutionLog } from './Logs';
import { ResultCode, RuleExecStatus } from './Enums';

export interface ActionOutcome {
  actionId: string;
  deviceId: string;
  command: string;
  paramKey: string; // WriteGuard 的登记键
  code: ResultCode;
  message: string;
}

export interface RuleOutcome {
  ruleId: string;
  ruleName: string;
  satisfied: boolean;
  status: RuleExecStatus;
  actionOutcomes: ActionOutcome[];
  errorMsg: string;
}

export interface RuleEvaluationReport {
  evaluatedAt: number;
  snapshot: EnvironmentData;
  automationEnabled: boolean;
  skipReason: string; // 关闭时写明原因，开启时为空串
  totalRules: number;
  triggeredRules: string[]; // 本轮真实触发的 ruleId
  skippedDedupRules: string[]; // 边沿去重跳过的 ruleId
  skippedConflictRules: string[]; // 冲突跳过的 ruleId
  outcomes: RuleOutcome[];
  newLogs: RuleExecutionLog[]; // ★ 本轮由 RuleEngine 生成，唯一提交入口
  durationMs: number;
}

export interface SceneApplyItem {
  deviceId: string;
  code: ResultCode;
  message: string;
}

export interface SceneApplyReport {
  sceneId: string;
  sceneName: string;
  fromSceneId: string;
  appliedAt: number;
  total: number;
  appliedCount: number;
  failedCount: number;
  noChangeCount: number;
  items: SceneApplyItem[];
  restoredFromSnapshot: boolean; // 回寝时为 true
}
