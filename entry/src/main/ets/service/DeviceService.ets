/**
 * 智寓 · 设备服务（MI-02~05 / FR-02 / Q-15）
 *
 * 四步前置校验链（顺序**锁死**，任一不通过即返回，绝不产生部分写入）：
 *   ① 存在性              → NOT_FOUND
 *   ② 在线且非故障        → DEVICE_OFFLINE
 *   ③ 参数键适用于该类型  → INVALID_PARAM（DeviceParamsFactory.paramKeysOf）
 *   ④ 值类型与区间合法    → INVALID_PARAM（ParamSchema.validateParamValue）
 *   ⑤ params.kind 与 type 一致（AT-04）→ INVALID_PARAM
 *   ⑥ 幂等：目标态 == 当前态 → NO_CHANGE，且**不写日志**（FR-02-08）
 *
 * 诊断类方法（`setDeviceStatus` / `setOnline`）**不做**在线性前置检查：
 * 它们本身就是把设备从离线/故障恢复回来的手段（Q-15），否则无法自证恢复路径。
 *
 * 写入路径：`MockDeviceAdapter.apply()` 产出新对象 → `LogService.appendOperation()`
 * （actor 由调用方给定）→ `AppDataRepository.commitDevices()`（唯一状态写入面）。
 * 本类**不**直接改 `state`，也不经过 `WriteGuard`（护栏 B-7：guard 只服务规则引擎）。
 *
 * 依据：design/系统架构设计.md 4.1 MI-02~06、4.2、4.4，PRD FR-02-02~10 / FR-04-13。
 */
import { IDeviceService } from './ServiceContracts';
import { LogService } from './LogService';
import { AppDataRepository } from '../store/AppDataRepository';
import { MockDeviceAdapter, DeviceCommandContext } from '../mock/MockDeviceAdapter';
import { Device } from '../model/Device';
import { DeviceParams, DeviceParamsFactory, ParamValue } from '../model/DeviceParams';
import { CommandResult, okResult, noChangeResult, failResult } from '../model/CommandResult';
import {
  DeviceType, DeviceStatus, DeviceCommand, LogActor, ParamKey, ResultCode
} from '../model/Enums';
import { AutomationRule } from '../model/AutomationRule';
import { AutomationAction } from '../model/AutomationAction';
import { Scene, DeviceStateSnapshot } from '../model/Scene';
import { OperationLog } from '../model/Logs';
import { validateParamValue } from '../common/ParamSchema';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';
import { messageOf } from '../common/ResultMessage';

/** 校验链单步结果（不抛异常，链式短路）。 */
interface ChainResult {
  ok: boolean;
  code: ResultCode;
  detail: string;
}

export class DeviceService implements IDeviceService {
  private static instance: DeviceService = new DeviceService();

  static getInstance(): DeviceService {
    return DeviceService.instance;
  }

  private lookupInstalled: boolean = false;

  private constructor() {
  }

  /**
   * 组合根注入（T3-05）：把只读设备查询交给 Mock 适配器。
   *
   * 由 `ServiceFacade.initialize()` 在 `EntryAbility.onCreate` 调用 **一次**；
   * 幂等，重复调用不产生副作用。放在这里而不是 `getInstance()` 里，
   * 是为了让「谁注入谁」在代码里**只有一处**可 grep（避免隐式自举）。
   */
  installMockLookup(): void {
    if (this.lookupInstalled) {
      return;
    }
    this.lookupInstalled = true;
    MockDeviceAdapter.getInstance().setLookup((id: string): Device | undefined => {
      return AppDataRepository.getInstance().findDevice(id);
    });
  }

  // ——————————————————————————————————————————————————————
  // MI-02 电源控制
  // ——————————————————————————————————————————————————————

