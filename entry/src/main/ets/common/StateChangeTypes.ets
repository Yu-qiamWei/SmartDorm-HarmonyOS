/**
 * 智寓 · 跨层回调与筛选类型（设计 4.1 支撑类型 / 8.3 订阅防泄漏）
 *
 * 本项目主状态订阅不依赖系统 emitter，由 AppDataRepository 自维护回调表
 * （Map<string, StateChangeHandler>），可在 Node 侧单测、可控注销（SK-06）。
 */
import { LogType } from '../model/Enums';

/** 一次状态变更的描述（页面据此刷新只读渲染快照）。 */
export interface ChangeSet {
  reason: string;
  timestamp: number;
  affectedPartitions: string[];
}

/** 订阅处理函数；页面 aboutToDisappear 必须调用返回的 Unsubscribe（SK-01/02）。 */
export type StateChangeHandler = (change: ChangeSet) => void;

/** 取消订阅函数类型。 */
export type Unsubscribe = () => void;

/** MI-13 日志查询筛选条件（FR-06-04）。 */
export interface LogFilter {
  from?: number;
  to?: number;
  types?: LogType[];
  deviceId?: string;
  ruleId?: string;
}
