/**
 * 智寓 · DM-07~10 四类日志 + LogBundle / LogRecord（FR-06）
 * 依据：design/系统架构设计.md 3.7 节、4.3 节护栏 A。
 *
 * ★ 护栏 A：RuleExecutionLog 仅由 RuleEngine 在真实调用 DeviceService 后生成，
 * 唯一提交入口为 AppDataRepository.commitRuleLogs(report)。
 * 阶段二页面 / 组件 / 初始化代码禁止 new 任何日志对象；MockDataFactory 的
 * logs.ruleExecutions 恒为 []。
 */
import { LogActor, ResultCode, RuleExecStatus, SensorType, EnvSource } from './Enums';
import { EnvironmentData } from './EnvironmentData';
import { AutomationCondition } from './AutomationCondition';

export interface OperationLog {
  id: string;
  timestamp: number;
  actor: LogActor; // USER / RULE / SCENE / SYSTEM
  deviceId: string;
  action: string; // DeviceCommand 或参数键
  before: string; // 变更前参数 JSON 字符串
  after: string; // 变更后参数 JSON 字符串
  result: ResultCode;
  message: string;
}

export interface ActionExecutionDetail {
  actionId: string;
  targetDeviceId: string;
  command: string;
  value: string; // 统一序列化为字符串便于持久化
  result: ResultCode;
  message: string;
}

export interface RuleExecutionLog {
  id: string;
  timestamp: number;
  ruleId: string;
  ruleName: string;
  snapshot: EnvironmentData; // 触发时环境快照，支持事后核查
  matchedConditions: AutomationCondition[]; // 命中的条件
  executedActions: ActionExecutionDetail[]; // 实际执行的动作清单
  skippedActions: ActionExecutionDetail[]; // 被冲突策略跳过的动作清单（Q-10）
  status: RuleExecStatus; // SUCCESS/PARTIAL/FAILED/SKIPPED_*
  errorMsg: string; // 无错误时为空串
  durationMs: number; // 真实耗时
}

export interface EnvironmentLog {
  id: string;
  timestamp: number;
  sensorType: SensorType;
  before: number | boolean;
  after: number | boolean;
  source: EnvSource;
}

export interface SceneSwitchLog {
  id: string;
  timestamp: number;
  fromSceneId: string;
  toSceneId: string;
  appliedCount: number;
  failedCount: number;
}

export interface LogBundle {
  operations: OperationLog[];
  ruleExecutions: RuleExecutionLog[];
  environment: EnvironmentLog[];
  sceneSwitches: SceneSwitchLog[];
}

export type LogRecord = OperationLog | RuleExecutionLog | EnvironmentLog | SceneSwitchLog;