  async setPower(id: string, on: boolean, actor: LogActor): Promise<CommandResult<Device>> {
    const chain: ChainResult = DeviceService.checkWritable(id);
    if (!chain.ok) {
      return failResult<Device>(chain.code, chain.detail);
    }
    const device: Device = AppDataRepository.getInstance().findDevice(id) as Device;
    const kind: ChainResult = DeviceService.checkKind(device);
    if (!kind.ok) {
      return failResult<Device>(kind.code, kind.detail);
    }
    if (device.powerOn === on) {
      return noChangeResult<Device>(device, '电源状态未变化');
    }
    const context: DeviceCommandContext = {
      device: device,
      command: on ? DeviceCommand.POWER_ON : DeviceCommand.POWER_OFF,
      powerOn: on,
      now: TimeUtil.now()
    };
    return this.execute(context, actor, on ? 'POWER_ON' : 'POWER_OFF');
  }

  // ——————————————————————————————————————————————————————
  // MI-03 参数设置（四步校验链 + 幂等）
  // ——————————————————————————————————————————————————————

  async setParam(
    id: string,
    key: ParamKey,
    value: ParamValue,
    actor: LogActor
  ): Promise<CommandResult<Device>> {
    // ① 存在性 / ② 在线非故障
    const chain: ChainResult = DeviceService.checkWritable(id);
    if (!chain.ok) {
      return failResult<Device>(chain.code, chain.detail);
    }
    const device: Device = AppDataRepository.getInstance().findDevice(id) as Device;
    // ③ 参数键适用于该设备类型
    const keys: ParamKey[] = DeviceParamsFactory.paramKeysOf(device.type);
    if (keys.indexOf(key) < 0) {
      return failResult<Device>(
        ResultCode.INVALID_PARAM, '参数键 ' + key + ' 不适用于 ' + device.type
      );
    }
    // ④ 值类型与区间
    if (validateParamValue(key, value) !== ResultCode.OK) {
      return failResult<Device>(
        ResultCode.INVALID_PARAM, '参数超出合法范围：' + key + '=' + String(value)
      );
    }
    // ⑤ params.kind 与 device.type 一致（AT-04）
    const kind: ChainResult = DeviceService.checkKind(device);
    if (!kind.ok) {
      return failResult<Device>(kind.code, kind.detail);
    }
    // ⑥ 幂等（不写日志）
    if (DeviceService.paramEquals(device, key, value)) {
      return noChangeResult<Device>(device, '参数 ' + key + ' 未变化');
    }
    const command: DeviceCommand = DeviceService.commandOf(key);
    const context: DeviceCommandContext = {
      device: device,
      command: command,
      powerOn: device.powerOn,
      now: TimeUtil.now(),
      paramKey: key as string,
      paramValue: value
    };
    return this.execute(context, actor, command + '=' + String(value));
  }

  // ——————————————————————————————————————————————————————
  // MI-04 添加设备
  // ——————————————————————————————————————————————————————

