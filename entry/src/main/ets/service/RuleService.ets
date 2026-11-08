/**
 * 智寓 · 规则服务（MI-11 / FR-04-09/10）
 *
 * 职责：规则 CRUD 与启停的**唯一入口**，并保证「编辑后边沿重新武装」：
 *   - `create`：校验通过后生成 id、把 `lastSatisfied` 置 false 再入库；
 *   - `update`：`updatedAt = now`、`lastSatisfied = false`（FR-04-09）；
 *   - `toggle`：`lastSatisfied = false`（停用→启用后必须能再次触发）；
 *   - `remove`：预置规则允许删除（规则与预置场景不同，预置场景才不可删）；
 *   - `resetAllDedup`：总开关切换时统一清标记（FR-04-10 配套）。
 *
 * ★ 写入只经 `IStateWriter.commitRules()`（设计 4.2），本类不直接改 `state`。
 * ★ 不写 `OperationLog`：`OperationLog` 以 `deviceId` 为主键，规则 CRUD 没有对应设备；
 *   规则变更的可追溯性由 `updatedAt` 与后续执行日志承担，不伪造设备日志。
 * ★ 校验只复用 `ParamSchema` 的既有纯函数，不在此处另写一份范围表（4.8 同理）。
 *
 * 依据：design/系统架构设计.md 4.1 MI-11、4.2，PRD FR-04-01~05、FR-04-09/10。
 */
import { IRuleService, commandToParamKey } from './ServiceContracts';
import { AppDataRepository } from '../store/AppDataRepository';
import { AutomationRule } from '../model/AutomationRule';
import { AutomationCondition } from '../model/AutomationCondition';
import { AutomationAction } from '../model/AutomationAction';
import { Device } from '../model/Device';
import { CommandResult, okResult, noChangeResult, failResult } from '../model/CommandResult';
import { Operator, ParamKey, ResultCode } from '../model/Enums';
import { validateParam, validateSensorValue } from '../common/ParamSchema';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';

/** 校验结论（带可读原因，供 UI 直接展示，不做静默失败）。 */
interface RuleCheck {
  code: ResultCode;
  detail: string;
}

export class RuleService implements IRuleService {
  private static instance: RuleService = new RuleService();

  static getInstance(): RuleService {
    return RuleService.instance;
  }

  private constructor() {
  }

  /** MI-11 创建规则：校验 → 补 id → 去重标记清零 → 提交。 */
  async create(rule: AutomationRule): Promise<CommandResult<AutomationRule>> {
    const check: RuleCheck = RuleService.validate(rule);
    if (check.code !== ResultCode.OK) {
      return failResult<AutomationRule>(check.code, check.detail);
    }
    const now: number = TimeUtil.now();
    const created: AutomationRule = {
      id: rule.id.length > 0 ? rule.id : IdGenerator.rule(),
      name: rule.name.trim(),
      enabled: rule.enabled,
      logic: rule.logic,
      conditions: RuleService.normalizeConditions(rule.conditions),
      actions: RuleService.normalizeActions(rule.actions),
      priority: rule.priority,
      lastSatisfied: false,
      lastTriggeredAt: 0,
      executionCount: 0,
      createdAt: now,
      updatedAt: now
    };
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const rules: AutomationRule[] = repo.getState().rules.slice();
    rules.push(created);
    repo.commitRules(rules, 'rule-create');
    return okResult<AutomationRule>(created, '规则「' + created.name + '」已创建');
  }

