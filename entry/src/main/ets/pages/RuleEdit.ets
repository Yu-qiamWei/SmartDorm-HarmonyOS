/**
 * 智寓 · 规则创建/编辑（FR-04-01~05 / ST-05 P0-5 补齐）
 *
 * 与旧版的本质差别：旧版 `conditionDrafts/actionDrafts` 只是 `string[]` 展示文本，
 * `buildRule()` 把条件写死成「温度 GT 28℃」、动作写死成「POWER_ON true」，
 * 编辑模式也只回填 name/priority —— 用户根本无法真正编辑条件与动作（FR-04 功能缺口）。
 *
 * 本版：
 *   ① 强类型草稿 `ConditionDraft` / `ActionDraft`（显式字段类型，无 any / Object / 未类型化字面量）；
 *   ② 编辑模式从 found.conditions / found.actions 完整回填，并保留累计统计等只读字段；
 *   ③ 逐条可编辑传感器 / 运算符 / 阈值 / 目标设备 / 命令 / 取值；
 *   ④ 校验直接复用 `common/ParamSchema` 与 `service/ServiceContracts.commandToParamKey`，
 *      **不复制第二份命令映射表**（护栏 B-4），与 `RuleService.validate` 同口径；
 *   ⑤ `buildRule()` 全量由草稿生成，order = 索引，unit 由 sensorType 推导；
 *   ⑥ 所有 ForEach 键值纳入「随编辑必然变化」的字段，杜绝本项目已修过 4 次的索引复用缺陷。
 *
 * 服务层（RuleService / ServiceContracts / ParamSchema / store / model）零改动。
 */
import { AutomationRule } from '../model/AutomationRule';
import { AutomationCondition } from '../model/AutomationCondition';
import { AutomationAction } from '../model/AutomationAction';
import { Device } from '../model/Device';
import { CommandResult } from '../model/CommandResult';
import { ParamValue } from '../model/DeviceParams';
import {
  ConditionLogic, SensorType, Operator, DeviceCommand, ParamKey, ResultCode, ACMode
} from '../model/Enums';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { RouteMap } from '../common/RouteMap';
import { RouteParams } from '../common/RouteParams';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';
import { validateSensorValue, validateParam } from '../common/ParamSchema';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { ServiceFacade } from '../service/ServiceFacade';
import { commandToParamKey } from '../service/ServiceContracts';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { ToastHost } from '../components/common/ToastHost';

/** 条件草稿（字段显式类型，供 @State 数组与 ForEach 使用）。 */
interface ConditionDraft {
  id: string;
  sensorType: SensorType;
  operator: Operator;
  threshold: number;
  unit: string;
}

/** 动作草稿；value 用联合类型承接文本输入、数值与布尔开关。 */
interface ActionDraft {
  id: string;
  targetDeviceId: string;
  command: DeviceCommand;
  value: string | number | boolean;
  order: number;
}

/** 枚举值域（ArkTS 不支持 Object.values 枚举，显式列举）。 */
const SENSOR_TYPES: SensorType[] = [
  SensorType.TEMPERATURE,
  SensorType.HUMIDITY,
  SensorType.ILLUMINANCE,
  SensorType.AIR_QUALITY,
  SensorType.HUMAN_PRESENCE
];

const OPERATORS: Operator[] = [
  Operator.GT,
  Operator.LT,
  Operator.IS_TRUE,
  Operator.IS_FALSE
];

const COMMANDS: DeviceCommand[] = [
  DeviceCommand.POWER_ON,
  DeviceCommand.POWER_OFF,
  DeviceCommand.SET_BRIGHTNESS,
  DeviceCommand.SET_TEMPERATURE,
  DeviceCommand.SET_MODE,
  DeviceCommand.SET_OPEN_PERCENT,
  DeviceCommand.LOCK,
  DeviceCommand.UNLOCK,
  DeviceCommand.SET_FAN_SPEED,
  DeviceCommand.SET_POWER,
  DeviceCommand.SOCKET_ON,
  DeviceCommand.SOCKET_OFF
];

const AC_MODE_VALUES: string[] = [
  ACMode.COOL, ACMode.HEAT, ACMode.FAN, ACMode.DRY, ACMode.AUTO
];

/** 枚举循环取值（支持负向 delta；未命中时从第 0 项起步）。 */
function nextEnum<T>(values: T[], current: T, delta: number): T {
  const size: number = values.length;
  const at: number = values.indexOf(current);
  const safe: number = at < 0 ? 0 : at;
  return values[((safe + delta) % size + size) % size];
}