  async addDevice(type: DeviceType, name: string): Promise<CommandResult<Device>> {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) {
      return failResult<Device>(ResultCode.INVALID_PARAM, '设备名称不可为空');
    }
    const now: number = TimeUtil.now();
    const created: Device = {
      id: IdGenerator.device(),
      name: trimmed,
      type: type,
      powerOn: false,
      params: DeviceParamsFactory.defaults(type),
      online: true,
      status: DeviceStatus.IDLE,
      locked: type === DeviceType.DOOR_LOCK,
      createdAt: now,
      lastUpdated: now
    };
    const devices: Device[] = AppDataRepository.getInstance().listDevices();
    devices.push(created);
    AppDataRepository.getInstance().commitDevices(devices, 'device-add');
    DeviceService.writeOperation(LogActor.USER, created.id, 'ADD_DEVICE',
      DeviceService.EMPTY_SNAPSHOT, DeviceService.snapshotOf(created));
    return okResult<Device>(created, '已添加 ' + type + ' 设备');
  }

  // ——————————————————————————————————————————————————————
  // MI-05 删除设备 + 悬空引用清理（FR-02-05）
  // ——————————————————————————————————————————————————————

  async removeDevice(id: string): Promise<CommandResult<void>> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const target: Device | undefined = repo.findDevice(id);
    if (target === undefined) {
      return failResult<void>(ResultCode.NOT_FOUND, '设备不存在：' + id);
    }
    // ① 设备本体
    const kept: Device[] = [];
    const current: Device[] = repo.listDevices();
    for (let i = 0; i < current.length; i++) {
      if (current[i].id !== id) {
        kept.push(current[i]);
      }
    }
    repo.commitDevices(kept, 'device-remove');
    // ② 规则动作引用（动作被清空则停用规则并保留，绝不静默删除用户规则）
    let removedActions: number = 0;
    const rules: AutomationRule[] = repo.getState().rules;
    const nextRules: AutomationRule[] = [];
    let rulesChanged: boolean = false;
    for (let i = 0; i < rules.length; i++) {
      const rule: AutomationRule = rules[i];
      const keptActions: AutomationAction[] = [];
      for (let j = 0; j < rule.actions.length; j++) {
        if (rule.actions[j].targetDeviceId !== id) {
          keptActions.push(rule.actions[j]);
        }
      }
      const dropped: number = rule.actions.length - keptActions.length;
      if (dropped === 0) {
        nextRules.push(rule);
        continue;
      }
      rulesChanged = true;
      removedActions = removedActions + dropped;
      const disabled: boolean = keptActions.length === 0;
      const rebuilt: AutomationRule = {
        id: rule.id,
        name: rule.name,
        enabled: disabled ? false : rule.enabled,
        logic: rule.logic,
        conditions: rule.conditions.slice(),
        actions: keptActions,
        priority: rule.priority,
        lastSatisfied: false,
        lastTriggeredAt: rule.lastTriggeredAt,
        executionCount: rule.executionCount,
        createdAt: rule.createdAt,
        updatedAt: TimeUtil.now()
      };
      nextRules.push(rebuilt);
    }
    if (rulesChanged) {
      repo.commitRules(nextRules, 'device-remove-rule-cleanup');
    }
    // ③ 场景目标态引用
    const scenes: Scene[] = repo.getState().scenes;
    const nextScenes: Scene[] = [];
    let scenesChanged: boolean = false;
    for (let i = 0; i < scenes.length; i++) {
      const scene: Scene = scenes[i];
      const keptStates: DeviceStateSnapshot[] = [];
      for (let j = 0; j < scene.deviceStates.length; j++) {
        if (scene.deviceStates[j].deviceId !== id) {
          keptStates.push(scene.deviceStates[j]);
        }
      }
      if (keptStates.length === scene.deviceStates.length) {
        nextScenes.push(scene);
        continue;
      }
      scenesChanged = true;
      const rebuilt: Scene = {
        id: scene.id,
        name: scene.name,
        type: scene.type,
        deviceStates: keptStates,
        isPreset: scene.isPreset,
        returnSnapshot: scene.returnSnapshot.slice(),
        createdAt: scene.createdAt,
        updatedAt: TimeUtil.now()
      };
      nextScenes.push(rebuilt);
    }
    if (scenesChanged) {
      repo.commitScenes(nextScenes, 'device-remove-scene-cleanup');
    }
    // ④ 回寝快照引用（KEY-10 独立分区）
    const snapshot: DeviceStateSnapshot[] = repo.getState().returnSnapshot;
    const keptSnapshot: DeviceStateSnapshot[] = [];
    for (let i = 0; i < snapshot.length; i++) {
      if (snapshot[i].deviceId !== id) {
        keptSnapshot.push(snapshot[i]);
      }
    }
    if (keptSnapshot.length !== snapshot.length) {
      repo.commitReturnSnapshot(keptSnapshot);
    }
    // ⑤ 系统日志（actor=SYSTEM，说明清理了多少挂载引用）
    DeviceService.writeOperation(LogActor.SYSTEM, id, 'REMOVE_DEVICE',
      DeviceService.snapshotOf(target), DeviceService.EMPTY_SNAPSHOT);
    return okResult<void>(undefined,
      '已移除 ' + target.name + '，清理规则动作 ' + removedActions + ' 条及场景/快照引用');
  }

  // ——————————————————————————————————————————————————————
  // MI-06 / Q-15 诊断区：状态与在线性（不做在线性前置检查）
  // ——————————————————————————————————————————————————————

  async setDeviceStatus(
    id: string,
    status: DeviceStatus,
    actor: LogActor
  ): Promise<CommandResult<Device>> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const before: Device | undefined = repo.findDevice(id);
    if (before === undefined) {
      return failResult<Device>(ResultCode.NOT_FOUND, '设备不存在：' + id);
    }
    const applied: CommandResult<Device> = MockDeviceAdapter.getInstance().setDeviceStatus(id, status);
    if (!applied.success || applied.data === undefined) {
      return applied;
    }
    if (!applied.changed) {
      return applied;
    }
    this.commitReplaced(applied.data, 'device-status');
    DeviceService.writeOperation(actor, id, 'SET_STATUS:' + status,
      DeviceService.snapshotOf(before), DeviceService.snapshotOf(applied.data));
    return applied;
  }

  async setOnline(id: string, online: boolean, actor: LogActor): Promise<CommandResult<Device>> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const before: Device | undefined = repo.findDevice(id);
    if (before === undefined) {
      return failResult<Device>(ResultCode.NOT_FOUND, '设备不存在：' + id);
    }
    const applied: CommandResult<Device> = MockDeviceAdapter.getInstance().setOnline(id, online);
    if (!applied.success || applied.data === undefined) {
      return applied;
    }
    if (!applied.changed) {
      return applied;
    }
    this.commitReplaced(applied.data, 'device-online');
    DeviceService.writeOperation(actor, id, online ? 'SET_ONLINE:true' : 'SET_ONLINE:false',
      DeviceService.snapshotOf(before), DeviceService.snapshotOf(applied.data));
    return applied;
  }

  // ——————————————————————————————————————————————————————
  // 内部：执行 + 日志 + 提交
  // ——————————————————————————————————————————————————————

  /** 校验通过后的统一落地：适配器变换 → 操作日志 → 单一写入面提交。 */
  private execute(
    context: DeviceCommandContext,
    actor: LogActor,
    actionLabel: string
  ): CommandResult<Device> {
    const before: Device = context.device;
    const applied: CommandResult<Device> = MockDeviceAdapter.getInstance().apply(context);
    if (!applied.success || applied.data === undefined) {
      return applied;
    }
    const after: Device = applied.data;
    this.commitReplaced(after, 'device-command');
    DeviceService.writeOperation(actor, after.id, actionLabel,
      DeviceService.snapshotOf(before), DeviceService.snapshotOf(after));
    return okResult<Device>(after, actionLabel);
  }

  /** 用新设备对象替换权威数组中的同 id 元素（不改其它元素引用）。 */
  private commitReplaced(next: Device, reason: string): void {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const current: Device[] = repo.listDevices();
    const result: Device[] = [];
    for (let i = 0; i < current.length; i++) {
      result.push(current[i].id === next.id ? next : current[i]);
    }
    repo.commitDevices(result, reason);
  }

  // ——————————————————————————————————————————————————————
  // 内部：校验链原子步骤
  // ——————————————————————————————————————————————————————

  /** ① 存在性 → ② 在线且非故障。 */
  private static checkWritable(id: string): ChainResult {
    if (id.length === 0) {
      return DeviceService.fail(ResultCode.NOT_FOUND, '设备 id 为空');
    }
    const device: Device | undefined = AppDataRepository.getInstance().findDevice(id);
    if (device === undefined) {
      return DeviceService.fail(ResultCode.NOT_FOUND, '设备不存在：' + id);
    }
    if (!device.online || device.status === DeviceStatus.OFFLINE) {
      return DeviceService.fail(ResultCode.DEVICE_OFFLINE, device.name + ' 已离线');
    }
    if (device.status === DeviceStatus.FAULT) {
      return DeviceService.fail(ResultCode.DEVICE_OFFLINE, device.name + ' 处于故障态');
    }
    return DeviceService.pass();
  }

  /** ⑤ params.kind 与 device.type 一致性（AT-04）。 */
  private static checkKind(device: Device): ChainResult {
    if (device.params.kind !== device.type) {
      return DeviceService.fail(ResultCode.INVALID_PARAM, '设备参数结构与类型不一致');
    }
    return DeviceService.pass();
  }

  private static pass(): ChainResult {
    const result: ChainResult = { ok: true, code: ResultCode.OK, detail: '' };
    return result;
  }

  private static fail(code: ResultCode, detail: string): ChainResult {
    const result: ChainResult = { ok: false, code: code, detail: detail };
    return result;
  }

  /**
   * 幂等比较：当前参数值是否已等于目标值。
   * 判别收窄后逐类型比较，避免用序列化字符串比较带来的字段顺序陷阱。
   */
  private static paramEquals(device: Device, key: ParamKey, value: ParamValue): boolean {
    const params: DeviceParams = device.params;
    switch (params.kind) {
      case DeviceType.LIGHT:
        return key === ParamKey.BRIGHTNESS && typeof value === 'number' &&
          params.brightness === value;
      case DeviceType.AIR_CONDITIONER:
        if (key === ParamKey.TEMPERATURE) {
          return typeof value === 'number' && params.temperature === value;
        }
        return key === ParamKey.MODE && params.mode === value;
      case DeviceType.CURTAIN:
        return key === ParamKey.OPEN_PERCENT && typeof value === 'number' &&
          params.openPercent === value;
      case DeviceType.DOOR_LOCK:
        return key === ParamKey.LOCKED && typeof value === 'boolean' && params.locked === value;
      case DeviceType.FAN:
        return key === ParamKey.FAN_SPEED && typeof value === 'number' && params.fanSpeed === value;
      case DeviceType.SOCKET:
        return key === ParamKey.POWER_WATT && typeof value === 'number' &&
          params.powerWatt === value;
      default:
        return false;
    }
  }

  /** ParamKey → DeviceCommand（12 类命令中与参数相关的 5 类；仅用于日志标签与执行上下文）。 */
  private static commandOf(key: ParamKey): DeviceCommand {
    switch (key) {
      case ParamKey.BRIGHTNESS:
        return DeviceCommand.SET_BRIGHTNESS;
      case ParamKey.TEMPERATURE:
        return DeviceCommand.SET_TEMPERATURE;
      case ParamKey.MODE:
        return DeviceCommand.SET_MODE;
      case ParamKey.OPEN_PERCENT:
        return DeviceCommand.SET_OPEN_PERCENT;
      case ParamKey.LOCKED:
        return DeviceCommand.LOCK;
      case ParamKey.FAN_SPEED:
        return DeviceCommand.SET_FAN_SPEED;
      case ParamKey.POWER_WATT:
        return DeviceCommand.SET_POWER;
      default:
        return DeviceCommand.POWER_ON;
    }
  }

  // ——————————————————————————————————————————————————————
  // 内部：操作日志
  // ——————————————————————————————————————————————————————

  /** 空快照（新增前 / 删除后），与正常快照同构，便于日志消费方统一解析。 */
  private static readonly EMPTY_SNAPSHOT: string = '{"powerOn":false,"locked":false,"params":""}';

  private static writeOperation(
    actor: LogActor,
    deviceId: string,
    action: string,
    before: string,
    after: string
  ): void {
    const log: OperationLog = {
      id: IdGenerator.log(),
      timestamp: TimeUtil.now(),
      actor: actor,
      deviceId: deviceId,
      action: action,
      before: before,
      after: after,
      result: ResultCode.OK,
      message: messageOf(ResultCode.OK)
    };
    LogService.getInstance().appendOperation(log);
  }

  /**
   * 设备参数快照（写入 OperationLog 的 before/after）。
   * 用确定性字符串组装而非引入序列化依赖：params 以可读摘要承载在同一 JSON 字段中，
   * 阶段四 Serializer 接管后可直接替换为真实参数对象序列化。
   */
  private static snapshotOf(device: Device): string {
    return '{"powerOn":' + (device.powerOn ? 'true' : 'false') +
      ',"locked":' + (device.locked ? 'true' : 'false') +
      ',"params":"' + DeviceParamsFactory.describe(device.params) + '"}';
  }
}
