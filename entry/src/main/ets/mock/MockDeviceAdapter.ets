/**
 * 智寓 · Mock 设备适配器（MI-06 / Q-15）
 *
 * 职责：把「一条已通过校验链的命令」翻译成**新的 Device 对象**（不就地修改权威态）。
 * `DeviceService` 负责校验、日志与提交；本适配器只做纯变换，符合设计 4.2
 * 「mock 不得写状态」——它不 import 仓储、不调用任何 `commit*`。
 *
 * 设备查询通过 `setLookup()` 注入（`DeviceService` 在初始化时注入只读查询），
 * 以避免 `mock → store` 的模块耦合，同时保持 `setDeviceStatus(id, status)` 的
 * 规格签名（只接受 id）。
 *
 * 离线 / 故障语义：`apply()` 对 `online === false` 或 `status === FAULT` 直接返回
 * `DEVICE_OFFLINE`，**不产生任何参数变更**（FR-02-06）。
 *
 * 依据：design/系统架构设计.md 4.1 MI-06、Q-15、4.2 分层约束。
 */
import { Device } from '../model/Device';
import {
  DeviceParams, ParamValue,
  LightParams, AirConditionerParams, CurtainParams, DoorLockParams, FanParams, SocketParams
} from '../model/DeviceParams';
import { DeviceType, DeviceStatus, DeviceCommand, ResultCode, ACMode } from '../model/Enums';
import { CommandResult, okResult, noChangeResult, failResult } from '../model/CommandResult';
import { TimeUtil } from '../common/TimeUtil';

/** 只读设备查询（由 DeviceService 注入，避免 mock 层依赖 store）。 */
export type DeviceLookup = (id: string) => Device | undefined;

/** 一条命令的执行上下文：目标电源态 + 可选参数变更。 */
export interface DeviceCommandContext {
  device: Device;
  command: DeviceCommand;
  powerOn: boolean;
  now: number;
  /** 空/缺省表示本命令不改参数（如纯开关命令）。 */
  paramKey?: string;
  /** 与 paramKey 配套的目标值。 */
  paramValue?: ParamValue;
}

export class MockDeviceAdapter {
  private static instance: MockDeviceAdapter = new MockDeviceAdapter();

  private lookup: DeviceLookup | undefined = undefined;

  static getInstance(): MockDeviceAdapter {
    return MockDeviceAdapter.instance;
  }

  private constructor() {
  }

  /** 注入只读查询（DeviceService 初始化时调用一次）。 */
  setLookup(lookup: DeviceLookup): void {
    this.lookup = lookup;
  }

  /**
   * 执行一条命令：返回**新对象**，`Device` 与 `DeviceParams` 均为复制，
   * 传入的 `ctx.device` 不会被修改（B6）。
   */
  apply(ctx: DeviceCommandContext): CommandResult<Device> {
    const device: Device = ctx.device;
    if (!device.online || device.status === DeviceStatus.OFFLINE) {
      return failResult<Device>(ResultCode.DEVICE_OFFLINE, device.name + ' 已离线');
    }
    if (device.status === DeviceStatus.FAULT) {
      return failResult<Device>(ResultCode.DEVICE_OFFLINE, device.name + ' 处于故障态');
    }
    const params: DeviceParams = MockDeviceAdapter.applyParam(
      device.params, ctx.paramKey, ctx.paramValue
    );
    const locked: boolean = MockDeviceAdapter.nextLocked(device.locked, ctx.paramKey, ctx.paramValue);
    const next: Device = {
      id: device.id,
      name: device.name,
      type: device.type,
      powerOn: ctx.powerOn,
      params: params,
      online: true,
      status: ctx.powerOn ? DeviceStatus.RUNNING : DeviceStatus.IDLE,
      locked: locked,
      createdAt: device.createdAt,
      lastUpdated: ctx.now > 0 ? ctx.now : TimeUtil.now()
    };
    return okResult<Device>(next, 'Mock 执行 ' + ctx.command);
  }

  /** 模拟置设备状态（诊断区）：OFFLINE 同步 `online=false`，其余同步 `online=true`。 */
  setDeviceStatus(id: string, status: DeviceStatus): CommandResult<Device> {
    const device: Device | undefined = this.resolve(id);
    if (device === undefined) {
      return failResult<Device>(ResultCode.NOT_FOUND, '设备不存在：' + id);
    }
    const online: boolean = status !== DeviceStatus.OFFLINE;
    if (device.status === status && device.online === online) {
      return noChangeResult<Device>(device, '状态已是 ' + status);
    }
    const next: Device = MockDeviceAdapter.withStatus(device, status, online);
    return okResult<Device>(next, '模拟状态 ' + status);
  }

