/**
 * 智寓 · DM-03 AutomationRule（FR-04 核心）
 * 依据：design/系统架构设计.md 3.5 节。
 *
 * lastSatisfied 为边沿去重标记（FR-04-10），持久化保存，重启后连续；
 * 规则编辑 / 启停 / 总开关切换时须显式 resetDedup()（ST-03 实现）。
 */
import { ConditionLogic } from './Enums';
import { AutomationCondition } from './AutomationCondition';
import { AutomationAction } from './AutomationAction';

export interface AutomationRule {
  id: string; // rule_ + UUID
  name: string; // 非空
  enabled: boolean; // 停用后不参与求值
  logic: ConditionLogic; // P0 固定 AND
  conditions: AutomationCondition[]; // 至少 1 条
  actions: AutomationAction[]; // 至少 1 条
  priority: number; // 排序第一关键字，数值小者优先
  lastSatisfied: boolean; // 边沿去重标记，持久化保存
  lastTriggeredAt: number; // 最近一次真实执行时间，0=从未
  executionCount: number; // 累计真实执行次数
  createdAt: number; // 排序第二关键字
  updatedAt: number; // 编辑时间；编辑时须 resetDedup()
}