function unitOf(sensorType: SensorType): string {
  switch (sensorType) {
    case SensorType.TEMPERATURE:
      return '℃';
    case SensorType.HUMIDITY:
      return '%RH';
    case SensorType.ILLUMINANCE:
      return 'Lux';
    case SensorType.AIR_QUALITY:
      return 'AQI';
    default:
      return '';
  }
}

function sensorLabel(sensorType: SensorType): string {
  switch (sensorType) {
    case SensorType.TEMPERATURE:
      return '温度';
    case SensorType.HUMIDITY:
      return '湿度';
    case SensorType.ILLUMINANCE:
      return '光照';
    case SensorType.AIR_QUALITY:
      return '空气质量';
    default:
      return '人体存在';
  }
}

function operatorLabel(operator: Operator): string {
  switch (operator) {
    case Operator.GT:
      return '大于';
    case Operator.LT:
      return '小于';
    case Operator.IS_TRUE:
      return '为真';
    default:
      return '为假';
  }
}

function commandLabel(command: DeviceCommand): string {
  switch (command) {
    case DeviceCommand.POWER_ON:
      return '开启电源';
    case DeviceCommand.POWER_OFF:
      return '关闭电源';
    case DeviceCommand.SET_BRIGHTNESS:
      return '设置亮度';
    case DeviceCommand.SET_TEMPERATURE:
      return '设置温度';
    case DeviceCommand.SET_MODE:
      return '设置空调模式';
    case DeviceCommand.SET_OPEN_PERCENT:
      return '设置窗帘开度';
    case DeviceCommand.LOCK:
      return '上锁';
    case DeviceCommand.UNLOCK:
      return '解锁';
    case DeviceCommand.SET_FAN_SPEED:
      return '设置风速';
    case DeviceCommand.SET_POWER:
      return '设置功率';
    case DeviceCommand.SOCKET_ON:
      return '插座通电';
    default:
      return '插座断电';
  }
}

/** 切换传感器时给一个落在合法量程内的初始阈值（避免立刻 INVALID_PARAM）。 */
function defaultThresholdOf(sensorType: SensorType): number {
  switch (sensorType) {
    case SensorType.TEMPERATURE:
      return 28;
    case SensorType.HUMIDITY:
      return 60;
    case SensorType.ILLUMINANCE:
      return 500;
    case SensorType.AIR_QUALITY:
      return 100;
    default:
      return 0;
  }
}

/**
 * 命令切换后的默认取值。
 *
 * 开关类（commandToParamKey → 'powerOn' / 'locked'）必须是布尔值，
 * 否则 RuleService.validateAction 会以 typeof 判定 INVALID_PARAM（真机缺陷 DEV-01 根因）。
 */
function defaultValueFor(command: DeviceCommand): string | number | boolean {
  switch (command) {
    case DeviceCommand.POWER_OFF:
    case DeviceCommand.SOCKET_OFF:
    case DeviceCommand.UNLOCK:
      return false;
    case DeviceCommand.SET_BRIGHTNESS:
      return 60;
    case DeviceCommand.SET_TEMPERATURE:
      return 26;
    case DeviceCommand.SET_MODE:
      return ACMode.AUTO;
    case DeviceCommand.SET_OPEN_PERCENT:
      return 50;
    case DeviceCommand.SET_FAN_SPEED:
      return 2;
    case DeviceCommand.SET_POWER:
      return 100;
    default:
      return true;
  }
}

/** 与 RuleService.validate 同样的探针口径：布尔型条件/传感器用 true 参与校验。 */
function conditionProbe(draft: ConditionDraft): number | boolean {
  if (draft.sensorType === SensorType.HUMAN_PRESENCE) {
    return true;
  }
  if (draft.operator === Operator.IS_TRUE || draft.operator === Operator.IS_FALSE) {
    return true;
  }
  return draft.threshold;
}

/**
 * 把草稿值按命令对应的 paramKey 转成服务层接受的 ParamValue。
 * 返回 undefined 表示类型不合法（交给 revalidate 显式报 INVALID_PARAM，不静默兜底）。
 */