  /** 模拟在线/离线（诊断区）：离线时状态同步为 OFFLINE，恢复在线时回到 IDLE。 */
  setOnline(id: string, online: boolean): CommandResult<Device> {
    const device: Device | undefined = this.resolve(id);
    if (device === undefined) {
      return failResult<Device>(ResultCode.NOT_FOUND, '设备不存在：' + id);
    }
    if (device.online === online) {
      return noChangeResult<Device>(device, '在线状态未变化');
    }
    const status: DeviceStatus = online ? DeviceStatus.IDLE : DeviceStatus.OFFLINE;
    const next: Device = MockDeviceAdapter.withStatus(device, status, online);
    return okResult<Device>(next, online ? '已恢复在线' : '已置为离线');
  }

  // ——————————————————————————————————————————————————————
  // 内部纯变换
  // ——————————————————————————————————————————————————————

  private resolve(id: string): Device | undefined {
    const lookup: DeviceLookup | undefined = this.lookup;
    if (lookup === undefined) {
      return undefined;
    }
    return lookup(id);
  }

  /** 复制设备并按新状态改写 status / online（不修改入参）。 */
  private static withStatus(device: Device, status: DeviceStatus, online: boolean): Device {
    const next: Device = {
      id: device.id,
      name: device.name,
      type: device.type,
      powerOn: device.powerOn,
      params: MockDeviceAdapter.applyParam(device.params, undefined, undefined),
      online: online,
      status: status,
      locked: device.locked,
      createdAt: device.createdAt,
      lastUpdated: TimeUtil.now()
    };
    return next;
  }

  /** 按命令参数键生成新的参数对象（判别收窄，AT-04；不修改入参）。 */
  private static applyParam(
    params: DeviceParams,
    paramKey: string | undefined,
    paramValue: ParamValue | undefined
  ): DeviceParams {
    switch (params.kind) {
      case DeviceType.LIGHT: {
        const next: LightParams = { kind: DeviceType.LIGHT, brightness: params.brightness };
        if (paramKey === 'brightness' && typeof paramValue === 'number') {
          next.brightness = Math.round(paramValue);
        }
        return next;
      }
      case DeviceType.AIR_CONDITIONER: {
        const next: AirConditionerParams = {
          kind: DeviceType.AIR_CONDITIONER,
          temperature: params.temperature,
          mode: params.mode
        };
        if (paramKey === 'temperature' && typeof paramValue === 'number') {
          next.temperature = Math.round(paramValue);
        }
        if (paramKey === 'mode' && typeof paramValue === 'string') {
          next.mode = paramValue as ACMode;
        }
        return next;
      }
      case DeviceType.CURTAIN: {
        const next: CurtainParams = { kind: DeviceType.CURTAIN, openPercent: params.openPercent };
        if (paramKey === 'openPercent' && typeof paramValue === 'number') {
          next.openPercent = Math.round(paramValue);
        }
        return next;
      }
      case DeviceType.DOOR_LOCK: {
        const next: DoorLockParams = { kind: DeviceType.DOOR_LOCK, locked: params.locked };
        if (paramKey === 'locked' && typeof paramValue === 'boolean') {
          next.locked = paramValue;
        }
        return next;
      }
      case DeviceType.FAN: {
        const next: FanParams = { kind: DeviceType.FAN, fanSpeed: params.fanSpeed };
        if (paramKey === 'fanSpeed' && typeof paramValue === 'number') {
          next.fanSpeed = Math.round(paramValue);
        }
        return next;
      }
      case DeviceType.SOCKET: {
        const next: SocketParams = { kind: DeviceType.SOCKET, powerWatt: params.powerWatt };
        if (paramKey === 'powerWatt' && typeof paramValue === 'number') {
          next.powerWatt = paramValue;
        }
        return next;
      }
      default: {
        const fallback: LightParams = { kind: DeviceType.LIGHT, brightness: 0 };
        return fallback;
      }
    }
  }

  /** 门锁锁定态与 `params.locked` 保持一致（Device.locked 与 DoorLockParams.locked 双写）。 */
  private static nextLocked(
    current: boolean,
    paramKey: string | undefined,
    paramValue: ParamValue | undefined
  ): boolean {
    if (paramKey === 'locked' && typeof paramValue === 'boolean') {
      return paramValue;
    }
    return current;
  }
}