  /** MI-11 更新规则：保留累计执行统计，`lastSatisfied` 强制复位（边沿重新武装）。 */
  async update(rule: AutomationRule): Promise<CommandResult<AutomationRule>> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const existing: AutomationRule | undefined = repo.findRule(rule.id);
    if (existing === undefined) {
      return failResult<AutomationRule>(ResultCode.NOT_FOUND, '规则不存在：' + rule.id);
    }
    const check: RuleCheck = RuleService.validate(rule);
    if (check.code !== ResultCode.OK) {
      return failResult<AutomationRule>(check.code, check.detail);
    }
    const now: number = TimeUtil.now();
    const updated: AutomationRule = {
      id: existing.id,
      name: rule.name.trim(),
      enabled: rule.enabled,
      logic: rule.logic,
      conditions: RuleService.normalizeConditions(rule.conditions),
      actions: RuleService.normalizeActions(rule.actions),
      priority: rule.priority,
      lastSatisfied: false,
      lastTriggeredAt: existing.lastTriggeredAt,
      executionCount: existing.executionCount,
      createdAt: existing.createdAt,
      updatedAt: now
    };
    repo.commitRules(RuleService.replaced(repo.getState().rules, updated), 'rule-update');
    return okResult<AutomationRule>(updated, '规则「' + updated.name + '」已保存');
  }

  /** MI-11 删除规则。 */
  async remove(id: string): Promise<CommandResult<void>> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const existing: AutomationRule | undefined = repo.findRule(id);
    if (existing === undefined) {
      return failResult<void>(ResultCode.NOT_FOUND, '规则不存在：' + id);
    }
    const kept: AutomationRule[] = [];
    const rules: AutomationRule[] = repo.getState().rules;
    for (let i = 0; i < rules.length; i++) {
      if (rules[i].id !== id) {
        kept.push(rules[i]);
      }
    }
    repo.commitRules(kept, 'rule-remove');
    return okResult<void>(undefined, '规则「' + existing.name + '」已删除');
  }

  /** MI-11 启停规则：启停即改变判定上下文，必须复位去重标记。 */
  async toggle(id: string, enabled: boolean): Promise<CommandResult<AutomationRule>> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const existing: AutomationRule | undefined = repo.findRule(id);
    if (existing === undefined) {
      return failResult<AutomationRule>(ResultCode.NOT_FOUND, '规则不存在：' + id);
    }
    if (existing.enabled === enabled) {
      return noChangeResult<AutomationRule>(
        existing, '规则已处于' + (enabled ? '启用' : '停用') + '状态'
      );
    }
    const toggled: AutomationRule = {
      id: existing.id,
      name: existing.name,
      enabled: enabled,
      logic: existing.logic,
      conditions: existing.conditions.slice(),
      actions: existing.actions.slice(),
      priority: existing.priority,
      lastSatisfied: false,
      lastTriggeredAt: existing.lastTriggeredAt,
      executionCount: existing.executionCount,
      createdAt: existing.createdAt,
      updatedAt: TimeUtil.now()
    };
    repo.commitRules(RuleService.replaced(repo.getState().rules, toggled), 'rule-toggle');
    return okResult<AutomationRule>(toggled, '规则已' + (enabled ? '启用' : '停用'));
  }

  /**
   * 总开关切换时统一复位全部规则的去重标记（FR-04-10 配套）。
   * 关闭期间不产生求值，若不复位，重新开启后的第一轮可能被旧的 `lastSatisfied` 拦掉。
   */
  resetAllDedup(): void {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const rules: AutomationRule[] = repo.getState().rules;
    let changed: boolean = false;
    const next: AutomationRule[] = [];
    for (let i = 0; i < rules.length; i++) {
      const rule: AutomationRule = rules[i];
      if (!rule.lastSatisfied) {
        next.push(rule);
        continue;
      }
      changed = true;
      const reset: AutomationRule = {
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
      next.push(reset);
    }
    if (changed) {
      repo.commitRules(next, 'rule-reset-dedup');
    }
  }

  // ——————————————————————————————————————————————————————
  // 内部：校验与规范化
  // ——————————————————————————————————————————————————————

  /** 规则合法性：名称 / 条件 / 动作 / 条件取值 / 动作目标设备与参数值。 */
  private static validate(rule: AutomationRule): RuleCheck {
    if (rule.name.trim().length === 0) {
      return RuleService.reject('规则名称不可为空');
    }
    if (rule.conditions.length === 0) {
      return RuleService.reject('规则至少需要 1 个条件');
    }
    if (rule.actions.length === 0) {
      return RuleService.reject('规则至少需要 1 个动作');
    }
    for (let i = 0; i < rule.conditions.length; i++) {
      const condition: AutomationCondition = rule.conditions[i];
      const probe: number | boolean =
        condition.operator === Operator.GT || condition.operator === Operator.LT
          ? condition.threshold
          : true;
      if (validateSensorValue(condition.sensorType, probe) !== ResultCode.OK) {
        return RuleService.reject(
          '条件阈值超出 ' + condition.sensorType + ' 的量程：' + condition.threshold
        );
      }
    }
    for (let i = 0; i < rule.actions.length; i++) {
      const action: AutomationAction = rule.actions[i];
      const device: Device | undefined =
        AppDataRepository.getInstance().findDevice(action.targetDeviceId);
      if (device === undefined) {
        return RuleService.reject('动作目标设备不存在：' + action.targetDeviceId);
      }
      const paramKey: string = commandToParamKey(action.command);
      if (paramKey.length === 0) {
        return RuleService.reject('未支持的设备命令：' + action.command);
      }
      if (paramKey === 'powerOn') {
        if (typeof action.value !== 'boolean') {
          return RuleService.reject('开关类命令的取值必须是布尔值');
        }
        continue;
      }
      const code: ResultCode = validateParam(device.type, paramKey as ParamKey, action.value);
      if (code !== ResultCode.OK) {
        return RuleService.reject(
          '动作参数不适用于 ' + device.name + '：' + paramKey + '=' + String(action.value)
        );
      }
    }
    return RuleService.accept();
  }

  private static accept(): RuleCheck {
    const check: RuleCheck = { code: ResultCode.OK, detail: '' };
    return check;
  }

  private static reject(detail: string): RuleCheck {
    const check: RuleCheck = { code: ResultCode.INVALID_PARAM, detail: detail };
    return check;
  }

  /** 条件规范化：补齐缺失 id（UI 新建条件时可能未生成）。 */
  private static normalizeConditions(list: AutomationCondition[]): AutomationCondition[] {
    const result: AutomationCondition[] = [];
    for (let i = 0; i < list.length; i++) {
      const item: AutomationCondition = list[i];
      const next: AutomationCondition = {
        id: item.id.length > 0 ? item.id : IdGenerator.condition(),
        sensorType: item.sensorType,
        operator: item.operator,
        threshold: item.threshold,
        unit: item.unit
      };
      result.push(next);
    }
    return result;
  }

  /** 动作规范化：补齐缺失 id。 */
  private static normalizeActions(list: AutomationAction[]): AutomationAction[] {
    const result: AutomationAction[] = [];
    for (let i = 0; i < list.length; i++) {
      const item: AutomationAction = list[i];
      const next: AutomationAction = {
        id: item.id.length > 0 ? item.id : IdGenerator.action(),
        targetDeviceId: item.targetDeviceId,
        command: item.command,
        value: item.value,
        order: item.order
      };
      result.push(next);
    }
    return result;
  }

  /** 用新规则对象整体替换同 id 元素，返回新数组（不改入参数组）。 */
  private static replaced(rules: AutomationRule[], next: AutomationRule): AutomationRule[] {
    const result: AutomationRule[] = [];
    for (let i = 0; i < rules.length; i++) {
      result.push(rules[i].id === next.id ? next : rules[i]);
    }
    return result;
  }
}