function actionParamValue(draft: ActionDraft, paramKey: string): ParamValue | undefined {
  const raw: string | number | boolean = draft.value;
  if (paramKey === 'powerOn' || paramKey === 'locked') {
    if (typeof raw === 'boolean') {
      return raw;
    }
    if (raw === 'true') {
      return true;
    }
    if (raw === 'false') {
      return false;
    }
    return undefined;
  }
  if (paramKey === 'mode') {
    if (raw === ACMode.COOL) {
      return ACMode.COOL;
    }
    if (raw === ACMode.HEAT) {
      return ACMode.HEAT;
    }
    if (raw === ACMode.FAN) {
      return ACMode.FAN;
    }
    if (raw === ACMode.DRY) {
      return ACMode.DRY;
    }
    if (raw === ACMode.AUTO) {
      return ACMode.AUTO;
    }
    return undefined;
  }
  if (typeof raw === 'number') {
    return raw;
  }
  if (typeof raw === 'boolean') {
    return undefined;
  }
  const parsed: number = Number(raw);
  return Number.isNaN(parsed) ? undefined : parsed;
}

function validateCondition(draft: ConditionDraft): ResultCode {
  return validateSensorValue(draft.sensorType, conditionProbe(draft));
}

/** 动作校验：目标设备存在 + 命令有映射 + 值类型/范围（含设备类型适用性）。 */
function validateAction(draft: ActionDraft): ResultCode {
  const device: Device | undefined =
    AppDataRepository.getInstance().findDevice(draft.targetDeviceId);
  if (device === undefined) {
    return ResultCode.INVALID_PARAM;
  }
  const paramKey: string = commandToParamKey(draft.command);
  if (paramKey.length === 0) {
    return ResultCode.INVALID_PARAM;
  }
  const value: ParamValue | undefined = actionParamValue(draft, paramKey);
  if (value === undefined) {
    return ResultCode.INVALID_PARAM;
  }
  if (paramKey === 'powerOn') {
    return typeof value === 'boolean' ? ResultCode.OK : ResultCode.INVALID_PARAM;
  }
  return validateParam(device.type, paramKey as ParamKey, value);
}

function conditionText(draft: ConditionDraft): string {
  return sensorLabel(draft.sensorType) + ' ' + operatorLabel(draft.operator) + ' ' +
    String(draft.threshold) + draft.unit;
}

function deviceNameOf(deviceId: string): string {
  const device: Device | undefined = AppDataRepository.getInstance().findDevice(deviceId);
  return device === undefined ? '设备不存在' : device.name;
}

function actionText(draft: ActionDraft): string {
  return '目标 ' + deviceNameOf(draft.targetDeviceId) + ' · ' + commandLabel(draft.command) +
    ' · 取值 ' + String(draft.value);
}

function defaultCondition(): ConditionDraft {
  const draft: ConditionDraft = {
    id: IdGenerator.condition(),
    sensorType: SensorType.TEMPERATURE,
    operator: Operator.GT,
    threshold: 28,
    unit: unitOf(SensorType.TEMPERATURE)
  };
  return draft;
}

function defaultAction(deviceId: string): ActionDraft {
  const draft: ActionDraft = {
    id: IdGenerator.action(),
    targetDeviceId: deviceId,
    command: DeviceCommand.POWER_ON,
    value: true,
    order: 0
  };
  return draft;
}

@Entry
@Component
struct RuleEdit {
  @State mode: string = 'create';
  @State ruleName: string = '';
  @State priority: number = 1;
  @State conditionDrafts: ConditionDraft[] = [defaultCondition()];
  @State actionDrafts: ActionDraft[] = [defaultAction('')];
  @State validationNote: string = '参数校验：待输入';
  @State saveNote: string = '尚未提交';

  private ruleId: string = '';
  private validationOk: boolean = false;
  /** 编辑模式要保留的只读字段（RuleService.update 也会保留，这里保证草稿不凭空重置）。 */
  private originalEnabled: boolean = true;
  private originalLogic: ConditionLogic = ConditionLogic.AND;
  private originalCreatedAt: number = 0;
  private originalLastTriggeredAt: number = 0;
  private originalExecutionCount: number = 0;
  private originalLastSatisfied: boolean = false;
  private unsubscribe: Unsubscribe | undefined = undefined;
  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    // 页面仅订阅，编辑草稿属于页面局部 @State，不被内存态覆盖（SK-01/02）。
  };

  /**
   * 文本框「未提交文本」暂存区（按草稿 id 索引）。
   *
   * ★ ST-05 阶段 B 的 D-1 / D-2 同源根因：ForEach 键值纳入 threshold / value，
   *   若 `onChange` 每次击键都改 @State，ForEach 立刻判定键值变化、销毁并重建整行：
   *   ① 一次性输入 "80" 只有第一个字符落到旧 TextInput（吞字符）；
   *   ② 点「移除」时 TextInput 失焦触发 onChange → 整行重建 → 正在被点击的
   *      Button 被卸载，onClick 丢失（只剩 1 条动作时移除无效）。
   * 因此输入期间**绝不**改 @State：文本只进暂存区，等 IME 提交（onSubmit）、
   * 按钮离散编辑或保存时再一次性提交；键值只在编辑结束后变化一次。
   */
  private pendingConditionText: Map<string, string> = new Map<string, string>();
  private pendingActionText: Map<string, string> = new Map<string, string>();

  private rememberConditionText(id: string, text: string): void {
    this.pendingConditionText.set(id, text);
  }

  private rememberActionText(id: string, text: string): void {
    this.pendingActionText.set(id, text);
  }

  /** 提交单个草稿的暂存文本（IME 回车时调用）。 */
  private flushConditionText(id: string): void {
    const text: string | undefined = this.pendingConditionText.get(id);
    if (text === undefined) {
      return;
    }
    this.pendingConditionText.delete(id);
    for (let i = 0; i < this.conditionDrafts.length; i++) {
      if (this.conditionDrafts[i].id === id) {
        this.setConditionThreshold(i, text);
        return;
      }
    }
  }

  private flushActionText(id: string): void {
    const text: string | undefined = this.pendingActionText.get(id);
    if (text === undefined) {
      return;
    }
    this.pendingActionText.delete(id);
    for (let i = 0; i < this.actionDrafts.length; i++) {
      if (this.actionDrafts[i].id === id) {
        this.setActionValue(i, text);
        return;
      }
    }
  }

  /** 全部暂存文本落进草稿（保存前 / 任何离散按钮编辑前调用）。 */
  private flushAllPending(): void {
    for (let i = 0; i < this.conditionDrafts.length; i++) {
      const id: string = this.conditionDrafts[i].id;
      if (this.pendingConditionText.has(id)) {
        this.flushConditionText(id);
      }
    }
    for (let i = 0; i < this.actionDrafts.length; i++) {
      const id: string = this.actionDrafts[i].id;
      if (this.pendingActionText.has(id)) {
        this.flushActionText(id);
      }
    }
  }

  aboutToAppear(): void {
    this.mode = RouteParams.mode();
    this.ruleId = RouteParams.ruleId();
    this.unsubscribe = AppDataRepository.getInstance().subscribe(this.onStateChange);
    if (this.mode === 'edit') {
      this.backfill(this.ruleId);
    }
    this.initializeTargets();
    this.revalidate();
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== undefined) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  /** 编辑模式：条件/动作逐字段完整回填，避免旧版「只回填 name/priority」的数据丢失。 */
  private backfill(id: string): void {
    const found: AutomationRule | undefined = AppDataRepository.getInstance().findRule(id);
    if (found === undefined) {
      return;
    }
    this.ruleName = found.name;
    this.priority = found.priority;
    this.originalEnabled = found.enabled;
    this.originalLogic = found.logic;
    this.originalCreatedAt = found.createdAt;
    this.originalLastTriggeredAt = found.lastTriggeredAt;
    this.originalExecutionCount = found.executionCount;
    this.originalLastSatisfied = found.lastSatisfied;

    const conditions: ConditionDraft[] = [];
    for (let i = 0; i < found.conditions.length; i++) {
      const c: AutomationCondition = found.conditions[i];
      const draft: ConditionDraft = {
        id: c.id,
        sensorType: c.sensorType,
        operator: c.operator,
        threshold: c.threshold,
        unit: c.unit.length > 0 ? c.unit : unitOf(c.sensorType)
      };
      conditions.push(draft);
    }
    if (conditions.length > 0) {
      this.conditionDrafts = conditions;
    }

    const actions: ActionDraft[] = [];
    for (let i = 0; i < found.actions.length; i++) {
      const a: AutomationAction = found.actions[i];
      const rawValue: string | number | boolean =
        typeof a.value === 'string' ? String(a.value) : a.value;
      const draft: ActionDraft = {
        id: a.id,
        targetDeviceId: a.targetDeviceId,
        command: a.command,
        value: rawValue,
        order: a.order
      };
      actions.push(draft);
    }
    if (actions.length > 0) {
      this.actionDrafts = actions;
    }
  }

  /** 新建动作的默认目标为空；首次进入时绑定到真实存在的设备，避免保存被 NOT_FOUND 拒绝。 */
  private initializeTargets(): void {
    const devices: Device[] = AppDataRepository.getInstance().listDevices();
    const fallback: string = devices.length > 0 ? devices[0].id : '';
    const next: ActionDraft[] = this.actionDrafts.slice();
    let changed: boolean = false;
    for (let i = 0; i < next.length; i++) {
      const d: ActionDraft = next[i];
      const found: Device | undefined =
        AppDataRepository.getInstance().findDevice(d.targetDeviceId);
      if (found === undefined) {
        const replaced: ActionDraft = {
          id: d.id,
          targetDeviceId: fallback,
          command: d.command,
          value: d.value,
          order: d.order
        };
        next[i] = replaced;
        changed = true;
      }
    }
    if (changed) {
      this.actionDrafts = next;
    }
  }

  /** 逐条校验全部条件与动作，结果直接写进 validationNote（用户可见，不静默）。 */
  private revalidate(): void {
    let ok: boolean = true;
    let note: string = '';
    if (this.conditionDrafts.length === 0) {
      ok = false;
      note = '参数校验：至少需要 1 条条件（INVALID_PARAM）';
    } else {
      for (let i = 0; i < this.conditionDrafts.length; i++) {
        if (validateCondition(this.conditionDrafts[i]) !== ResultCode.OK) {
          ok = false;
          note = '参数校验：第 ' + (i + 1) + ' 条条件越界（INVALID_PARAM）';
          break;
        }
      }
      if (ok) {
        note = '参数校验：' + this.conditionDrafts.length + ' 条条件全部合法';
      }
    }
    if (ok) {
      if (this.actionDrafts.length === 0) {
        ok = false;
        note = '参数校验：至少需要 1 条动作（INVALID_PARAM）';
      } else {
        for (let i = 0; i < this.actionDrafts.length; i++) {
          if (validateAction(this.actionDrafts[i]) !== ResultCode.OK) {
            ok = false;
            note = '参数校验：第 ' + (i + 1) + ' 条动作不合法（INVALID_PARAM）';
            break;
          }
        }
        if (ok) {
          note = note + ' · ' + this.actionDrafts.length + ' 条动作全部合法';
        }
      }
    }
    this.validationOk = ok;
    this.validationNote = note;
  }

  private replaceCondition(index: number, draft: ConditionDraft): void {
    if (index < 0 || index >= this.conditionDrafts.length) {
      return;
    }
    const next: ConditionDraft[] = this.conditionDrafts.slice();
    next[index] = draft;
    this.conditionDrafts = next;
    this.revalidate();
  }

  private replaceAction(index: number, draft: ActionDraft): void {
    if (index < 0 || index >= this.actionDrafts.length) {
      return;
    }
    const next: ActionDraft[] = this.actionDrafts.slice();
    next[index] = draft;
    this.actionDrafts = next;
    this.revalidate();
  }

  private cycleConditionSensor(index: number): void {
    this.flushAllPending();
    const d: ConditionDraft = this.conditionDrafts[index];
    const sensorType: SensorType = nextEnum(SENSOR_TYPES, d.sensorType, 1);
    let operator: Operator = d.operator;
    if (sensorType === SensorType.HUMAN_PRESENCE) {
      operator = Operator.IS_TRUE;
    } else if (operator === Operator.IS_TRUE || operator === Operator.IS_FALSE) {
      operator = Operator.GT;
    }
    const next: ConditionDraft = {
      id: d.id,
      sensorType: sensorType,
      operator: operator,
      threshold: defaultThresholdOf(sensorType),
      unit: unitOf(sensorType)
    };
    this.replaceCondition(index, next);
  }

  private cycleConditionOperator(index: number): void {
    this.flushAllPending();
    const d: ConditionDraft = this.conditionDrafts[index];
    const next: ConditionDraft = {
      id: d.id,
      sensorType: d.sensorType,
      operator: nextEnum(OPERATORS, d.operator, 1),
      threshold: d.threshold,
      unit: d.unit
    };
    this.replaceCondition(index, next);
  }

  private adjustConditionThreshold(index: number, delta: number): void {
    this.flushAllPending();
    const d: ConditionDraft = this.conditionDrafts[index];
    const next: ConditionDraft = {
      id: d.id,
      sensorType: d.sensorType,
      operator: d.operator,
      threshold: d.threshold + delta,
      unit: d.unit
    };
    this.replaceCondition(index, next);
  }

  private setConditionThreshold(index: number, text: string): void {
    if (index < 0 || index >= this.conditionDrafts.length) {
      return;
    }
    const d: ConditionDraft = this.conditionDrafts[index];
    const parsed: number = Number(text);
    const next: ConditionDraft = {
      id: d.id,
      sensorType: d.sensorType,
      operator: d.operator,
      threshold: Number.isNaN(parsed) ? d.threshold : parsed,
      unit: d.unit
    };
    this.replaceCondition(index, next);
  }

  private cycleActionDevice(index: number): void {
    this.flushAllPending();
    const d: ActionDraft = this.actionDrafts[index];
    const devices: Device[] = AppDataRepository.getInstance().listDevices();
    if (devices.length === 0) {
      ToastHost.showMessage('没有可用设备');
      return;
    }
    const ids: string[] = [];
    for (let i = 0; i < devices.length; i++) {
      ids.push(devices[i].id);
    }
    const next: ActionDraft = {
      id: d.id,
      targetDeviceId: nextEnum(ids, d.targetDeviceId, 1),
      command: d.command,
      value: d.value,
      order: d.order
    };
    this.replaceAction(index, next);
  }

  private cycleActionCommand(index: number): void {
    this.flushAllPending();
    const d: ActionDraft = this.actionDrafts[index];
    const command: DeviceCommand = nextEnum(COMMANDS, d.command, 1);
    const next: ActionDraft = {
      id: d.id,
      targetDeviceId: d.targetDeviceId,
      command: command,
      value: defaultValueFor(command),
      order: d.order
    };
    this.replaceAction(index, next);
  }

  private adjustActionValue(index: number, delta: number): void {
    this.flushAllPending();
    const d: ActionDraft = this.actionDrafts[index];
    const paramKey: string = commandToParamKey(d.command);
    let value: string | number | boolean = d.value;
    if (paramKey === 'powerOn' || paramKey === 'locked') {
      const current: boolean = d.value === true || d.value === 'true';
      value = !current;
    } else if (paramKey === 'mode') {
      value = nextEnum(AC_MODE_VALUES, String(d.value), delta);
    } else if (typeof d.value === 'number') {
      value = d.value + delta;
    } else {
      const parsed: number = Number(String(d.value));
      value = Number.isNaN(parsed) ? 0 : parsed + delta;
    }
    const next: ActionDraft = {
      id: d.id,
      targetDeviceId: d.targetDeviceId,
      command: d.command,
      value: value,
      order: d.order
    };
    this.replaceAction(index, next);
  }

  private setActionValue(index: number, text: string): void {
    if (index < 0 || index >= this.actionDrafts.length) {
      return;
    }
    const d: ActionDraft = this.actionDrafts[index];
    const next: ActionDraft = {
      id: d.id,
      targetDeviceId: d.targetDeviceId,
      command: d.command,
      value: text,
      order: d.order
    };
    this.replaceAction(index, next);
  }

  private firstDeviceId(): string {
    const devices: Device[] = AppDataRepository.getInstance().listDevices();
    return devices.length > 0 ? devices[0].id : '';
  }

  /** 草稿 → AutomationRule：条件/动作全量由草稿生成，order = 索引，unit 由 sensorType 推导。 */
  private buildRule(): AutomationRule {
    const now: number = TimeUtil.now();
    const conditions: AutomationCondition[] = [];
    for (let i = 0; i < this.conditionDrafts.length; i++) {
      const d: ConditionDraft = this.conditionDrafts[i];
      const condition: AutomationCondition = {
        id: d.id.length > 0 ? d.id : IdGenerator.condition(),
        sensorType: d.sensorType,
        operator: d.operator,
        threshold: d.threshold,
        unit: unitOf(d.sensorType)
      };
      conditions.push(condition);
    }
    const actions: AutomationAction[] = [];
    for (let i = 0; i < this.actionDrafts.length; i++) {
      const d: ActionDraft = this.actionDrafts[i];
      const paramKey: string = commandToParamKey(d.command);
      const converted: ParamValue | undefined = actionParamValue(d, paramKey);
      const value: ParamValue = converted === undefined ? true : converted;
      const action: AutomationAction = {
        id: d.id.length > 0 ? d.id : IdGenerator.action(),
        targetDeviceId: d.targetDeviceId,
        command: d.command,
        value: value,
        order: i
      };
      actions.push(action);
    }
    const editing: boolean = this.mode === 'edit' && this.ruleId.length > 0;
    const rule: AutomationRule = {
      id: editing ? this.ruleId : IdGenerator.rule(),
      name: this.ruleName,
      enabled: editing ? this.originalEnabled : true,
      logic: editing ? this.originalLogic : ConditionLogic.AND,
      conditions: conditions,
      actions: actions,
      priority: this.priority,
      // 编辑模式保留累计统计与边沿标记；RuleService.update 会按 FR-04-09 强制复位
      // lastSatisfied，这里保持数据完整、不凭空清零。
      lastSatisfied: editing ? this.originalLastSatisfied : false,
      lastTriggeredAt: editing ? this.originalLastTriggeredAt : 0,
      executionCount: editing ? this.originalExecutionCount : 0,
      createdAt: editing ? this.originalCreatedAt : now,
      updatedAt: now
    };
    return rule;
  }

  private save(): void {
    this.flushAllPending();
    this.revalidate();
    if (!this.validationOk) {
      ToastHost.showMessage(this.validationNote);
      this.saveNote = this.validationNote;
      return;
    }
    const rule: AutomationRule = this.buildRule();
    const facade: ServiceFacade = ServiceFacade.getInstance();
    const task: Promise<CommandResult<AutomationRule>> = this.mode === 'edit'
      ? facade.updateRule(rule)
      : facade.createRule(rule);
    task.then((result: CommandResult<AutomationRule>): void => {
      ToastHost.showResult<AutomationRule>(result);
      if (result.changed) {
        RouteMap.back();
      } else {
        // 失败 / 幂等未变更必须回显真实原因，不写死「占位未实现」（DEV-02）。
        this.saveNote = result.message;
      }
    });
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: this.mode === 'edit' ? '编辑规则' : '新建规则',
          subtitle: '条件 AND 组合 · 动作按 order 升序执行',
          showBack: true,
          actionLabel: '首页'
        })

        SectionCard({ title: '基本信息', caption: this.validationNote }) {
          TextInput({ placeholder: '请输入规则名称', text: this.ruleName })
            .fontSize(ThemeTokens.FONT_BODY)
            .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .onChange((text: string): void => {
              this.ruleName = text;
            })
          Row() {
            Button('优先级 −')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.priority = Math.max(0, this.priority - 1);
              })
            Text('优先级 ' + this.priority)
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Button('优先级 +')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.priority = this.priority + 1;
              })
          }
          .width('100%')
          .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
        }

        SectionCard({
          title: '触发条件（AND）',
          caption: '共 ' + this.conditionDrafts.length + ' 条 · 逐条可编辑'
        }) {
          ForEach(this.conditionDrafts, (draft: ConditionDraft, index: number): void => {
            Column() {
              Text('条件 ' + (index + 1) + '：' + conditionText(draft))
                .fontSize(ThemeTokens.FONT_BODY)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .width('100%')
              Row() {
                Button('传感器：' + sensorLabel(draft.sensorType))
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.PRIMARY)
                  .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.cycleConditionSensor(index);
                  })
                Button('运算符：' + operatorLabel(draft.operator))
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.PRIMARY)
                  .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
                  .onClick(() => {
                    this.cycleConditionOperator(index);
                  })
              }
              .width('100%')
              .margin({ top: 4 })
              Row() {
                Button('阈值 −1')
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.PRIMARY)
                  .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.adjustConditionThreshold(index, -1);
                  })
                Button('阈值 +1')
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.PRIMARY)
                  .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
                  .onClick(() => {
                    this.adjustConditionThreshold(index, 1);
                  })
                Button('移除')
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.STATUS_FAULT)
                  .backgroundColor(ThemeTokens.WARNING_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
                  .onClick(() => {
                    const next: ConditionDraft[] = this.conditionDrafts.slice();
                    const removed: ConditionDraft | undefined = next[index];
                    if (removed === undefined) {
                      return;
                    }
                    next.splice(index, 1);
                    this.conditionDrafts = next;
                    this.pendingConditionText.delete(removed.id);
                    this.revalidate();
                  })
              }
              .width('100%')
              .margin({ top: 4 })
              TextInput({ placeholder: '阈值（数值，回车或保存生效）', text: String(draft.threshold) })
                .fontSize(ThemeTokens.FONT_BODY)
                .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .onChange((text: string): void => {
                  this.rememberConditionText(draft.id, text);
                })
                .onSubmit((): void => {
                  this.flushConditionText(draft.id);
                })
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
          }, (draft: ConditionDraft, index: number): string =>
            draft.id + ':' + draft.sensorType + ':' + draft.operator + ':' + String(draft.threshold))
          Button('添加条件')
            .fontSize(ThemeTokens.FONT_BODY)
            .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
            .onClick(() => {
              this.flushAllPending();
              const next: ConditionDraft[] = this.conditionDrafts.slice();
              next.push(defaultCondition());
              this.conditionDrafts = next;
              this.revalidate();
            })
        }

        SectionCard({
          title: '执行动作（有序）',
          caption: '逐条可编辑目标设备 / 命令 / 取值 · 按 order 升序执行'
        }) {
          ForEach(this.actionDrafts, (draft: ActionDraft, index: number): void => {
            Column() {
              Text('动作 ' + (index + 1) + '：' + actionText(draft))
                .fontSize(ThemeTokens.FONT_BODY)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .width('100%')
              Row() {
                Button('目标设备：' + deviceNameOf(draft.targetDeviceId))
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.PRIMARY)
                  .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.cycleActionDevice(index);
                  })
                Button('命令：' + commandLabel(draft.command))
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.PRIMARY)
                  .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
                  .onClick(() => {
                    this.cycleActionCommand(index);
                  })
              }
              .width('100%')
              .margin({ top: 4 })
              Row() {
                Button('取值 −1')
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.PRIMARY)
                  .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.adjustActionValue(index, -1);
                  })
                Button('取值 +1')
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.PRIMARY)
                  .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
                  .onClick(() => {
                    this.adjustActionValue(index, 1);
                  })
                Button('移除')
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.STATUS_FAULT)
                  .backgroundColor(ThemeTokens.WARNING_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .layoutWeight(1)
                  .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
                  .onClick(() => {
                    const next: ActionDraft[] = this.actionDrafts.slice();
                    const removed: ActionDraft | undefined = next[index];
                    if (removed === undefined) {
                      return;
                    }
                    next.splice(index, 1);
                    this.actionDrafts = next;
                    this.pendingActionText.delete(removed.id);
                    this.revalidate();
                  })
              }
              .width('100%')
              .margin({ top: 4 })
              TextInput({ placeholder: '取值（数值 / true / false / 模式，回车或保存生效）', text: String(draft.value) })
                .fontSize(ThemeTokens.FONT_BODY)
                .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .onChange((text: string): void => {
                  this.rememberActionText(draft.id, text);
                })
                .onSubmit((): void => {
                  this.flushActionText(draft.id);
                })
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
          }, (draft: ActionDraft, index: number): string =>
            draft.id + ':' + draft.targetDeviceId + ':' + draft.command + ':' + String(draft.value))
          Row() {
            Button('添加动作')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.PRIMARY)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.flushAllPending();
                const next: ActionDraft[] = this.actionDrafts.slice();
                next.push(defaultAction(this.firstDeviceId()));
                this.actionDrafts = next;
                this.revalidate();
              })
            Button('全部绑定首台设备')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                this.flushAllPending();
                const target: string = this.firstDeviceId();
                const next: ActionDraft[] = [];
                for (let i = 0; i < this.actionDrafts.length; i++) {
                  const d: ActionDraft = this.actionDrafts[i];
                  const replaced: ActionDraft = {
                    id: d.id,
                    targetDeviceId: target,
                    command: d.command,
                    value: d.value,
                    order: d.order
                  };
                  next.push(replaced);
                }
                this.actionDrafts = next;
                this.revalidate();
              })
          }
          .width('100%')
          .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
        }

        SectionCard({ title: '提交', caption: this.saveNote }) {
          Row() {
            Button('保存规则')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.ACCENT)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.save();
              })
            Button('取消返回')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                RouteMap.back();
              })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({
        left: ThemeTokens.SPACE_PAGE_X,
        right: ThemeTokens.SPACE_PAGE_X,
        bottom: ThemeTokens.SPACE_SECTION_GAP
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
  }
}
